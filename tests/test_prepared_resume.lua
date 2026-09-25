local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Exercise actual resume/tick/submit/send functions with memory-only I/O and
-- simulated editor reads. No native UI, timers, filesystem writes, or typing.
local requested=paths.source('gemini_book.lua')
local f=assert(io.open(requested));local source=f:read('*a');f:close();assert(load(source,'compile main'))
local function loadModule(name)return dofile(paths.source(name..'.lua'))end
local core=loadModule('gemini_book_core')
local status=loadModule('gemini_book_status')
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local function eq(a,b,message)check(a==b,message..': expected '..tostring(b)..', got '..tostring(a))end
local function clone(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=clone(x)end;return out end
local s={time=100,writes={},returns=0,pastes=0,clicks=0,moves=0,scans=0,logs={},messages={},settings={},timers={}}
local hs={configdir='/fixture',settings={get=function(k)return s.settings[k]end,set=function(k,v)s.settings[k]=clone(v)end},
    menubar={new=function()return {setTitle=function()end,setTooltip=function()end,setMenu=function()end}end},
    timer={secondsSinceEpoch=function()return s.time end,doEvery=function()return {stop=function()end}end,
        doAfter=function(_,fn)s.timers[#s.timers+1]=fn end},hotkey={bind=function()return {}end},
    json={encode=clone,decode=clone},alert={show=function(text)s.messages[#s.messages+1]=text;return #s.messages end,
        closeAll=function()end,closeSpecific=function()end},screenRecordingState=function()return true end,
    mouse={absolutePosition=function()s.moves=s.moves+1 end},eventtap={},caffeinate={set=function()end},
    pasteboard={changeCount=function()return 0 end}}
local mods={gemini_book_epub=dofile(paths.source("gemini_book_epub.lua")),gemini_book_status=status,gemini_book_core=core,
    gemini_book_limits={normalize=function(x)return tostring(x or ''):lower()end},
    gemini_book_provider=dofile(paths.source("gemini_book_provider.lua")),
    gemini_book_resume={modelLabel=function(x)return x end}}
local env=setmetatable({hs=hs,_S=s,_CLONE=clone,print=function()end,
    require=function(name)return mods[name]or{}end},{__index=_G})
local injected=[[
atomicWrite=function(path,value)
    if _S.failCheckpoint then error('checkpoint unavailable')end
    _S.writes[path]=_CLONE(value)
end
readFile=function()return string.rep('translation instructions ',12)end
log=function(text)_S.logs[#_S.logs+1]=text end
beginOwnership=function()end
releaseOwnership=function()end
guard=function()if _S.badWindow then return nil,'Wrong window'end;return {focus=function()end}end
stableSourceCapture=function(label,active,done,failed,expected)
    done({},_S.sourceHash)
end
pendingSourceStillVisible=function()return _S.sourceHash==job.pending.sourceHash end
evaluationSourceProblem=function()return _S.evaluationError end
scanButtons=function(done)
    _S.scans=_S.scans+1
    if _S.scanProblem then pause(_S.scanProblem);return end
    done({},_S.generating,{},nil,'Flash')
end
focusDescription=function()return 'fixture editor'end
inputFailure=function(message)
    _S.failure=message
    pause(message)
end
readyInput=function(requireEmpty)
    _S.requireEmpty=requireEmpty
    if not _S.focused then inputFailure('Cannot verify editor focus');return end
    if requireEmpty and (type(_S.draft)~='string' or core.trim(_S.draft)~='')then
        inputFailure('Foreign or nonempty draft');return
    end
    return {},nil,_S.draft
end
pasteRequestOnce=function(text)_S.pastes=_S.pastes+1;_S.draft=text;return true end
hs.eventtap.leftClick=function()_S.clicks=_S.clicks+1;_S.focused=not _S.failFocus end
hs.eventtap.keyStroke=function(mods,key)
    assert(key=='return' and #mods==0,'Only one final Return is allowed')
    assert(job.pending.sent==true,'Write-ahead sent must precede Return')
    assert(_S.writes[job.folder..'/checkpoint.json'].pending.sent==true,'Durable write-ahead sent must precede Return')
    _S.returns=_S.returns+1
end
M._test={resume=resumeNow,tick=tick,pause=pause,
    set=function(value)
        job=value;running=false;phase='restored';epoch=0;due=0;scanPending=false
        recoveryActive=false;sessionWarning=nil;resumeCaptureEpoch=nil
        inputReadback=nil;inputWaitPhase=nil;verifiedInput=nil;pasteInFlight=false
        illustrationBuild={status='idle'};cfg.illustrationsEnabled=false
        cal={input={x=100,y=100}}
    end,
    state=function()return job,running,phase,due end,
    phase=function(value)setPhase(value)end}
return M
]]
local instrumented,n=source:gsub('return M%s*$',injected);assert(n==1)
local M=assert(load(instrumented,'actual main memory harness','t',env))()
local T=M._test
local instructions=string.rep('Translation instructions for current visible source only. ',4)
local function fixture(kind)
    local p={index=2,id='fixture-00002',sourceHash='saved-source',sent=false}
    if kind~='fresh' then
        p.inputMode='inline';p.composerPrefix='';p.requestText=core.inlineRequestText(p.id,instructions);p.pasteAttemptedAt=99
    end
    if kind=='sent'then p.sent=true;p.sentAt=99 end
    local j={folder='/fixture/book',bookTitle='Fixture Vol. 07',tag='fixture',records={{index=1,id='fixture-00001'}},
        remaining=68,pending=p,needAdvance=false,requestMode='inline',pauseKind='paused',pauseReason='Paused. Gemini itself may still finish its reply.'}
    for _,k in ipairs({'returns','pastes','clicks','moves','scans'})do s[k]=0 end
    s.writes={};s.time=100;s.logs={};s.messages={};s.failure=nil;s.generating=false;s.scanProblem=nil
    s.badWindow=false;s.focused=false;s.failFocus=false;s.failCheckpoint=false;s.evaluationError=nil
    s.sourceHash=p.sourceHash;s.draft=p.requestText or '';T.set(j)
    return j,p
end
local function tick(dt)
    local _,_,_,due=T.state();s.time=math.max(s.time+(dt or .1),due or 0);T.tick()
end
local function phase()return select(3,T.state())end
local function resumeToCheck(j)
    T.resume(true);eq(phase(),'preflight','unsent request still starts with preflight')
    tick();eq(phase(),'focus','preflight still checks Gemini idle')
    tick();eq(s.clicks,1,'resume focuses composer once')
    eq(phase(),'resume-inline','prepared request routes to content classification')
end
local function resumeToDraft(j)
    resumeToCheck(j);tick()
    eq(phase(),'submit','nonempty prepared request routes to full draft readback')
end
local function verifyThenSend()
    tick();eq(phase(),'submit','draft needs stable full readback')
    tick(.2);eq(phase(),'submit-check','stable draft reaches submission checks')
    tick();eq(phase(),'send','live model and generating checks run before Send')
    tick();eq(phase(),'wait','one submission transitions to collection')
end
-- Owned full inline draft continues without modifying or repasting its text.
do
    local j,p=fixture('prepared');local original=p.requestText
    resumeToDraft(j);verifyThenSend()
    eq(s.pastes,0,'prepared draft never repasted');eq(s.returns,1,'prepared draft sent exactly once')
    eq(s.draft,original,'prepared draft content preserved');eq(p.id,'fixture-00002','request identity unchanged')
    eq(p.sent,true,'pending now marked sent');eq(j.remaining,68,'submission does not consume page count')
    eq(#j.records,1,'submission does not fabricate saved page')
end
-- Fresh requests still enter the ordinary empty-editor/paste path.
do
    local j=fixture('fresh');T.resume(true);tick();tick()
    eq(phase(),'paste-inline','fresh request uses existing paste path')
    tick();eq(s.pastes,1,'fresh request pasted once');eq(phase(),'submit','fresh paste then verifies')
    eq(s.returns,0,'fresh paste does not submit directly')
end
-- Sent state always wins even if prepared metadata survives a crash.
do
    local j,p=fixture('sent');T.resume(true)
    eq(phase(),'wait','sent request only collects');eq(p.sentAt,100,'sent request gets fresh collection deadline')
    eq(s.clicks,0,'sent request does not focus composer');eq(s.pastes,0,'sent request never repasted');eq(s.returns,0,'sent request never resent')
end
-- Foreign, partial, empty and duplicate drafts fail closed; no clipboard mutation.
for _,variant in ipairs({'foreign','partial','duplicated','unreadable'})do
    local j,p=fixture('prepared')
    if variant=='foreign'then s.draft='Unrelated private draft'elseif variant=='partial'then s.draft=p.requestText:sub(1,30)
    elseif variant=='duplicated'then s.draft=p.requestText..' '..p.requestText else s.draft=false end
    local before=s.draft;resumeToDraft(j);tick();tick(16)
    eq(select(2,T.state()),false,variant..' draft stops')
    eq(j.pauseKind,'warning',variant..' draft warns');eq(p.sent,false,variant..' not marked sent')
    eq(s.pastes,0,variant..' never overwritten');eq(s.returns,0,variant..' never submitted')
    eq(s.draft,before,variant..' content untouched')
end
-- An empty composer gets one ordinary guarded paste of the same pending ID.
do
    local j,p=fixture('prepared');s.draft='';local id=p.id
    resumeToCheck(j);tick();eq(phase(),'paste-inline','empty draft follows guarded paste path')
    eq(s.pastes,0,'classification itself never pastes')
    tick();eq(phase(),'submit','freshly pasted request still requires readback')
    eq(s.pastes,1,'empty composer gets one paste');eq(p.id,id,'empty composer retains request ID')
    verifyThenSend();eq(s.returns,1,'empty composer submits once after verification')
end
-- A foreign draft appearing after empty classification must not be overwritten.
do
    local j,p=fixture('prepared');s.draft='';resumeToCheck(j);tick()
    s.draft='New user draft';tick()
    eq(select(2,T.state()),false,'new draft between checks stops')
    eq(s.pastes,0,'new draft between checks never overwritten');eq(s.returns,0,'new draft between checks never sent')
    eq(s.draft,'New user draft','new draft remains intact')
end
-- Missing ownership evidence never bypasses the ordinary empty-editor guard.
for _,variant in ipairs({'missing-mode','missing-paste-time','invalid-paste-time','wrong-request-ID','missing-request'})do
    local j,p=fixture('prepared')
    if variant=='missing-mode'then p.inputMode=nil elseif variant=='missing-paste-time'then p.pasteAttemptedAt=nil
    elseif variant=='invalid-paste-time'then p.pasteAttemptedAt='yesterday'
    elseif variant=='wrong-request-ID'then p.requestText=core.inlineRequestText('other-00001',instructions)
    else p.requestText=nil end
    T.resume(true);tick();tick();eq(phase(),'paste-inline',variant..' does not reuse unowned draft')
    tick();eq(select(2,T.state()),false,variant..' nonempty draft stops')
    eq(s.pastes,0,variant..' draft never overwritten');eq(s.returns,0,variant..' draft never sent')
end
-- Readback tolerates only normal Chrome layout whitespace.
do
    local j,p=fixture('prepared');s.draft=p.requestText:gsub('\n','  ');resumeToDraft(j);verifyThenSend()
    eq(s.pastes,0,'layout-only draft not repasted');eq(s.returns,1,'layout-equivalent full request accepted')
end
-- Every existing submission guard still applies during resumed preparation.
for _,variant in ipairs({'generation-preflight','generation-submit','source-start','source-send','changed-draft','wrong-window','focus-failed','quota'})do
    local j,p=fixture('prepared')
    if variant=='generation-preflight'then s.generating=true;T.resume(true);tick()
    elseif variant=='source-start'then s.sourceHash='other-page';T.resume(true)
    elseif variant=='wrong-window'then s.badWindow=true;T.resume(true)
    elseif variant=='focus-failed'then s.failFocus=true;resumeToCheck(j);tick()
    elseif variant=='quota'then s.scanProblem='Service limit';T.resume(true);tick()
    else
        resumeToDraft(j);tick();tick(.2)
        if variant=='generation-submit'then s.generating=true;tick()
        else tick();if variant=='source-send'then s.sourceHash='other-page'else s.draft='Changed after verification'end;tick()end
    end
    eq(select(2,T.state()),false,variant..' stops')
    eq(j.pauseKind,'warning',variant..' warns');eq(p.sent,false,variant..' retains unsent state')
    eq(s.returns,0,variant..' no Return');eq(s.pastes,0,variant..' no repaste')
end
-- Failure to durably mark sent prevents the Return from being dispatched.
do
    local j,p=fixture('prepared');resumeToDraft(j);tick();tick(.2);tick();s.failCheckpoint=true
    local ok=pcall(tick);eq(ok,false,'write-ahead failure propagates to safe wrapper')
    eq(s.returns,0,'failed checkpoint prevents Return');s.failCheckpoint=false
end
print('Prepared-draft resume: '..checks..' actual-source checks passed ('..requested..')')
