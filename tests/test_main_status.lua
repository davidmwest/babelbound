local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Actual main-module functions with memory-only I/O/UI stand-ins. No UI calls,
-- subprocesses, filesystem writes, native timers or translations occur. Tests
-- explicitly drain selected deferred callbacks from an in-memory queue.
local path=paths.source("gemini_book.lua")
local f=assert(io.open(path));local source=f:read('*a');f:close()
assert(load(source,'compile actual main'))
local S=dofile(paths.source("gemini_book_status.lua"))
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function eq(a,b,message)check(a==b,(message or 'check')..': expected '..tostring(b)..', got '..tostring(a))end
local function clone(v)if type(v)~='table' then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local test={writes={},messages={},logs={},settings={},scheduled={},saved={},files={},hotkeys={},opens={},dialogs={},events={},repeating={}}
test.reader={focus=function(self)
    test.focusCalls=(test.focusCalls or 0)+1;test.frontmost=self;test.events[#test.events+1]='focus reader'
end}
local function dialogReply(title,message)
    test.dialogs[#test.dialogs+1]={title=title,message=message}
    test.events[#test.events+1]='dialog'
    if test.dialogStealsFocus then test.frontmost={}end
    if test.onDialog then test.onDialog(title)end
    return table.remove(test.dialogButtons or {},1) or test.dialogButton or 'Cancel'
end
local calibration={provider='gemini',windowID=17,windowTitle='Book viewer',screenID=1,
    windowFrame={x=0,y=0,w=1000,h=800},input={x=900,y=700},next={x=700,y=400},
    crop={x=20,y=50,w=700,h=700},panel={x=800,y=80}}
test.settings['GeminiBookMac.v1.calibration']=clone(calibration)
local menu={setTitle=function(self,title)self.title=title end,setTooltip=function(self,title)self.tooltip=title end,
    setMenu=function(self,fn)self.items=fn end}
local hs={configdir='/fixture/config',settings={get=function(k)return test.settings[k]end,set=function(k,v)test.settings[k]=clone(v)end},
    menubar={new=function()return menu end},timer={secondsSinceEpoch=function()return 123456 end,
        doEvery=function(_,fn)local timer={callback=fn,stop=function(self)self.stopped=true end};test.repeating[#test.repeating+1]=timer;return timer end,
        doAfter=function(_,fn)test.scheduled[#test.scheduled+1]=fn end},
    window={frontmostWindow=function()test.windowReads=(test.windowReads or 0)+1;return test.frontmost end},
    hotkey={bind=function(_,key,_,released)test.hotkeys[key]=released;return {}end},json={encode=clone,decode=clone},alert={show=function(s)test.messages[#test.messages+1]=s;return #test.messages end,
        closeAll=function()end,closeSpecific=function()end},screenRecordingState=function()return test.permission~=false end,
    pasteboard={readAllData=function()return {}end,changeCount=function()return 0 end},
    fs={attributes=function(path,key)local mode=test.files[path];if not mode then return nil end;return key and mode or {mode=mode}end},
    caffeinate={get=function()return false end,set=function()end},dialog={
        textPrompt=function(title,message)return dialogReply(title,message),test.dialogValue or ''end,
        blockAlert=dialogReply}}
local actualJobs=dofile(paths.source("gemini_book_jobs.lua"))
local modules={gemini_book_epub=dofile(paths.source("gemini_book_epub.lua")),gemini_book_status=S,gemini_book_core={markdown=function()return 'markdown'end,html=function()return 'html'end},
    gemini_book_jobs=actualJobs,gemini_book_limits={normalize=function(s)return tostring(s or ''):lower()end},
    gemini_book_provider=dofile(paths.source("gemini_book_provider.lua")),
    gemini_book_resume=dofile(paths.source("gemini_book_resume.lua")),
    gemini_book_menu=dofile(paths.source("gemini_book_menu.lua")),
    gemini_book_source=dofile(paths.source("gemini_book_source.lua"))}
local env=setmetatable({hs=hs,_TEST=test,_CLONE=clone,print=function()end,require=function(name)return modules[name] or {}end},{__index=_G})
local injection=[[
-- Test-only exposure; production source on disk is not changed.
atomicWrite=function(path,value)
    if _TEST.failWrite then error('fixture disk full')end
    _TEST.writes[path]=_CLONE(value)
end
readFile=function(path)return _TEST.saved[path]end
log=function(s)_TEST.logs[#_TEST.logs+1]=s end
pendingSourceStillVisible=function()return _TEST.sourceVisible~=false end
evaluationForPending=function()return nil end
local actualHandleUsageLimit=handleUsageLimit
handleUsageLimit=function(event,origin)
    _TEST.limitCalls=(_TEST.limitCalls or 0)+1
    _TEST.lastLimit={event=event,origin=origin}
    pause('Fixture service quota blocked')
end
guard=function()
    _TEST.events[#_TEST.events+1]='guard'
    if _TEST.requireReaderFocus and _TEST.frontmost~=_TEST.reader then return nil,'Reader lost focus to confirmation dialog' end
    if _TEST.guardError then return nil,_TEST.guardError end
    _TEST.guardCalls=(_TEST.guardCalls or 0)+1
    return _TEST.reader
end
stableSourceCapture=function(label,active,done,failed,expected)
    _TEST.events[#_TEST.events+1]='capture'
    _TEST.captureCalls=(_TEST.captureCalls or 0)+1
    if _TEST.requireReaderFocus and _TEST.frontmost~=_TEST.reader then failed('Reader lost focus before source capture');return end
    if _TEST.captureError then failed(_TEST.captureError);return end
    done({},_TEST.hash or expected or 'source')
end
beginOwnership=function()end
waitForPage=function()setPhase('settle')end
mkdir=function()end
openPath=function(path)
    _TEST.opens[#_TEST.opens+1]={path=path,running=running,scheduled=job and job.autoResume and job.autoResume.active,
        checking=recoveryActive or resumeCaptureEpoch==epoch}
end
M._test={pause=pause,save=saveAnswer,resume=resumeNow,checkpoint=checkpoint,warning=warningNotice,handleLimit=actualHandleUsageLimit,
    set=function(state)
        job=state.job;running=state.running==true;phase=state.phase or 'idle';due=0
        recoveryActive=state.recoveryActive==true;resumeCaptureEpoch=nil;sessionWarning=state.warning;epoch=state.epoch or 0
        provider=state.provider or 'gemini';cal=_CLONE(_TEST.calibration)
        if state.calibrated==false then cal=nil end
        if cal then cal.provider=provider end
        lastModelReadback=nil;calibrationStep=nil;calibrationDraft=nil;nextCalibration=nil
        illustrationBuild=state.build or {status='idle'};illustrationTask=nil;quota.timer=nil;scan=nil
        cfg.illustrationsEnabled=false;cfg.epubEnabled=false;cfg.offerAutoResume=false;refreshMenu()
    end,
    state=function()return job,running,phase,sessionWarning end}
return M
]]
local transformed,count=source:gsub('return M%s*$',injection)
assert(count==1,'one main return')
local M=assert(load(transformed,'actual main (memory-only harness)','t',env))()
local T=M._test
local function job(remaining)
    return {folder='/books/Book-Extremely Long Full Series Name Vol. 107',folderName='Book-Extremely Long Full Series Name Vol. 107',
        bookTitle='Extremely Long Full Series Name Vol. 107',tag='test',records={{index=1,id='old',first='old first',last='old last',text='old text',model='Flash'}},
        remaining=remaining or 3,lastSourceHash='source',needAdvance=true,requestMode='inline'}
end
local function reset(j,running)
    test.writes={};test.messages={};test.scheduled={};test.guardError=nil;test.captureError=nil;test.hash=nil
    test.failWrite=nil;test.permission=true;test.sourceVisible=true;test.limitCalls=0;test.dialogButton='Cancel';test.dialogValue=''
    test.opens={};test.dialogs={};test.guardCalls=0;test.focusCalls=0;test.calibration=calibration;test.files={}
    test.events={};test.repeating={};test.frontmost=test.reader;test.windowReads=0;test.captureCalls=0
    test.dialogStealsFocus=false;test.requireReaderFocus=false;test.dialogButtons={};test.onDialog=nil
    if j then test.files[j.folder]='directory';test.files[j.folder..'/translation.html']='file';test.files[j.folder..'/translation.epub']='file'end
    T.set{job=j,running=running}
end
local finished='Batch complete. Last page remains visible. Review the saved translation.'
local function pending(j)
    j.pending={index=#j.records+1,id='new',sourceHash='source',sent=true,modelAtSubmit='Flash'};return j
end
local function findItem(items,prefix)
    for _,item in ipairs(items) do
        if item.title and item.title:sub(1,#prefix)==prefix then return item end
        if item.menu then local nested=findItem(item.menu,prefix);if nested then return nested end end
    end
end
local function nextCallback()
    local callback=table.remove(test.scheduled,1)
    check(type(callback)=='function','expected deferred callback')
    callback()
end
local answer={first='new first',last='new last',text='new translated text',raw='valid response'}
-- Error state is durable; intentional Stop and dismissal do not erase it.
do
    local j=job();reset(j,true);T.pause('Copy target disappeared')
    eq(j.pauseKind,'warning','runtime failure persists warning')
    eq(j.pauseReason,'Copy target disappeared','runtime failure persists cause')
    eq(test.writes[j.folder..'/checkpoint.json'].pauseKind,'warning','warning checkpoint written')
    eq(menu.title,'BT warning','failure visible in native menu')
    M.stop();eq(j.pauseKind,'warning','idle Stop retains warning')
    eq(j.pauseReason,'Copy target disappeared','idle Stop retains original reason')
    M.dismissMessage();eq(menu.title,'BT warning','dismiss does not clear warning')
    hs.shutdownCallback();eq(j.pauseKind,'warning','shutdown preserves warning')
end
-- Ordinary user pause and completed outcome retain distinct semantics.
do
    local j=job();reset(j,true);M.stop()
    eq(j.pauseKind,'paused','running Stop persists ordinary pause')
    eq(menu.title,'BT paused','ordinary pause title')
    eq(test.writes[j.folder..'/checkpoint.json'].pauseKind,'paused','ordinary pause checkpoint')
    j=job(0);j.pauseKind='finished';j.pauseReason=finished;reset(j,false)
    eq(menu.title,'BT finished','completed batch title')
    M.stop();eq(j.pauseKind,'finished','Stop cannot erase finished outcome')
    eq(j.pauseReason,finished,'Stop retains completion reason')
    hs.shutdownCallback();eq(j.pauseKind,'finished','shutdown preserves completion')
end
-- All three completion paths must outrank manual/test/service pause branches.
for _,variant in ipairs({'normal','manual','test-one','deferred-limit','manual-with-old-warning'})do
    local j=pending(job(1))
    if variant=='test-one' then j.pauseAfterNext=true end
    if variant=='deferred-limit' then j.deferredUsageLimit={text='quota'}end
    if variant=='manual-with-old-warning' then j.pauseKind='warning';j.pauseReason='old collection failure'end
    reset(j,variant~='manual' and variant~='manual-with-old-warning')
    T.save(answer,variant=='manual' or variant=='manual-with-old-warning')
    eq(#j.records,2,variant..' final save committed')
    eq(j.remaining,0,variant..' batch exhausted')
    eq(j.pending,nil,variant..' pending cleared')
    eq(j.pauseKind,'finished',variant..' final save is finished')
    eq(menu.title,'BT finished',variant..' visible finished')
    eq(test.writes[j.folder..'/checkpoint.json'].pauseKind,'finished',variant..' durable finish')
    eq(test.limitCalls,0,variant..' final page does not pause for nonexistent remaining work')
    if variant=='deferred-limit' then
        eq(j.deferredUsageLimit,nil,'final service notice cleared from pending queue')
        eq(j.completedBatchNotice.text,'quota','final service notice retained as informational metadata')
    end
end
-- Partial batch saves and failures retain the right pause/remaining behavior.
for _,variant in ipairs({'manual','test-one','manual-with-old-warning','deferred-limit'})do
    local j=pending(job(3))
    if variant=='test-one' then j.pauseAfterNext=true end
    if variant=='deferred-limit' then j.deferredUsageLimit={text='quota'}end
    if variant=='manual-with-old-warning' then j.pauseKind='warning';j.pauseReason='old collection failure'end
    reset(j,variant~='manual' and variant~='manual-with-old-warning')
    T.save(answer,variant=='manual' or variant=='manual-with-old-warning')
    eq(j.remaining,2,variant..' nonfinal count retained')
    eq(j.pauseKind,variant=='deferred-limit' and 'warning' or 'paused',variant..' nonfinal outcome')
    eq(menu.title,variant=='deferred-limit' and 'BT warning' or 'BT paused',variant..' visible outcome')
    eq(test.limitCalls,variant=='deferred-limit' and 1 or 0,variant..' service handling')
end
do
    local j=pending(job(1));reset(j,true);test.sourceVisible=false;T.save(answer,false)
    eq(#j.records,1,'source mismatch does not commit')
    eq(j.remaining,1,'source mismatch does not consume batch')
    eq(j.pauseKind,'warning','source mismatch warns')
    eq(menu.title,'BT warning','source mismatch visible')
end
-- Actual menu contents read the full loaded title fresh, including volume.
do
    local j=job();reset(j,false)
    eq(findItem(M.menuItems(),'Resume —').title,'Resume — Extremely Long Full Series Name Vol. 107','full volume title in real menu')
    j.bookTitle='Renamed Series Vol. 208'
    eq(findItem(M.menuItems(),'Resume —').title,'Resume — Renamed Series Vol. 208','menu reads renamed title')
    reset(nil,false)
    check(findItem(M.menuItems(),'No book loaded')~=nil,'no-job menu is honest')
    check(findItem(M.menuItems(),'Start translating…')~=nil,'no-job primary starts a new book')
    eq(findItem(M.menuItems(),'Resume —'),nil,'no-job menu cannot name old/frontmost book')
    local oldRestore=M.restoreLatest;local restored=0
    M.restoreLatest=function()restored=restored+1;return true end
    T.resume(true)
    eq(restored,1,'no-job resume restores rather than creates')
    eq(select(1,T.state()),nil,'no-job resume does not create a fake job')
    M.restoreLatest=oldRestore
end
-- Building and opening menus is passive: provider, book, pending request,
-- timers, browser focus and checkpoints are left alone.
do
    local j=pending(job());j.needAdvance=false;reset(j,false)
    local originalID=j.pending.id
    for _=1,3 do
        local items=M.menuItems()
        for _,title in ipairs({'Read translation','Books','Setup','Advanced'}) do
            check(findItem(items,title)~=nil,'stable menu group '..title)
        end
        check(findItem(items,'A reply is pending')~=nil,'pending request explained without collecting')
    end
    eq(next(test.writes),nil,'menu construction writes no checkpoint')
    eq(#test.scheduled,0,'menu construction schedules no operation')
    eq(test.guardCalls,0,'menu construction performs no browser guard/read')
    eq(test.focusCalls,0,'menu construction never focuses browser')
    eq(#test.dialogs,0,'menu construction presents no prompt')
    eq(j.pending.id,originalID,'menu construction retains pending request identity')
    eq(j.pending.sent,true,'menu construction retains sent status')
    eq(select(2,T.state()),false,'menu construction does not run job')
end
-- Menu callbacks recheck the live operation and the identity they were built
-- for, including programmatic calls that bypass Hammerspoon's disabled flag.
do
    local j=job();reset(j,false)
    local staleNew=assert(findItem(M.menuItems(),'Start a new book…')).fn
    T.set{job=j,running=true}
    staleNew()
    eq(select(1,T.state()),j,'active stale New book callback retains job')
    eq(select(2,T.state()),true,'active stale New book callback does not pause job')
    eq(#test.dialogs,0,'active stale New book callback opens no wizard')
    eq(next(test.writes),nil,'active stale New book callback writes nothing')
    M.selectProvider('chatgpt')
    eq(M.currentProvider(),'gemini','direct provider action also rejects active job')
    eq(select(1,T.state()),j,'direct blocked provider action retains current book')
    M.newJob(5,'Another book');M.calibrate();M.restoreFolder('/books/Other');M.retry()
    eq(select(1,T.state()),j,'direct blocked setup and recovery actions retain current book')
    eq(select(2,T.state()),true,'direct blocked setup and recovery actions leave translation running')
    eq(#test.scheduled,0,'direct blocked setup and recovery actions schedule nothing')
    eq(next(test.writes),nil,'direct blocked setup and recovery actions write nothing')

    reset(j,false)
    local staleResume=assert(findItem(M.menuItems(),'Resume —')).fn
    local replacement=job();replacement.bookTitle='A different book';replacement.folder='/books/Other'
    T.set{job=replacement}
    staleResume()
    eq(select(1,T.state()),replacement,'stale callback never switches back to its book')
    eq(#test.scheduled,0,'stale callback cannot start replacement book')

    reset(j,false)
    staleResume=assert(findItem(M.menuItems(),'Resume —')).fn
    M.stop();staleResume()
    eq(#test.scheduled,0,'Stop invalidates old resume callbacks for the same book')

    j.autoResume={active=true,dueAt=123500};reset(j,false)
    M.selectProvider('chatgpt');M.newJob(5,'Another book')
    eq(j.autoResume.active,true,'blocked setup actions cannot silently cancel scheduled work')
    eq(M.currentProvider(),'gemini','scheduled work blocks provider changes')
    eq(select(1,T.state()),j,'scheduled work blocks replacement book')
end
-- Primary and pause shortcuts share the menu's policy. S opens warning review;
-- P never bypasses a warning, creates a new target, or triggers a scheduled job.
do
    local j=job();j.pauseKind='warning';j.pauseReason='Check the saved source';reset(j,false)
    check(findItem(M.menuItems(),'Review problem —')~=nil,'warning offers review instead of blind resume')
    test.hotkeys.p()
    eq(#test.scheduled,0,'P cannot bypass warning')
    eq(j.pauseReason,'Check the saved source','P preserves blocking warning')
    test.hotkeys.s()
    eq(#test.dialogs,1,'S presents warning review')
    eq(#test.scheduled,0,'cancelled warning review schedules no work')
    eq(select(2,T.state()),false,'cancelled warning review remains idle')

    j=job(0);reset(j,false)
    test.hotkeys.p()
    eq(#test.dialogs,0,'P never starts another batch wizard')
    eq(#test.scheduled,0,'P never creates work after completion')
    check(findItem(M.menuItems(),'Translate more —')~=nil,'completed batch offers explicit extension')

    j=job();j.autoResume={active=true,dueAt=123500};reset(j,false)
    test.hotkeys.p()
    eq(j.autoResume.active,true,'P leaves approved scheduled resume armed')
    eq(#test.scheduled,0,'P cannot trigger scheduled work early')

    reset(nil,false)
    test.hotkeys.p()
    eq(#test.dialogs,0,'P does not create a book')
    eq(#test.scheduled,0,'P does not restore or start a book')

    local oldNew=M.newJob;local created=0
    M.newJob=function()created=created+1 end
    test.hotkeys.s()
    eq(created,1,'S invokes new-book action when no book is loaded')
    M.newJob=oldNew
end
-- A native confirmation can leave Hammerspoon in front. Accepted recovery
-- restores the exact previously focused reader before browser guards/capture.
for _,route in ipairs({'resume','collect','position'})do
    local j=job();j.pauseKind='warning';j.pauseReason='Review this page'
    if route=='collect'then pending(j);j.needAdvance=false end
    if route=='position'then j.turnUncertain=true end
    reset(j,false);test.dialogStealsFocus=true;test.requireReaderFocus=true
    local label=route=='collect' and 'Collect existing reply' or route=='position' and 'Review page position' or 'Check and resume'
    test.dialogButtons={label,route=='collect' and 'Collect reply' or 'Cancel'}
    M.reviewProblem()
    eq(test.windowReads,1,route..' review remembers frontmost reader before dialog')
    eq(test.frontmost,test.reader,route..' accepted review refocuses original reader')
    eq(test.events[1],'dialog',route..' first presents review')
    eq(test.events[2],'focus reader',route..' refocuses before any browser guard')
    eq(M.uiState().kind,'checking',route..' accepted review reserves deferred source check')
    nextCallback()
    eq(test.events[3],'guard',route..' browser guard follows restored reader focus')
    eq(test.captureCalls,1,route..' source check reaches original reader')
    eq(#j.records,1,route..' review alone does not save another page')
    eq(j.remaining,3,route..' review does not consume a page')
    if route=='position'then
        eq(select(2,T.state()),false,'cancelled second position confirmation remains idle')
        eq(j.turnUncertain,true,'review does not silently approve uncertain page position')
    else
        eq(select(2,T.state()),true,route..' starts only after source check')
        if route=='collect'then
            eq(j.pending.id,'new','reviewed collection retains original request identity')
            eq(j.pending.sent,true,'reviewed collection never resets sent request for resubmission')
            eq(select(3,T.state()),'wait','reviewed collection waits for existing reply')
        end
    end
end
do
    local j=job();j.pauseKind='warning';j.pauseReason='Review this page';reset(j,false)
    test.dialogStealsFocus=true;test.hotkeys.s()
    eq(test.focusCalls,0,'cancelled review does not switch windows')
    eq(test.guardCalls,0,'cancelled review performs no browser checks')
    eq(#test.scheduled,0,'cancelled review schedules no source capture')

    reset(j,false);test.dialogStealsFocus=true;test.dialogButton='Check and resume'
    test.onDialog=function()M.stop()end
    test.hotkeys.s()
    eq(test.focusCalls,0,'operation changed during review does not refocus stale reader')
    eq(#test.scheduled,0,'operation changed during review cannot resume')
end
-- The actual automatic quota handler reserves its delayed offer immediately.
-- A second action cannot race that offer, and Stop invalidates the callback.
for _,decision in ipairs({'stop','decline','approve'})do
    local j=pending(job());j.needAdvance=false;reset(j,true)
    M.config.offerAutoResume=true;test.requireReaderFocus=true;test.dialogStealsFocus=true
    test.dialogButton=decision=='approve' and 'Yes, auto-resume' or 'No, stay paused'
    local event={text=os.date('%Y-%m-%d %H:%M',123456+3600),kind='fixture-quota'}
    check(T.handleLimit(event,'fixture-sidebar'),decision..' actual quota handler recognizes event')
    eq(select(2,T.state()),false,decision..' quota handling pauses active translation')
    eq(M.uiState().kind,'checking',decision..' optional quota offer reserves checking immediately')
    eq(#test.scheduled,1,decision..' quota handling queues one confirmation')
    eq(j.autoResume,nil,decision..' no reset timer exists before explicit approval')
    M.selectProvider('chatgpt');test.hotkeys.s()
    eq(M.currentProvider(),'gemini',decision..' reserved quota offer blocks provider mutation')
    eq(#test.scheduled,1,decision..' reserved quota offer blocks duplicate primary action')
    if decision=='stop'then M.stop()end
    nextCallback()
    eq(j.pending.id,'new',decision..' quota offer retains pending request identity')
    eq(j.pending.sent,true,decision..' quota offer cannot authorize resubmission')
    if decision=='approve'then
        eq(j.autoResume.active,true,'accepted quota offer arms approved one-shot timer')
        eq(M.uiState().kind,'scheduled','accepted quota offer displays scheduled state')
        eq(#test.repeating,1,'accepted quota offer installs exactly one timer')
        eq(test.frontmost,test.reader,'quota confirmation restores reader focus')
    else
        eq(j.autoResume,nil,decision..' quota offer leaves no armed timer')
        eq(#test.repeating,0,decision..' quota offer installs no timer')
        eq(M.uiState().kind,'warning',decision..' quota offer leaves original warning visible')
        eq(#test.dialogs,decision=='stop' and 0 or 1,decision..' quota confirmation count')
        if decision=='stop'then eq(test.guardCalls,0,'Stop cancels quota offer before browser check')end
    end
end
-- Entering Resume reserves the checking state immediately, before its timer
-- executes. Repeated clicks cannot enqueue duplicate starts; Stop cancels it.
do
    local j=job();reset(j,false)
    test.hotkeys.s()
    eq(M.uiState().kind,'checking','S reserves checking before deferred work')
    eq(#test.scheduled,1,'S enqueues one resume check')
    check(findItem(M.menuItems(),'Checking —').disabled,'checking primary cannot be started again')
    test.hotkeys.s()
    eq(#test.scheduled,1,'second S does not enqueue another resume')
    test.hotkeys.x()
    eq(select(2,T.state()),false,'Stop leaves translation idle')
    nextCallback()
    eq(test.guardCalls,0,'cancelled resume never touches browser')
    eq(select(2,T.state()),false,'cancelled callback cannot restart job')

    reset(j,false)
    test.hotkeys.p()
    eq(M.uiState().kind,'checking','P resumes ordinary paused job with same reservation')
    nextCallback()
    eq(select(2,T.state()),true,'ordinary paused resume starts after check')
    test.hotkeys.p()
    eq(select(2,T.state()),false,'P pauses active translation')
end
do
    local j=job();reset(j,true)
    local open=assert(findItem(M.menuItems(),'Pause and open reading copy')).fn
    test.files[j.folder..'/translation.html']=nil
    open()
    eq(#test.opens,0,'stale reading-copy callback rechecks that output exists')
    eq(select(2,T.state()),true,'missing reading copy does not interrupt running translation')
end
-- Opening a foreground reading artifact pauses before opening it, and cancels
-- any armed quota timer before another app can take browser focus.
for _,mode in ipairs({'running','checking','scheduled'}) do
    local j=job();if mode=='scheduled' then j.autoResume={active=true,dueAt=123500}end
    reset(j,mode=='running')
    if mode=='checking' then M.resume() end
    local open=assert(findItem(M.menuItems(),mode=='scheduled' and 'Cancel scheduled resume and open reading copy' or 'Pause and open reading copy'))
    check(not open.disabled,'reading copy remains available while '..mode)
    open.fn()
    eq(#test.opens,1,'reading copy opens once from '..mode)
    eq(test.opens[1].running,false,'translation pauses before foreground open from '..mode)
    check(not test.opens[1].checking,'checks cancel before foreground open from '..mode)
    check(not test.opens[1].scheduled,'quota timer cancels before foreground open from '..mode)
    if mode=='checking' then
        nextCallback()
        eq(select(2,T.state()),false,'opening reading copy cancels deferred resume')
    end
end
-- Restore uses the saved outcome, never a hard-coded paused title.
for _,variant in ipairs({'finished','legacy-finished','warning','paused'})do
    local j=job(variant:find('finished',1,true)and 0 or 3)
    j.pauseKind=variant~='legacy-finished' and variant or nil
    j.pauseReason=variant:find('finished',1,true)and finished or variant=='warning' and 'Collection failed' or 'Paused. Gemini itself may still finish its reply.'
    reset(nil,false);test.saved[j.folder..'/checkpoint.json']=clone(j)
    check(M.restoreFolder(j.folder),'restores '..variant)
    eq(menu.title,'BT '..(variant=='legacy-finished' and 'finished' or variant),'restore title '..variant)
    eq(M.uiState().bookTitle,j.bookTitle,'restored menu book title')
    local actual=select(1,T.state());eq(actual.remaining,j.remaining,'restore retains batch count')
end
-- Guard failures must replace a stale success label, and successful resume clears it.
do
    local j=job(0);j.pauseKind='finished';j.pauseReason=finished;reset(j,false)
    test.guardError='Wrong book window';T.resume(true)
    eq(j.pauseKind,'warning','resume guard warns after completed batch')
    eq(menu.title,'BT warning','resume guard cannot retain finished display')
    eq(j.remaining,0,'failed resume does not create batch')
    j=job();j.pauseKind='warning';j.pauseReason='Old problem';reset(j,false)
    T.resume(true)
    eq(j.pauseKind,nil,'successful resume clears persisted warning')
    eq(j.pauseReason,nil,'successful resume clears prior reason')
    eq(M.uiState().kind,'saving','successful resume starts existing saved phase')
    eq(select(2,T.state()),true,'successful resume runs existing job')
end
-- A background reading-copy build must not conceal a translation failure.
do
    local j=job();j.pauseKind='warning';j.pauseReason='Turn could not be verified'
    reset(j,false)
    T.set{job=j,build={folder=j.folder,status='running'}}
    eq(menu.title,'BT warning','background build cannot conceal durable warning')
    check(M.uiState().tooltip:find('Turn could not be verified',1,true)~=nil,'failure remains visible during background build')
end
-- Status persistence errors surface even if the in-memory outcome was complete.
do
    local j=job(0);reset(j,true);test.failWrite=true;T.pause(finished,'finished')
    eq(menu.title,'BT warning','checkpoint failure overrides apparent finish')
    check(M.uiState().tooltip:find('fixture disk full',1,true)~=nil,'checkpoint failure reason visible')
    test.failWrite=false
end
print('Actual main integration: '..checks..' checks passed')
