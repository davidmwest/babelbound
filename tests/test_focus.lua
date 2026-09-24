local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local base=paths.root..'hammerspoon/'
local focus=assert(loadfile(base..'gemini_book_focus.lua'))()
assert(loadfile(base..'gemini_book.lua'))
local count=0
local function check(value,why)assert(value,why);count=count+1 end
local function fixture()
    local t={setCalls=0,reads=0,bundle='com.google.Chrome'}
    local function node(values,parent)
        local n={v=values or {},parent=parent,process=321}
        function n:pid()return self.process end
        function n:attributeValue(k)t.reads=t.reads+1;if k=='AXParent'then return self.parent end;return self.v[k]end
        function n:isAttributeSettable(k)return k=='AXFocused' and self.settable~=false end
        function n:setAttributeValue(k,v)
            check(k=='AXFocused' and v==true,'Only a direct focus assignment is allowed')
            t.setCalls=t.setCalls+1;if t.setError then return nil,'rejected'end
            return self
        end
        function n:performAction()error('No AX action is allowed')end
        return n
    end
    t.node=node
    t.area=node({AXRole='AXWebArea',AXTitle='My Book',AXEnabled=true,AXFocused=false,
        AXFrame={x=20,y=110,w=1480,h=1090}})
    local e=t.area
    for i=1,4 do e=node({AXRole='AXGroup'},e)end
    t.hit=node({AXRole='AXImage'},e)
    t.other=node({AXRole='AXGroup',AXFocused=true,AXFrame={x=1550,y=110,w=700,h=1000}})
    t.root=node({AXFocusedUIElement=t.other})
    t.cal={windowTitle='My Book - Google Chrome',windowFrame={x=10,y=30,w=2290,h=1200},
        panel={x=1520,y=110},crop={x=30,y=125,w=1460,h=1060},next={x=95,y=614}}
    t.app={bundleID=function()return t.bundle end,pid=function()return 321 end}
    t.hs={application={frontmostApplication=function()return not t.noApp and t.app or nil end},
        axuielement={applicationElement=function()return t.root end,
            systemWideElement=function()return {elementAtPosition=function()
                if t.hitError then error('AX unavailable')end;return t.hit
            end}end}}
    function t.prepare()return focus.prepare(t.hs,t.cal,'com.google.Chrome',0)end
    function t.activate(node)
        t.root.v.AXFocusedUIElement=node or t.area
        t.root.v.AXFocusedUIElement.v.AXFocused=true
    end
    return t
end
do
    local t=fixture();local state,err,evidence=t.prepare()
    check(state and not err and t.setCalls==1,'One direct focus request is prepared')
    check(evidence.ancestorDepth==6 and evidence.book.title=='My Book','Bounded hit ancestry identifies the actual book area')
    check(not focus.check(t.hs,t.cal,state,.05),'A successful AX assignment is not assumed to mean focus is ready')
    t.activate()
    check(focus.check(t.hs,t.cal,state,.1),'Readback of book focus establishes readiness')
    check(evidence.ready and evidence.verifiedAt==.1 and evidence.after.pid==321,'Primitive readiness evidence is retained')
    t.root.v.AXFocusedUIElement=t.other
    check(not focus.check(t.hs,t.cal,state,.2),'Focus loss before click is detected')
    check(t.setCalls==1,'Polling never requests focus again')
end
for _,case in ipairs({
    {'foreign app',function(t)t.bundle='foreign'end},
    {'no app',function(t)t.noApp=true end},
    {'missing hit',function(t)t.hit=nil end},
    {'failed hit',function(t)t.hitError=true end},
    {'foreign hit PID',function(t)t.hit.process=999 end},
    {'foreign ancestor PID',function(t)t.hit.parent.process=999 end},
    {'wrong title',function(t)t.area.v.AXTitle='Other Book'end},
    {'empty title',function(t)t.area.v.AXTitle=''end},
    {'disabled area',function(t)t.area.v.AXEnabled=false end},
    {'sidebar overlap',function(t)t.area.v.AXFrame.w=2200 end},
    {'crop not enclosed',function(t)t.area.v.AXFrame.w=100 end},
    {'outside window',function(t)t.area.v.AXFrame.x=-10 end},
    {'missing geometry',function(t)t.area.v.AXFrame=nil end},
    {'not focus settable',function(t)t.area.settable=false end},
    {'too deep',function(t)local e=t.area;for i=1,13 do e=t.node({AXRole='AXGroup'},e)end;t.hit=e end},
    {'cyclic parent',function(t)t.hit.parent=t.hit end},
})do
    local t=fixture();case[2](t);local state,err,evidence=t.prepare()
    check(not state and err and evidence.error,case[1]..' fails closed')
    check(t.setCalls==0,case[1]..' performs no focus mutation')
    check(t.reads<150,case[1]..' stays bounded')
end
do
    local t=fixture();t.setError=true;local state,err=t.prepare()
    check(not state and err and t.setCalls==1,'A rejected focus assignment is not retried')
    t=fixture();t.activate();state,err=t.prepare()
    check(state and not err and t.setCalls==0 and state.evidence.alreadyFocused,'Already focused book needs no focus mutation')
    local child=t.node({AXRole='AXGroup',AXFocused=true},t.area);t.activate(child)
    check(focus.check(t.hs,t.cal,state,.1),'Focused descendant of the same book is accepted')
    child.process=999
    check(not focus.check(t.hs,t.cal,state,.2),'Foreign process focus with misleading ancestry is rejected')
    t=fixture();state=t.prepare();t.activate();t.area.v.AXTitle='Other Book'
    local ready,why=focus.check(t.hs,t.cal,state,.1)
    check(not ready and why,'Replaced area identity fails final verification')
    t=fixture();state=t.prepare();t.activate();t.bundle='other'
    ready,why=focus.check(t.hs,t.cal,state,.1)
    check(not ready and why,'Foreground changes fail final verification')
end
do
    local t=fixture();local f=t.area.v.AXFrame;t.area.v.AXFrame=nil
    t.area.v.AXPosition={x=f.x,y=f.y};t.area.v.AXSize={width=f.w,height=f.h}
    local state=t.prepare();check(state and state.evidence.book.frame.w==1480,'AXPosition/AXSize geometry is supported')
    local function plain(v)
        if type(v)=='table'then
            check(not getmetatable(v),'Evidence has no AX/geometry metatables')
            for k,x in pairs(v)do check(type(k)=='string' or type(k)=='number','Primitive evidence keys');plain(x)end
        else check(type(v)=='string' or type(v)=='number' or type(v)=='boolean','Evidence contains primitive values only')end
    end
    plain(state.evidence)
end
print('PASS '..count..' book-focus helper checks')
