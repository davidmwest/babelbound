-- Focus only the calibrated book's AXWebArea. Never presses a control or sends
-- a mouse/keyboard event. Keep live AX objects in transient state, not traces.
local M={}
local function call(object,method,...)
    if not object then return nil end
    local ok,value=pcall(object[method],object,...)
    if ok then return value end
end
local function attr(e,key)return call(e,"attributeValue",key)end
local function pid(e)return call(e,"pid")end
local function frame(e)
    local f=attr(e,"AXFrame")
    if not f then
        local p,s=attr(e,"AXPosition"),attr(e,"AXSize")
        if p and s then f={x=p.x,y=p.y,w=s.w or s.width,h=s.h or s.height}end
    end
    if not f or type(f.x)~="number" or type(f.y)~="number"
        or type(f.w)~="number" or type(f.h)~="number" then return nil end
    return {x=f.x,y=f.y,w=f.w,h=f.h}
end
local function description(e)
    if not e then return {present=false}end
    return {present=true,role=attr(e,"AXRole"),pid=pid(e),
        focused=attr(e,"AXFocused"),frame=frame(e)}
end
local function validArea(area,cal,expectedPID)
    if not area or attr(area,"AXRole")~="AXWebArea" or pid(area)~=expectedPID
        or attr(area,"AXEnabled")==false then return nil,"The book web area is unavailable."end
    local title=attr(area,"AXTitle")
    if type(title)~="string" or title=="" or type(cal.windowTitle)~="string"
        or cal.windowTitle:sub(1,#title)~=title then
        return nil,"The web-area title does not match the calibrated book."
    end
    local f,c,w=frame(area),cal.crop,cal.windowFrame
    if not f or f.w<=0 or f.h<=0 or f.x<w.x-2 or f.y<w.y-2
        or f.x+f.w>cal.panel.x+2 or f.y+f.h>w.y+w.h+2
        or f.x>c.x+2 or f.y>c.y+2 or f.x+f.w<c.x+c.w-2 or f.y+f.h<c.y+c.h-2
        or cal.next.x<f.x or cal.next.x>f.x+f.w or cal.next.y<f.y or cal.next.y>f.y+f.h then
        return nil,"The web area does not cover the calibrated book pane."
    end
    return {pid=expectedPID,title=title,frame=f}
end
local function focusedWithin(focused,area,expectedPID)
    local e=focused
    for _=1,16 do
        if not e or pid(e)~=expectedPID then return false end
        if e==area then return attr(focused,"AXFocused")~=false end
        e=attr(e,"AXParent")
    end
    return false
end
local function appFor(hs,bundle,expectedPID)
    local app=hs.application.frontmostApplication()
    if not app or app:bundleID()~=bundle or (expectedPID and app:pid()~=expectedPID) then return nil end
    return app
end
function M.prepare(hs,cal,bundle,at)
    local evidence={startedAt=at,requested=false,ready=false}
    local function fail(why)evidence.error=why;return nil,why,evidence end
    local app=appFor(hs,bundle)
    if not app then return fail("Chrome is no longer frontmost.")end
    local expectedPID=app:pid()
    local ok,hit=pcall(function()
        return hs.axuielement.systemWideElement():elementAtPosition(cal.next.x,cal.next.y)
    end)
    if not ok or not hit then return fail("Cannot locate the book under the forward target.")end
    local area,e= nil,hit
    for depth=1,12 do
        if not e or pid(e)~=expectedPID then break end
        if attr(e,"AXRole")=="AXWebArea" then area=e;evidence.ancestorDepth=depth;break end
        e=attr(e,"AXParent")
    end
    local book,why=validArea(area,cal,expectedPID)
    if not book then return fail(why)end
    evidence.book=book
    local root=hs.axuielement.applicationElement(app)
    local focused=attr(root,"AXFocusedUIElement")
    evidence.before=description(focused)
    local state={area=area,pid=expectedPID,bundle=bundle,startedAt=at,evidence=evidence}
    if focusedWithin(focused,area,expectedPID) then
        evidence.alreadyFocused=true
    else
        if call(area,"isAttributeSettable","AXFocused")~=true then
            return fail("The book web area does not support direct focus.")
        end
        evidence.requested=true
        if not call(area,"setAttributeValue","AXFocused",true) then
            return fail("Chrome did not accept direct focus on the book web area.")
        end
    end
    return state,nil,evidence
end
function M.check(hs,cal,state,at)
    if not state then return false,"Missing book-focus state."end
    local evidence=state.evidence
    evidence.lastCheckedAt=at
    local app=appFor(hs,state.bundle,state.pid)
    if not app then return false,"Chrome changed during book focusing."end
    local book,why=validArea(state.area,cal,state.pid)
    if not book then return false,why end
    local root=hs.axuielement.applicationElement(app)
    local focused=attr(root,"AXFocusedUIElement")
    evidence.after=description(focused)
    evidence.ready=focusedWithin(focused,state.area,state.pid)
    if evidence.ready then evidence.verifiedAt=at end
    return evidence.ready
end
return M
