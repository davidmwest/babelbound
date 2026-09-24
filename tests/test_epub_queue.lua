local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local E=dofile(paths.source("gemini_book_epub.lua"))
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function eq(a,b,m)check(a==b,m..': expected '..tostring(b)..', got '..tostring(a))end
local function fixture()
    local s={tasks={},changes={},ready={},time=100,files={['/python']=true,['/script']=true},logs={}}
    local hooks={python='/python',script='/script',now=function()return s.time end,
        exists=function(path)if s.existsError then error('exists failed')end;return s.files[path]end,
        decode=function(value)if s.decodeError then error('bad JSON')end;return value end,
        log=function(message)s.logs[#s.logs+1]=message end,
        onChange=function(folder,state)s.changes[#s.changes+1]={folder=folder,state=state}end,
        onReady=function(folder,state)s.ready[#s.ready+1]={folder=folder,state=state};if s.readyCallback then s.readyCallback(folder)end end}
    hooks.taskNew=function(path,callback,args)
        if s.newError then error('new threw')end
        if s.newNil then return nil end
        local task={callback=callback,path=path,args=args}
        function task:start()
            if s.startError then error('start threw')end
            if s.startFalse then return false end
            if s.syncFinish then self.callback(0,s.syncFinish,'')end
            return self
        end
        s.tasks[#s.tasks+1]=task;return task
    end
    s.manager=E.new(hooks)
    function s.finish(index,result,code,stderr)
        local t=s.tasks[index]
        local folder=t.args[3]:gsub('/translation.html$','')
        s.files[folder..'/translation.epub']=not s.missingOutput
        t.callback(code or 0,result or {ok=true,output=folder..'/translation.epub',screens=10},stderr or '')
    end
    return s
end
-- Queuing never starts work; explicit flush owns the barrier.
do
    local s=fixture();local m=s.manager
    eq(m:state('/book').status,'idle','unknown folder idle');eq(m:busy('/book'),false,'unknown folder not busy')
    m:request('/book','Book Vol. 07',10);eq(#s.tasks,0,'request does not launch');eq(m:state('/book').status,'queued','queued state')
    eq(m:busy('/book'),true,'queued rename blocked');eq(m:pendingFolders()[1],'/book','pending enumeration')
    check(m:flush('/book'),'flush launches');eq(#s.tasks,1,'one task created');eq(m:state('/book').status,'running','running state')
    eq(s.tasks[1].path,'/python','correct runtime');eq(s.tasks[1].args[1],'/script','script is first Python argument');eq(s.tasks[1].args[2],'--html','structured html argument')
    eq(s.tasks[1].args[3],'/book/translation.html','html path');eq(s.tasks[1].args[5],'/book/translation.epub','output path')
    eq(s.tasks[1].args[7],'Book Vol. 07','title argument')
    eq(m:flush('/book'),false,'duplicate flush cannot race');eq(#m:pendingFolders(),0,'active request removed from pending')
    s.finish(1);eq(m:state('/book').status,'complete','success state');eq(m:state('/book').savedCount,10,'success count')
    eq(m:state('/book').epub,'/book/translation.epub','success file');eq(m:busy('/book'),false,'complete not busy')
    eq(#s.ready,1,'success invokes barrier callback once')
    s.finish(1);eq(#s.ready,1,'duplicate task callback ignored')
    m:request('/book','Book Vol. 07',10);eq(m:busy('/book'),true,'manual refresh same count is not skipped')
end
-- Coalescing picks latest data and never starts a second task for one folder.
do
    local s=fixture();local m=s.manager
    m:request('/book','old',1);m:request('/book','latest',4);m:flush('/book')
    eq(s.tasks[1].args[7],'latest','pre-flush title coalesced');eq(m:state('/book').savedCount,4,'pre-flush count coalesced')
    m:request('/book','newer',5);m:request('/book','newest',6)
    eq(m:flush('/book'),false,'active task blocks next flush');eq(#s.tasks,1,'no simultaneous same-folder task')
    s.finish(1,{ok=true,output='/book/translation.epub',screens=4})
    eq(m:state('/book').status,'queued','newer request survives completion');eq(m:state('/book').savedCount,6,'newest requested count remains')
    eq(#s.tasks,1,'completion does not bypass caller barrier');eq(m:busy('/book'),true,'queued follow-up stays busy')
    m:flush('/book');eq(#s.tasks,2,'caller starts newest queued');eq(s.tasks[2].args[7],'newest','newest title retained')
    s.finish(2,{ok=true,output='/book/translation.epub',screens=7});eq(m:state('/book').savedCount,7,'newer completed snapshot accepted')
end
-- Folders remain independent across job switches, and state is detached.
do
    local s=fixture();local m=s.manager
    m:request('/z book','Z',1);m:request('/a book','A',2)
    eq(table.concat(m:pendingFolders(),','),'/a book,/z book','stable pending order')
    m:flush('/z book');m:flush('/a book');eq(#s.tasks,2,'different folders do not overwrite queue')
    s.finish(1,{ok=true,output='/z book/translation.epub',screens=1});eq(m:busy('/a book'),true,'old job completion preserves new job task')
    eq(m:state('/z book').status,'complete','old folder completes independently')
    local state=m:state('/z book');state.status='failed';eq(m:state('/z book').status,'complete','state cannot be mutated outside')
    s.finish(2,{ok=true,output='/a book/translation.epub',screens=2});eq(m:state('/a book').status,'complete','new folder completes')
end
-- All startup/contract errors become visible failures and release active locks.
for _,variant in ipairs({'missing-runtime','missing-script','exists-error','new-nil','new-throws','start-false','start-throws',
    'exit-error','bad-json','not-object','not-ok','wrong-path','short-count','fractional-count','infinite-count','missing-output'})do
    local s=fixture();local m=s.manager
    if variant=='missing-runtime'then s.files['/python']=nil elseif variant=='missing-script'then s.files['/script']=nil
    elseif variant=='exists-error'then s.existsError=true elseif variant=='new-nil'then s.newNil=true
    elseif variant=='new-throws'then s.newError=true elseif variant=='start-false'then s.startFalse=true elseif variant=='start-throws'then s.startError=true end
    m:request('/book','Book',10);m:flush('/book')
    if m:state('/book').status=='running'then
        local result={ok=true,output='/book/translation.epub',screens=10};local code=0
        if variant=='exit-error'then code=2 elseif variant=='bad-json'then s.decodeError=true elseif variant=='not-object'then result='text'
        elseif variant=='not-ok'then result.ok=false elseif variant=='wrong-path'then result.output='/other/file.epub'
        elseif variant=='short-count'then result.screens=9 elseif variant=='fractional-count'then result.screens=10.5
        elseif variant=='infinite-count'then result.screens=math.huge elseif variant=='missing-output'then s.missingOutput=true end
        s.finish(1,result,code,'diagnostic')
    end
    eq(m:state('/book').status,'failed',variant..' failed state');check(type(m:state('/book').error)=='string',variant..' reason')
    eq(m:busy('/book'),false,variant..' active lock released');eq(#s.ready,1,variant..' ready callback')
end
-- Barrier failures clear queued work and cannot pretend to cancel an active task.
do
    local s=fixture();local m=s.manager;m:request('/book','Book',1);m:fail('/book','Illustration failed')
    eq(m:busy('/book'),false,'barrier failure drops queued request');eq(#m:pendingFolders(),0,'failed queue removed')
    eq(m:state('/book').error,'Illustration failed','barrier reason visible')
    m:request('/book','Book',2);m:flush('/book');m:request('/book','Book',3);m:fail('/book','Source export failed')
    eq(m:busy('/book'),true,'active task remains busy after external fail');eq(#m:pendingFolders(),0,'external fail drops newer queue')
    s.finish(1,{ok=true,output='/book/translation.epub',screens=2})
    eq(m:state('/book').status,'failed','active success cannot hide later barrier failure');eq(m:busy('/book'),false,'active completion releases lock')
end
-- A failed older run retains newer queued work for the caller's next barrier.
do
    local s=fixture();local m=s.manager;m:request('/book','Book',1);m:flush('/book');m:request('/book','Book',2)
    s.finish(1,{ok=false,error='old failed'})
    eq(m:state('/book').status,'failed','failure stays visible while pending');eq(m:state('/book').queued,true,'pending retry disclosed')
    eq(m:pendingFolders()[1],'/book','newer request retained');eq(m:busy('/book'),true,'queued recovery remains busy')
    s.readyCallback=function(folder)m:flush(folder)end;m:flush('/book');s.finish(2,{ok=true,output='/book/translation.epub',screens=2})
    eq(m:state('/book').status,'complete','next successful export resolves failure')
end
-- Synchronous fake callbacks are safe; production tasks complete asynchronously.
do
    local s=fixture();s.files['/book/translation.epub']=true;s.syncFinish={ok=true,output='/book/translation.epub',screens=1}
    s.manager:request('/book','Book',1);s.manager:flush('/book')
    eq(s.manager:state('/book').status,'complete','synchronous completion preserved');eq(s.manager:busy('/book'),false,'sync completion releases lock')
end
print('EPUB queue: '..checks..' checks passed')
