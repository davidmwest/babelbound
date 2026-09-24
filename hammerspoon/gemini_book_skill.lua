-- Pure AX inspection helpers. No typing, clicks, network access, or changes.
local C=require("gemini_book_core")
local S={}
local function attr(e,k)
    local ok,v=pcall(function()return e:attributeValue(k)end)
    if ok then return v end
end
local function frame(e)
    local f=attr(e,"AXFrame")
    if f and f.x and f.y and f.w and f.h then return f end
    local p,z=attr(e,"AXPosition"),attr(e,"AXSize")
    if p and z then return {x=p.x,y=p.y,w=z.w or z.width,h=z.h or z.height} end
end
local function labels(e)
    local t={}
    for _,k in ipairs({"AXTitle","AXDescription","AXHelp","AXValue"})do
        local v=attr(e,k)
        if type(v)=="string" and #v<=120 then t[#t+1]=v end
    end
    return t
end
function S.matchesLabel(label,skill)
    if type(label)~="string" then return false end
    local s=C.normalizedDraft(label):lower()
    local n=skill:gsub("^/", ""):lower()
    if s==n or s=="/"..n then return true end
    -- Allow a decorative emoji/punctuation, but no additional words. In Lua,
    -- %w is ASCII here; this is intentionally for the configured English ln.
    local escaped=n:gsub("([^%w])","%%%1")
    return s:match("^%W*"..escaped.."%W*$")~=nil
end
local function hasPress(e)
    local ok,a=pcall(function()return e:actionNames()end)
    if not ok or type(a)~="table"then return false end
    for _,v in ipairs(a)do if v=="AXPress" then return true end end
    return false
end
local function contains(r,p)
    return r and p.x>=r.x and p.x<=r.x+r.w and p.y>=r.y and p.y<=r.y+r.h
end
local function visible(e,f,p)
    if not f or not f.w or not f.h or f.w<=0 or f.h<=0 then return false end
    if attr(e,"AXHidden")==true or attr(e,"AXEnabled")==false then return false end
    return contains(p,{x=f.x+f.w/2,y=f.y+f.h/2})
end
function S.snapshot(elements, params)
    local out={}
    for _,e in ipairs(elements)do
        local f=frame(e)
        local role=attr(e,"AXRole")
        if role~="AXTextArea" and role~="AXTextField" and visible(e,f,params.panel)then
            local name
            for _,v in ipairs(labels(e))do if S.matchesLabel(v,params.skill)then name=v;break end end
            if name and f.h<=100 and f.w<=650 and f.y+f.h<=params.editorTop+4 then
                local center={x=f.x+f.w/2,y=f.y+f.h/2}
                local target=e
                for _=1,6 do
                    if not target then break end
                    local tf=frame(target)
                    local tr=attr(target,"AXRole")
                    if visible(target,tf,params.panel) and tf.h<=100 and tf.w<=700
                        and contains(tf,center) and hasPress(target)
                        and (tr=="AXMenuItem" or tr=="AXRow" or tr=="AXCell"
                            or tr=="AXButton" or tr=="AXGroup")then
                        local item={element=target,labelElement=e,center=center,label=name,
                            role=tr,frame={x=tf.x,y=tf.y,w=tf.w,h=tf.h}}
                        -- Semantic + geometric signature excludes already-visible
                        -- conversation chips even when AX handles are recreated.
                        item.signature=string.format("%s|%s|%.1f|%.1f|%.1f|%.1f",
                            tr,C.normalizedDraft(name),tf.x,tf.y,tf.w,tf.h)
                        local duplicate=false
                        for _,old in ipairs(out)do
                            if old.element==target or old.signature==item.signature then duplicate=true;break end
                        end
                        if not duplicate then out[#out+1]=item end
                        break
                    end
                    target=attr(target,"AXParent")
                end
            end
        end
    end
    return out
end
function S.newCandidates(current,baseline)
    local out={}
    for _,item in ipairs(current)do
        local old=false
        for _,b in ipairs(baseline or {})do
            if item.element==b.element or item.signature==b.signature then old=true;break end
        end
        if not old then out[#out+1]=item end
    end
    return out
end
function S.stillPressable(item,params)
    if not item or not item.element or not item.labelElement then return false end
    local current=S.snapshot({item.labelElement},params)
    for _,c in ipairs(current)do
        if c.element==item.element and c.signature==item.signature then return true end
    end
    return false
end
function S.summary(items)
    local out={}
    for _,v in ipairs(items)do out[#out+1]={label=v.label,role=v.role,frame=v.frame,signature=v.signature}end
    return out
end
return S
