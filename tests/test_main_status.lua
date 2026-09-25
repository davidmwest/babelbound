local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Actual main-module functions with memory-only I/O/UI stand-ins. No UI calls,
-- subprocesses, filesystem writes, timers firing or translations occur.
local path=paths.source("gemini_book.lua")
local f=assert(io.open(path));local source=f:read('*a');f:close()
assert(load(source,'compile actual main'))
local S=dofile(paths.source("gemini_book_status.lua"))
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function eq(a,b,message)check(a==b,(message or 'check')..': expected '..tostring(b)..', got '..tostring(a))end
local function clone(v)if type(v)~='table' then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local test={writes={},messages={},logs={},settings={},scheduled={},saved={}}
local menu={setTitle=function(self,title)self.title=title end,setTooltip=function(self,title)self.tooltip=title end,
    setMenu=function(self,fn)self.items=fn end}
local hs={configdir='/fixture/config',settings={get=function(k)return test.settings[k]end,set=function(k,v)test.settings[k]=clone(v)end},
    menubar={new=function()return menu end},timer={secondsSinceEpoch=function()return 123456 end,
        doEvery=function()return {stop=function()end}end,doAfter=function(_,fn)test.scheduled[#test.scheduled+1]=fn end},
    hotkey={bind=function()return {}end},json={encode=clone,decode=clone},alert={show=function(s)test.messages[#test.messages+1]=s;return #test.messages end,
        closeAll=function()end,closeSpecific=function()end},screenRecordingState=function()return test.permission~=false end,
    pasteboard={readAllData=function()return {}end,changeCount=function()return 0 end},
    caffeinate={get=function()return false end,set=function()end},dialog={textPrompt=function()return test.dialogButton or 'Cancel',test.dialogValue or ''end}}
local actualJobs=dofile(paths.source("gemini_book_jobs.lua"))
local modules={gemini_book_epub=dofile(paths.source("gemini_book_epub.lua")),gemini_book_status=S,gemini_book_core={markdown=function()return 'markdown'end,html=function()return 'html'end},
    gemini_book_jobs=actualJobs,gemini_book_limits={normalize=function(s)return tostring(s or ''):lower()end},
    gemini_book_provider=dofile(paths.source("gemini_book_provider.lua")),
    gemini_book_resume={modelLabel=function(s)return s end}}
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
handleUsageLimit=function(event,origin)
    _TEST.limitCalls=(_TEST.limitCalls or 0)+1
    _TEST.lastLimit={event=event,origin=origin}
    pause('Fixture service quota blocked')
end
guard=function()
    if _TEST.guardError then return nil,_TEST.guardError end
    return {focus=function()end}
end
stableSourceCapture=function(label,active,done,failed,expected)
    if _TEST.captureError then failed(_TEST.captureError);return end
    done({},_TEST.hash or expected or 'source')
end
beginOwnership=function()end
waitForPage=function()setPhase('settle')end
M._test={pause=pause,save=saveAnswer,resume=resumeNow,checkpoint=checkpoint,warning=warningNotice,
    set=function(state)
        job=state.job;running=state.running==true;phase=state.phase or 'idle';due=0
        recoveryActive=false;resumeCaptureEpoch=nil;sessionWarning=state.warning;epoch=0
        illustrationBuild=state.build or {status='idle'};illustrationTask=nil;quota.timer=nil;scan=nil
        cfg.illustrationsEnabled=false;cfg.epubEnabled=false;refreshMenu()
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
    T.set{job=j,running=running}
end
local finished='Batch complete. Last page remains visible. Review the saved translation.'
local function pending(j)
    j.pending={index=#j.records+1,id='new',sourceHash='source',sent=true,modelAtSubmit='Flash'};return j
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
    local function start(items)for _,x in ipairs(items)do if x.title:match('^Start / resume')then return x.title end end end
    eq(start(M.menuItems()),'Start / resume — Extremely Long Full Series Name Vol. 107 (Ctrl-Option-Cmd-S)','full volume title in real menu')
    j.bookTitle='Renamed Series Vol. 208'
    eq(start(M.menuItems()),'Start / resume — Renamed Series Vol. 208 (Ctrl-Option-Cmd-S)','menu reads renamed title')
    reset(nil,false)
    local title=start(M.menuItems())
    check(title:find('No book loaded',1,true)~=nil,'no-job menu is honest')
    check(not title:find('Vol.',1,true),'no-job menu cannot name old/frontmost book')
    local oldRestore=M.restoreLatest;local restored=0
    M.restoreLatest=function()restored=restored+1;return true end
    T.resume(true)
    eq(restored,1,'no-job resume restores rather than creates')
    eq(select(1,T.state()),nil,'no-job resume does not create a fake job')
    M.restoreLatest=oldRestore
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
