-- Bounded, asynchronous AXChildren-only traversal. No input, clipboard or UI actions.
-- Deliberately never follows AXParent, AXLinkedUIElements, AXWindow, etc. during a scan.
local A={}
local function attr(e,k)
    if not e then return nil end
    local ok,v=pcall(function()return e:attributeValue(k)end)
    if ok then return v end
end
local function frame(e)
    local f=attr(e,"AXFrame")
    if f and f.x and f.y and f.w and f.h then return f end
    local p,s=attr(e,"AXPosition"),attr(e,"AXSize")
    if p and s then return {x=p.x,y=p.y,w=s.w or s.width,h=s.h or s.height} end
end
local function contains(r,p)
    return r and r.w and r.h and p.x>=r.x and p.x<=r.x+r.w and p.y>=r.y and p.y<=r.y+r.h
end
-- Walk only a short parent chain from the calibrated composer. Never fall back
-- to searching a Chrome window or application when the expected pane is missing.
function A.roots(seed,cal,pid)
    local composer,panel
    local wf=cal.windowFrame
    local width=wf.x+wf.w-cal.panel.x
    local seen={}
    for _=1,14 do
        if not seed or seen[seed]then break end
        seen[seed]=true
        local ok,p=pcall(function()return seed:pid()end)
        if not ok or p~=pid then break end
        local role=attr(seed,"AXRole")
        if role=="AXApplication" or role=="AXWindow"then break end
        local f=frame(seed)
        if f and f.w and f.h and f.w>=100 and f.w<=width+96
            and f.x>=cal.panel.x-48 and f.x+f.w<=wf.x+wf.w+16
            and f.y>=cal.panel.y-48 and f.y+f.h<=wf.y+wf.h+16
            and contains(f,cal.input)
            and (role=="AXGroup" or role=="AXWebArea" or role=="AXSplitGroup" or role=="AXScrollArea")then
            if f.h>=40 and f.h<=360 then composer=seed end
            if f.h>360 and f.h>=wf.h*0.45 then panel=seed end
        end
        seed=attr(seed,"AXParent")
    end
    return composer,panel
