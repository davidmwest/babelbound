local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Actual main-module integration. All I/O, UI, task starts and clocks are
-- memory-only stand-ins; tests never operate on real books or browser state.
local f=assert(io.open(paths.source("gemini_book.lua")));local source=f:read('*a');f:close()
assert(load(source,'compile actual main'))
local S=dofile(paths.source("gemini_book_status.lua"))
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function eq(a,b,m)check(a==b,(m or 'check')..': expected '..tostring(b)..', got '..tostring(a))end
local function clone(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local test={writes={},saved={},logs={},messages={},settings={},scheduled={},tasks={},requests={},flushes={},states={}}
local menu={setTitle=function(self,s)self.title=s end,setTooltip=function(self,s)self.tooltip=s end,setMenu=function(self,fn)self.items=fn end}
local hs={configdir='/fixture/config',settings={get=function(k)return test.settings[k]end,set=function(k,v)test.settings[k]=clone(v)end},
    menubar={new=function()return menu end},timer={secondsSinceEpoch=function()return 123456 end,
        doEvery=function()return{stop=function()end}end,doAfter=function(_,fn)test.scheduled[#test.scheduled+1]=fn end},
    hotkey={bind=function()return{}end},json={encode=clone,decode=clone},
    fs={attributes=function(path)return not test.missingRuntime and {mode='file'}or nil end},
    alert={show=function(s)test.messages[#test.messages+1]=s;return #test.messages end,closeAll=function()end,closeSpecific=function()end},
    pasteboard={readAllData=function()return{}end,changeCount=function()return 0 end},
    caffeinate={get=function()return false end,set=function()end},dialog={textPrompt=function()return'Cancel',''end},
    task={new=function(command,callback,args)
        local task={command=command,callback=callback,args=args,folder=args[#args]}
        task.start=function()return not test.failTaskStart end
        test.tasks[#test.tasks+1]=task;return task
    end}}
local manager
local epub={new=function(options)
    test.initializations=(test.initializations or 0)+1
    manager={options=options}
    function manager:state(folder)return clone(test.states[folder]or{status='idle',folder=folder})end
    function manager:request(folder,title,count)
        test.requests[#test.requests+1]={folder=folder,title=title,count=count}
        test.states[folder]={folder=folder,status='queued',title=title,savedCount=count};options.onChange()
    end
    function manager:pendingFolders()
        local result={};for folder,state in pairs(test.states)do if state.status=='queued'then result[#result+1]=folder end end
        table.sort(result);return result
    end
    function manager:flush(folder)
        if self:state(folder).status~='queued'then return end
        test.flushes[#test.flushes+1]=folder;test.states[folder].status='running';options.onChange()
    end
    function manager:fail(folder,reason)
        test.states[folder]={folder=folder,status='failed',error=reason};options.onChange()
    end
    function manager:busy(folder)local s=self:state(folder).status;return s=='running'or s=='queued'end
    function manager:complete(folder)
        test.states[folder].status='complete';options.onChange();options.onReady()
    end
    return manager
end}
local modules={gemini_book_status=S,gemini_book_epub=epub,
    gemini_book_core={markdown=function()return'markdown'end,html=function()return'html'end},
    gemini_book_jobs=dofile(paths.source("gemini_book_jobs.lua")),
    gemini_book_limits={normalize=function(s)return tostring(s or''):lower()end},
    gemini_book_resume={modelLabel=function(s)return s end}}
local injection=[[
atomicWrite=function(path,value)_TEST.writes[path]=_CLONE(value)end
readFile=function(path)return _TEST.writes[path]or _TEST.saved[path]end
log=function(s)_TEST.logs[#_TEST.logs+1]=s end
pendingSourceStillVisible=function()return true end
evaluationForPending=function()return nil end
handleUsageLimit=function()_TEST.limitCalls=(_TEST.limitCalls or 0)+1;pause('Fixture service quota blocked')end
M._test={save=saveAnswer,rebuild=rebuildIllustrations,flush=flushEpubs,request=requestEpub,
    set=function(state)
        job=state.job;running=state.running==true;phase='idle';due=0;epoch=0
        recoveryActive=false;resumeCaptureEpoch=nil;sessionWarning=nil
        illustrationBuild={status='idle'};illustrationTask=nil;illustrationQueued=nil;quota.timer=nil;scan=nil
        cfg.illustrationsEnabled=state.illustrations==true;cfg.epubEnabled=true;refreshMenu()
    end,
    switch=function(other)job=other;running=false;refreshMenu()end,
    state=function()return job,running,illustrationTask,illustrationQueued end}
return M
]]
local transformed,count=source:gsub('return M%s*$',injection);assert(count==1)
local function loadMain(overrides)
    local env=setmetatable({hs=hs,_TEST=test,_CLONE=clone,print=function()end,
        GeminiBookConfig=overrides,require=function(name)return modules[name]or{}end},{__index=_G})
    -- The real module reads rawget(_G, "GeminiBookConfig") during loading.
    -- Give each isolated initialization its own globals, as Lua normally does.
    env._G=env
    return assert(load(transformed,'actual main (memory-only EPUB harness)','t',env))()
end

-- Installer-supplied options must be applied before helper closures capture
-- runtime paths; configuring M.config after require is too late for this.
do
    local options={illustrationPython='/fixture/custom-runtime/bin/python3',
        epubScript='/fixture/custom-helper/ebook.py',defaultBatch=9}
    local configured=loadMain(options)
    eq(configured.config.illustrationPython,options.illustrationPython,'pre-load Python override applied')
    eq(manager.options.python,options.illustrationPython,'EPUB helper captures overridden Python during initialization')
    eq(manager.options.script,options.epubScript,'EPUB helper captures overridden script during initialization')
    eq(configured.config.defaultBatch,9,'pre-load scalar option applied')
    eq(configured.config.epubEnabled,true,'unspecified default remains enabled')
    eq(options.epubEnabled,nil,'module does not add defaults to caller options')
    local empty=loadMain({})
    eq(empty.config.illustrationPython,'/fixture/config/.bt-venv/bin/python3','empty overrides preserve default Python')
    eq(empty.config.defaultBatch,3,'empty overrides preserve batch default')
    for _,invalid in ipairs({'not a table',17,false,function()end})do
        local previous=test.initializations
        local ok,problem=pcall(loadMain,invalid)
        check(not ok,'non-table configuration is rejected')
        check(tostring(problem):find('GeminiBookConfig must be a table',1,true),'non-table error names configuration')
        eq(test.initializations,previous,'invalid configuration cannot initialize a helper')
    end
    local previous=test.initializations
    local ok,problem=pcall(loadMain,{illustrationPyton='/fixture/typo/python'})
    check(not ok,'unknown configuration option is rejected')
    check(tostring(problem):find('Unknown GeminiBookConfig option: illustrationPyton',1,true),'unknown-option error identifies typo')
    eq(test.initializations,previous,'unknown option cannot initialize a helper')
end
local M=loadMain()
eq(M.config.illustrationPython,'/fixture/config/.bt-venv/bin/python3','absent overrides preserve installed-runtime default')
eq(manager.options.python,M.config.illustrationPython,'default EPUB helper captures installed-runtime default')
eq(manager.options.script,'/fixture/config/gemini_book_epub.py','absent overrides preserve default EPUB script')
eq(M.config.defaultBatch,3,'prior instance overrides cannot leak into default instance')
local T=M._test
local function job(remaining,name)
    name=name or'Test Vol. 07'
    return{folder='/books/Book-'..name,folderName='Book-'..name,bookTitle=name,tag='test',
        records={{index=1,id='old',first='old first',last='old last',text='old text',model='Flash'}},
        remaining=remaining,lastSourceHash='source',needAdvance=true,requestMode='inline'}
end
local function pending(j)
    j.pending={index=#j.records+1,id='new',sourceHash='source',sent=true,modelAtSubmit='Flash'};return j
end
local function reset(j,running,illustrations)
    test.writes={};test.saved={};test.logs={};test.messages={};test.scheduled={};test.tasks={}
    test.requests={};test.flushes={};test.states={};test.failTaskStart=false;test.missingRuntime=false;test.limitCalls=0
    T.set{job=j,running=running,illustrations=illustrations}
end
local function finish(task,scanCount,code)
    test.saved[task.folder..'/illustrations/manifest.json']={sourceCount=scanCount,records={}}
    task.callback(code or 0,'fixture scan output','fixture scan failure')
end
local answer={first='new first',last='new last',text='new translated text',raw='valid response'}

eq(M.config.epubEnabled,true,'automatic EPUB enabled by default')
for _,variant in ipairs({'normal','manual','one-page-recovery','deferred-limit'})do
    local j=pending(job(1));reset(j,variant~='manual',false)
    if variant=='one-page-recovery'then j.pauseAfterNext=true end
    if variant=='deferred-limit'then j.deferredUsageLimit={text='quota'}end
    T.save(answer,variant=='manual')
    eq(#j.records,2,variant..' final save commits')
    eq(j.remaining,0,variant..' final save exhausts batch')
    eq(#test.requests,1,variant..' queues EPUB automatically')
    eq(test.requests[1].folder,j.folder,variant..' queues correct folder')
    eq(test.requests[1].title,j.bookTitle,variant..' uses book title')
    eq(test.requests[1].count,2,variant..' uses final committed count')
    eq(#test.flushes,1,variant..' starts export without UI')
    eq(menu.title,'BT saving (100%)',variant..' final export visible')
    manager:complete(j.folder);eq(menu.title,'BT finished',variant..' finished after export')
end
for _,variant in ipairs({'normal','manual','one-page-recovery'})do
    local j=pending(job(3));reset(j,variant~='manual',false)
    if variant=='one-page-recovery'then j.pauseAfterNext=true end
    T.save(answer,variant=='manual')
    eq(j.remaining,2,variant..' retains remaining pages')
    eq(#test.requests,0,variant..' nonfinal save does not export')
    eq(#test.flushes,0,variant..' nonfinal export cannot start')
end

-- Actual illustration callbacks must complete the final coalesced writer first.
do
    local j=job(1);reset(j,true,true);T.rebuild(false)
    eq(#test.tasks,1,'first illustration scan starts')
    pending(j);T.save(answer,false)
    eq(#test.requests,1,'completed job queues behind older scan')
    eq(#test.flushes,0,'older scan blocks export')
    eq(menu.title,'BT saving (100%)','queued export visible at 100 percent')
    finish(test.tasks[1],1)
    eq(#test.tasks,2,'final save schedules latest illustration scan')
    eq(#test.flushes,0,'final illustration writer still blocks export')
    finish(test.tasks[2],2)
    eq(#test.flushes,1,'last illustration callback drains EPUB queue')
    eq(test.flushes[1],j.folder,'correct queued book exported')
    eq(menu.title,'BT saving (100%)','running EPUB visible at 100 percent')
    manager:fail(j.folder,'disk full')
    eq(menu.title,'BT warning','EPUB failure visible')
    check(M.uiState().tooltip:find('disk full',1,true),'EPUB failure cause visible')
    T.request(j);manager:complete(j.folder)
    eq(menu.title,'BT finished','successful export retry restores finished')
end

-- Switching the loaded book must not strand a completed book's pending export.
do
    local a=pending(job(1,'A'));reset(a,true,true);T.save(answer,false)
    local b=pending(job(1,'B'));T.switch(b);T.save(answer,false)
    eq(#test.requests,2,'two completed jobs queued')
    eq(#test.flushes,0,'writer barrier spans loaded-job switch')
    finish(test.tasks[1],2)
    eq(#test.tasks,2,'queued second-book illustration scan starts')
    eq(#test.flushes,0,'second-book writer still blocks all exports')
    finish(test.tasks[2],2)
    eq(#test.flushes,2,'all pending folders drained after job switch')
    eq(test.flushes[1],a.folder,'first completed folder exported')
    eq(test.flushes[2],b.folder,'second completed folder exported')
end

for _,variant in ipairs({'scan-error','start-error','missing-runtime'})do
    local j=pending(job(1));reset(j,true,true)
    test.failTaskStart=variant=='start-error';test.missingRuntime=variant=='missing-runtime'
    T.save(answer,false)
    if variant=='scan-error'then finish(test.tasks[1],0,1)end
    eq(#test.requests,1,variant..' records export intention')
    eq(#test.flushes,0,variant..' prevents partial EPUB export')
    eq(manager:state(j.folder).status,'failed',variant..' failed export visible')
    eq(menu.title,'BT warning',variant..' has warning status')
end

-- Actual API and actual menu both guard renaming during queued/running export.
for _,status in ipairs({'queued','running'})do
    local j=job(0);reset(j,false,false);test.states[j.folder]={folder=j.folder,status=status}
    local ok,problem=M.renameJob('New title')
    eq(ok,nil,status..' export blocks direct rename API')
    check(problem:find('wait for',1,true),status..' rename explains unfinished save')
    local rename
    for _,item in ipairs(M.menuItems())do if item.title=='Rename current job…'then rename=item end end
    check(rename and rename.disabled,status..' export disables rename menu')
end

-- A stale scan queued before a final save still needs its second pass even
-- when another book is loaded before the first callback returns.
do
    local a=job(1,'A');reset(a,true,true);T.rebuild(false)
    pending(a);T.save(answer,false)
    local b=job(4,'B');T.switch(b)
    finish(test.tasks[1],1)
    eq(#test.flushes,0,'job switch cannot export a stale artwork manifest')
    eq(#test.tasks,2,'old completed book gets its final illustration scan after switch')
    eq(test.tasks[2].folder,a.folder,'queued writer belongs to old completed book')
    finish(test.tasks[2],2)
    eq(#test.flushes,1,'old completed book exports after refreshed artwork')
end

-- A newer book can replace the scalar illustration queue while A's initial
-- scan is still running. The EPUB queue must detect and repair A's stale
-- manifest independently of that short-lived illustration queue.
do
    local a=job(1,'A');reset(a,true,true);T.rebuild(false)
    pending(a);T.save(answer,false)
    local b=pending(job(1,'B'));T.switch(b);T.save(answer,false)
    finish(test.tasks[1],1)
    eq(#test.tasks,2,'newer queued writer starts before older rescue')
    eq(test.tasks[2].folder,b.folder,'newer book retains its illustration queue')
    finish(test.tasks[2],2)
    eq(#test.tasks,3,'EPUB freshness guard rescues overwritten older queue')
    eq(test.tasks[3].folder,a.folder,'rescue scan belongs to stale older folder')
    eq(#test.flushes,0,'stale completed book is not exported prematurely')
    finish(test.tasks[3],2)
    eq(#test.flushes,2,'both completed books export after all required scans')
    eq(test.flushes[1],a.folder,'rescued older book exported')
    eq(test.flushes[2],b.folder,'newer book exported')
end

print('Automatic EPUB actual-main integration: '..checks..' checks passed')