end
function A.scan(root,opts,predicate,done)
    assert(root and type(predicate)=="function" and type(done)=="function")
    opts=opts or {}
    local clock=opts.clock or hs.timer.secondsSinceEpoch
    local schedule=opts.schedule or hs.timer.doAfter
    local search={active=true,visited=0,matches=0,started=clock(),root=root,
        prunedText=0,prunedEditors=0,prunedHidden=0,visibleChildLists=0}
    local stack,seen,results={{element=root,depth=0,root=root}},nil,nil
    -- Lua keeps these separate to avoid creating accidental global variables.
    seen={};results={}
    function search:isRunning()return self.active end
    function search:cancel()self.active=false;if self.timer then self.timer:stop()end end
    local function finish(status)
        if not search.active then return end
        search.active=false;search.elapsed=clock()-search.started
        done(status,results,search)
    end
    local function step()
        if not search.active then return end
        if opts.valid and not opts.valid()then search:cancel();return end
        local ok,err=xpcall(function()
            local start=clock();local processed=0
            while #stack>0 do
                if clock()-search.started>(opts.timeout or 12)then finish("timeout");return end
                if processed>=(opts.sliceNodes or 12) or clock()-start>(opts.sliceSeconds or 0.02)then break end
                local item=table.remove(stack);local e=item.element
                if not seen[e]then
                    seen[e]=true;search.visited=search.visited+1;processed=processed+1
                    if search.visited>(opts.maxNodes or 6000)then finish("node-limit");return end
                    -- One role read for this visit, shared with its predicate.
                    -- This value is never retained across scans or used to
                    -- suppress a node, quota check, or live model readback.
                    if opts.controlScan then item.knownRole=attr(e,"AXRole")end
                    -- Preserve the actual child path used to discover this element. This
                    -- is scan-local evidence, not a cached model or a new AXParent query.
                    if predicate(e,item)then results[#results+1]=e;search.matches=#results end
                    -- A control scan does not need to expand the hundreds of
                    -- formatting descendants of a text node whose AXValue has
                    -- already been inspected, or any user draft contents. Keep
                    -- the text node itself in the predicate for quota notices.
                    -- Do not prune generic groups by geometry: their children
                    -- may extend outside their own frame.
                    local children
                    local skip=false
                    if opts.controlScan then
                        local role=item.knownRole
                        if attr(e,"AXHidden")==true then
                            skip=true;search.prunedHidden=search.prunedHidden+1
                        elseif role=="AXTextArea" or role=="AXTextField" then
                            skip=true;search.prunedEditors=search.prunedEditors+1
                        elseif role=="AXStaticText" then
                            local value=attr(e,"AXValue")
                            if type(value)=="string" and value:match("%S") then
                                skip=true;search.prunedText=search.prunedText+1
                            end
                        end
                        -- Only a scroll area's explicitly exposed visible-child
                        -- list can replace its full list. Unsupported/nil means
                        -- fall back to AXChildren; never infer visibility from
                        -- clipping coordinates alone.
                        if not skip and role=="AXScrollArea" then
                            local visible=attr(e,"AXVisibleChildren")
                            if type(visible)=="table" then
                                children=visible
                                search.visibleChildLists=search.visibleChildLists+1
                            end
                        end
                    end
                    if not skip and children==nil then children=attr(e,"AXChildren")end
                    if type(children)=="table" and #children>0 then
                        if item.depth>=(opts.maxDepth or 40)then finish("depth-limit");return end
                        -- Reverse document order (latest messages first), but complete
                        -- the scoped scan before interpreting absence as an idle state.
                        for _,child in ipairs(children)do
                            if child and not seen[child]then stack[#stack+1]={element=child,depth=item.depth+1,parent=item,root=root}end
                        end
                    end
                end
            end
            if #stack==0 then finish("completed")
            else search.timer=schedule(0.01,step)end
        end,debug.traceback)
        if not ok then search.error=err;finish("error")end
    end
    -- Always asynchronous, including empty trees, so callers can save the handle.
    search.timer=schedule(0.01,step)
    return search
end
-- Identify the CURRENT model control without assuming the text composer is
-- compact. A long inline prompt grows beyond roots()' compact-composer bound,
-- but the model picker remains in the calibrated bottom toolbar. This fallback
-- accepts only a live control with Chrome's explicit "currently ..." caption,
-- NOT a bare model name in a response/draft/menu. No cached model, UI action,
-- new calibration, or whole-window scan is involved.
function A.readModelControl(e,opts)
    local cal,composer,panel=opts.cal,opts.composer,opts.panel
    local parse,normalize=opts.parseLabel,opts.normalize
    if not e or not panel or not cal or not cal.input or not cal.windowFrame then
        return nil,"missing-current-sidebar"
    end
    -- AX reads cross a process boundary. Most scanned nodes are history groups
    -- or unrelated text; reject those before reading shared scope geometry,
    -- labels or ancestry. Candidates still undergo every original live check.
    local role=opts.knownRole or attr(e,"AXRole")
    local control=role=="AXPopUpButton" or role=="AXMenuButton" or role=="AXButton"
    local caption=role=="AXStaticText"
    if not control and not caption then return nil,"not-model-control-role" end
    local f=frame(e)
    if not f or not f.w or not f.h or f.w<=0 or f.h<=0 or f.h>65 or f.w>220 then
        return nil,"not-a-compact-control"
    end
    local pt={x=f.x+f.w/2,y=f.y+f.h/2}
    local wf=cal.windowFrame
    local footer={x=cal.panel.x-5,y=cal.input.y-12,
        w=wf.x+wf.w-cal.panel.x+10,h=wf.y+wf.h+5-(cal.input.y-12)}
    if not contains(footer,pt) then
        return nil,"outside-current-composer-footer"
    end
    local labels={}
    for _,k in ipairs({"AXTitle","AXValue","AXDescription","AXHelp"})do
        local v=attr(e,k)
        if type(v)=="string" and #v<=120 then
            local model=parse(v)
            if model then labels[#labels+1]={model=model,normalized=normalize(v)} end
        end
    end
    if #labels==0 then return nil,"unrecognized-model-label" end
    local cf,pf=frame(composer),frame(panel)
    if not contains(pf,pt) then return nil,"outside-current-composer-footer" end
    if attr(e,"AXHidden")==true or attr(e,"AXEnabled")==false then
        return nil,"hidden-or-disabled-control"
    end
    -- Require real ancestry in this sidebar. Screen coordinates alone do not
    -- authorize a match; editor contents and open model menus are excluded.
    local node,seen=e,{}
    local reachedPanel,reachedComposer=false,false
    local pidOK,pid=pcall(function()return panel:pid()end)
    if not pidOK or not pid then return nil,"unknown-sidebar-process" end
    for _=1,18 do
        if not node or seen[node] then break end
        seen[node]=true
        local ok,npid=pcall(function()return node:pid()end)
        if not ok or npid~=pid then return nil,"different-or-unknown-process" end
        local r=attr(node,"AXRole")
        if r=="AXTextArea" or r=="AXTextField" or r=="AXComboBox" then
            return nil,"inside-draft-editor"
        end
        if r=="AXMenu" or r=="AXMenuItem" or r=="AXList" or r=="AXListBox" then
            return nil,"inside-open-picker-or-list"
        end
        if attr(node,"AXHidden")==true then return nil,"hidden-ancestor" end
        if node==composer then reachedComposer=true end
        if node==panel then reachedPanel=true;break end
        node=attr(node,"AXParent")
    end
    local ancestryEvidence="parent-chain"
    if not reachedPanel and opts.scanPath then
        -- 1.1.17: The current sidebar scan already discovered this control by
        -- following AXChildren. Its reverse AXParent chain may be incomplete,
        -- differently wrapped, or deeper than the short reverse-walk bound.
        -- Validate the recorded forward path instead of discarding real Pro
        -- evidence. Never accept geometry alone or a path from a different pane.
        local path=opts.scanPath
        if path.element~=e or path.root~=panel then
            return nil,"not-in-current-sidebar-ancestry"
        end
        local seenPath={}
        local depth=path.depth
        if type(depth)~="number" or depth<0 or depth>40 then
            return nil,"invalid-scanned-sidebar-path"
        end
        reachedComposer=false
        for _=1,41 do
            if not path or seenPath[path] or path.root~=panel or path.depth~=depth then
                return nil,"invalid-scanned-sidebar-path"
            end
            seenPath[path]=true
            local item=path.element
            if not item then return nil,"invalid-scanned-sidebar-path" end
            local ok,npid=pcall(function()return item:pid()end)
            if not ok or npid~=pid then return nil,"different-or-unknown-process" end
            local r=attr(item,"AXRole")
            if r=="AXTextArea" or r=="AXTextField" or r=="AXComboBox" then
                return nil,"inside-draft-editor"
            end
            if r=="AXMenu" or r=="AXMenuItem" or r=="AXList" or r=="AXListBox" then
                return nil,"inside-open-picker-or-list"
            end
            if r=="AXWindow" or r=="AXApplication" then
                return nil,"invalid-scanned-sidebar-path"
            end
            if attr(item,"AXHidden")==true then return nil,"hidden-ancestor" end
            if item==composer then reachedComposer=true end
            if item==panel then
                if depth~=0 or path.parent then return nil,"invalid-scanned-sidebar-path" end
                reachedPanel=true;ancestryEvidence="scanned-children-path";break
            end
            path=path.parent;depth=depth-1
        end
    end
    if not reachedPanel then return nil,"not-in-current-sidebar-ancestry" end
    local compactContext=cf and reachedComposer and contains(cf,pt)
    local values={}
    for _,label in ipairs(labels)do
        local explicit=control and label.normalized:match("^open mode picker,%s*currently%s+.+$")
            or (opts.namedPicker and role=="AXPopUpButton")
        if explicit or compactContext then values[label.model]=explicit and "live-footer-caption" or "compact-composer-caption" end
    end
    local result,evidence,count=nil,nil,0
    for model,how in pairs(values)do result,evidence,count=model,how,count+1 end
    if count>1 then return nil,"conflicting-control-captions" end
    if result then return result,evidence.."/"..ancestryEvidence end
    return nil,compactContext and "unrecognized-model-label" or "explicit-current-caption-required"
end
return A
