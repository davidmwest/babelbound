local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Exercise the actual main tick and pending-source equality check. The clock,
-- source capture, UI targets and durable writes are synthetic; no native input
-- or files are produced. Fresh-control lookup remains distinct from a click.
local f=assert(io.open(paths.source("gemini_book.lua")));local source=f:read("*a");f:close()
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local function eq(a,b,message)check(a==b,message..": expected "..tostring(b)..", got "..tostring(a))end
local function clone(v)if type(v)~="table"then return v end;local out={};for k,x in pairs(v)do out[k]=clone(x)end;return out end
local s={time=100,hash="original-source",captures=0,clicks={},keys=0,scrolls=0,moves=0,
    timers={},files={},messages={},settings={},visibleChecks={},scans=0}
local hs={configdir="/fixture/config",settings={get=function(k)return s.settings[k]end,set=function(k,v)s.settings[k]=clone(v)end},
    menubar={new=function()return {setTitle=function(_,title)s.title=title end,setTooltip=function()end,setMenu=function()end}end},
    timer={secondsSinceEpoch=function()return s.time end,doEvery=function()return {stop=function()end}end,
        doAfter=function(seconds,fn)local item={at=s.time+seconds,fn=fn};s.timers[#s.timers+1]=item;return {stop=function()item.cancelled=true end}end},
    hotkey={bind=function()return {}end},json={encode=clone,decode=clone},
    alert={show=function(text)s.messages[#s.messages+1]=text;return #s.messages end,closeAll=function()end,closeSpecific=function()end},
    eventtap={leftClick=function(point)s.clicks[#s.clicks+1]=clone(point)end,
        keyStroke=function()s.keys=s.keys+1;error("Copy-source checking must not type")end,
        scrollWheel=function()s.scrolls=s.scrolls+1;error("Copy-source checking must not scroll")end},
    pasteboard={changeCount=function()return 5 end},caffeinate={set=function()end}}
local modules={}
local env=setmetatable({hs=hs,_S=s,_CLONE=clone,print=function()end,require=function(name)
    if not modules[name]then modules[name]=dofile(paths.source(name..".lua"))end;return modules[name]
end},{__index=_G})
local injection=[[
atomicWrite=function(path,value)_S.files[path]=_CLONE(value)end
readFile=function(path)return _S.files[path]end
mkdir=function()end
log=function()end
guard=function()if _S.guardError then return nil,_S.guardError end;return {focus=function()end}end
capture=function()_S.captures=_S.captures+1;return {},_S.hash end
movePointer=function()_S.moves=_S.moves+1 end
visibleCopyAt=function(candidate)
    _S.visibleChecks[#_S.visibleChecks+1]=candidate.name
    return candidate.element
end
probeComposerReadiness=function(done)done('idle',{startedAt=now()})end
scanButtons=function(done)
    _S.scans=_S.scans+1
    done({_S.freshTarget},false,{})
end
M.config.illustrationsEnabled=false;M.config.epubEnabled=false
M._test={tick=tick,
    set=function(selected,pending,target)
        provider=selected;epoch=40;running=true;phase='copy-click';due=0
        job={folder='/fixture/Book-Synthetic',bookTitle='Synthetic',provider=selected,tag='fixture',
            records={},remaining=3,pending=pending,needAdvance=false}
        cal={provider=selected,input={x=1100,y=850},panel={x=800,y=100},windowFrame={x=0,y=0,w=1200,h=900}}
        collection={id=pending.id,index=pending.index,startedAt=now(),copies=0,scrolls=0,viewReady=true,rejected={},events={}}
        copyTarget=target;copyBefore=nil;copyStarted=nil;copyClipboardState=nil
        scan=nil;scanPending=false;recoveryActive=false;resumeCaptureEpoch=nil;sessionWarning=nil
        illustrationTask=nil;illustrationBuild={status='idle'}
        responseCandidate=nil;responseSince=nil;verifiedInput=nil
        readinessStats={pendingID=pending.id,checks=0,generating=0,idle=0,unknown=0,fullScans=0,intervals=0,intervalTotal=0}
        clipboardBackup=nil;clipboardOwnedCount=nil;sleepBackup=nil
        refreshMenu()
    end,
    state=function()return {job=job,phase=phase,running=running,due=due,collection=collection,target=copyTarget,epoch=epoch}end
}
return M
]]
local transformed,count=source:gsub("return M%s*$",injection);assert(count==1)
local M=assert(load(transformed,"actual copy-source memory harness","t",env))()
local T=M._test
local function target(name,x)
    return {name=name,center={x=x,y=700},label="Copy",element={attributeValue=function(_,key)
        if key=="AXTitle"then return "Copy"end
    end}}
end
local function reset(provider,hash)
    s.time=100;s.hash=hash or "different-source";s.captures=0;s.clicks={};s.keys=0;s.scrolls=0;s.moves=0
    s.timers={};s.files={};s.messages={};s.visibleChecks={};s.scans=0;s.guardError=nil
    s.freshTarget=target("fresh",1080)
    local p={id="fixture-00001",index=1,sourceHash="original-source",sent=true,sentAt=90,provider=provider or "chatgpt"}
    T.set(provider or "chatgpt",p,target("stale",1010));return T.state().job
end
local function tick(dt,hash)
    s.time=s.time+(dt or 0);if hash~=nil then s.hash=hash end;T.tick();return T.state()
end
local function noActions(label)
    eq(#s.clicks,0,label.." has no click");eq(s.keys,0,label.." has no typing")
    eq(s.scrolls,0,label.." has no scroll");eq(s.moves,0,label.." has no pointer movement")
end
local function unchanged(j,label)
    eq(j.pending.id,"fixture-00001",label.." retains sent ID")
    eq(j.pending.sent,true,label.." retains sent state")
    eq(j.pending.sentAt,90,label.." retains response deadline origin")
    eq(j.pending.sourceHash,"original-source",label.." retains source reference")
    eq(j.remaining,3,label.." retains batch count");eq(#j.records,0,label.." creates no translation")
    eq(j.needAdvance,false,label.." does not authorize page turn")
end

-- Normal matching Copy does not pay a stability wait on either provider.
for _,provider in ipairs({"gemini","chatgpt"})do
    local j=reset(provider,"original-source");local state=tick()
    eq(state.phase,"clipboard",provider.." matching source copies immediately")
    eq(#s.clicks,1,provider.." uses exactly one Copy click")
    eq(s.clicks[1].x,1010,provider.." uses verified current target")
    eq(state.collection.copies,1,provider.." counts one attempt")
    eq(state.target,nil,provider.." drops target after click")
    eq(s.captures,1,provider.." uses ordinary one source check")
    eq(state.collection.sourceWaitStarted,nil,provider.." opens no recheck window")
    eq(s.keys,0,provider.." sends no translation");unchanged(j,provider.." normal copy")
end

-- A mismatch must not relax Gemini behavior.
do
    local j=reset("gemini");local state=tick()
    eq(state.running,false,"Gemini mismatch pauses immediately")
    eq(j.pauseKind,"warning","Gemini mismatch remains a warning")
    eq(state.collection.sourceWaitStarted,nil,"Gemini never enters source grace window")
    noActions("Gemini mismatch");unchanged(j,"Gemini mismatch")
end

-- A transient mismatch may recover only after a full second of consecutive
-- original hashes. The old target is discarded, then fresh controls are read.
do
    local j=reset();local state=tick()
    eq(state.phase,"copy-source-check","ChatGPT mismatch enters read-only phase")
    eq(state.running,true,"short transient does not immediately pause")
    eq(state.collection.sourceWaitStarted,100,"deadline anchored to first mismatch")
    eq(state.collection.sourceWaitMatchedAt,nil,"mismatch has no stability credit")
    eq(state.target,nil,"first mismatch immediately discards old Copy target")
    eq(s.title,"BT saving (0%)","source recheck is shown as saving")
    tick(.01,"original-source");eq(s.captures,1,"ordinary fast tick does not bypass polling cadence")
    state=tick(.33);local matched=state.collection.sourceWaitMatchedAt
    eq(matched,s.time,"first original sample starts stable interval")
    tick(.34);state=tick(.34)
    eq(state.phase,"copy-source-check","less than one second is insufficient")
    noActions("unstable interval");unchanged(j,"transient wait")
    state=tick(.34)
    eq(state.phase,"wait","stable original reacquires reply controls")
    eq(state.target,nil,"stale Copy target is discarded")
    eq(state.collection.copies,0,"read-only checks consume no Copy attempts")
    eq(#s.visibleChecks,0,"old target is not revalidated or clicked during wait")
    noActions("stable source transition")
    state=tick(.34)
    eq(s.scans,1,"fresh sidebar scan runs after recovery")
    eq(state.phase,"copy-click","fresh control follows ordinary hover path")
    eq(state.target,s.freshTarget,"reacquired target replaces old coordinates")
    state=tick(.1)
    eq(state.phase,"clipboard","fresh target reaches normal clipboard path")
    eq(#s.clicks,1,"one Copy after fresh controls")
    eq(s.clicks[1].x,1080,"fresh coordinate clicked; stale coordinate unused")
    eq(s.visibleChecks[#s.visibleChecks],"fresh","fresh live target rechecked at click time")
    unchanged(j,"recovered copy")
end

-- No original hash and intermittent originals both stop within the same
-- bounded window; accumulated matching time must never substitute stability.
for _,scenario in ipairs({"never-returns","oscillates","near-match-only"})do
    local j=reset();tick()
    for i=1,6 do
        local hash=scenario=="oscillates" and i%2==1 and "original-source" or
            (scenario=="near-match-only" and "original-source-with-one-difference" or "different-source")
        tick(.34,hash)
    end
    -- Skip synthetic idle time rather than running ninety equivalent polls.
    tick(129.65-s.time)
    eq(T.state().running,true,scenario.." may wait until the thirty-second bound")
    eq(T.state().collection.sourceWaitStarted,100,scenario.." does not reset deadline")
    tick(130-s.time)
    local state=T.state()
    eq(state.running,false,scenario.." times out at thirty seconds")
    eq(j.pauseKind,"warning",scenario.." pauses with warning")
    eq(state.collection.copies,0,scenario.." uses no copy attempt")
    noActions(scenario);unchanged(j,scenario)
    local captures=s.captures;tick(1,"original-source")
    eq(s.captures,captures,scenario.." stays paused after source returns")
end

-- A late exact return does not extend the thirty-second deadline to gain one
-- second of matching time; fluctuations also restart the stable interval.
do
    local j=reset();tick();tick(.34,"original-source");tick(.34);tick(.34,"different-source")
    eq(T.state().collection.sourceWaitMatchedAt,nil,"mismatch clears prior match interval")
    tick(.34,"original-source");tick(.34)
    eq(T.state().phase,"copy-source-check","two separate partial intervals do not add")
    tick(.34,"different-source");tick(129.3-s.time);tick(.34,"original-source");tick(.34)
    eq(T.state().running,true,"late match remains inside original deadline")
    tick(.34)
    eq(T.state().running,false,"late return cannot renew deadline")
    eq(j.pauseKind,"warning","late return requires manual review")
    noActions("late return");unchanged(j,"late return")
end

-- Chrome can keep its debugging banner visible for longer than the former
-- three-second grace period. A later exact return still requires one stable
-- second and leaves the original request timeout and source reference intact.
do
    local j=reset();tick();tick(8,"different-source")
    eq(T.state().phase,"copy-source-check","banner beyond three seconds can still clear")
    tick(4,"original-source");tick(.34);tick(.34)
    eq(T.state().phase,"copy-source-check","late source return still needs a full stable second")
    tick(.34)
    eq(T.state().phase,"wait","late stable original returns to fresh controls")
    eq(T.state().target,nil,"late recovery does not retain old Copy control")
    noActions("late but valid recovery");unchanged(j,"late but valid recovery")
end

-- The source grace period does not renew the overall reply budget. Once the
-- source is restored, the normal wait state checks the unchanged sentAt before
-- any fresh control scan or Copy click.
do
    local j=reset();j.pending.sentAt=s.time-M.config.responseTimeout+1
    local sentAt=j.pending.sentAt
    tick();tick(12,"original-source");tick(.34);tick(.34);tick(.34)
    eq(T.state().phase,"wait","stable source returns to ordinary reply wait")
    tick(.34)
    eq(T.state().running,false,"expired response budget still pauses")
    eq(j.pauseKind,"warning","expired response requires review")
    eq(j.pending.sentAt,sentAt,"source grace never resets response clock")
    eq(j.pending.id,"fixture-00001","expired request retains its original ID")
    eq(j.pending.sent,true,"expired request remains sent rather than retried")
    eq(s.scans,0,"response timeout stops before fresh controls")
    noActions("expired overall response")
end

-- Any newly changed source after recovery is checked again before the fresh
-- Copy click. Recovery never permits a click based only on earlier samples.
do
    local j=reset();tick();tick(.34,"original-source");tick(.34);tick(.34);tick(.34)
    tick(.34);eq(T.state().phase,"copy-click","fresh target is ready")
    tick(.1,"changed-again")
    eq(T.state().phase,"copy-source-check","changed source before fresh click rechecks")
    eq(#s.clicks,0,"changed-again source prevents fresh Copy click")
    unchanged(j,"source changed again")
end

-- Stop/epoch changes cancel queued readiness checks. A guard failure also
-- stops before another capture, even if the pending source would match.
do
    local j=reset();tick();tick(.34,"original-source");M.stop()
    local before=s.captures;local callbacks=s.timers;s.timers={};s.time=s.time+10
    for _,timer in ipairs(callbacks)do if not timer.cancelled then timer.fn()end end
    T.tick();eq(s.captures,before,"Stop cancels source-check callbacks")
    eq(T.state().running,false,"Stop leaves job paused")
    noActions("cancelled wait");unchanged(j,"cancelled wait")
end
do
    local j=reset();tick();s.guardError="Wrong current sidebar";local before=s.captures
    tick(.34,"original-source")
    eq(s.captures,before,"guard failure prevents capture/recovery")
    eq(T.state().running,false,"guard failure stops checking")
    noActions("guard failure");unchanged(j,"guard failure")
end
for _,scenario in ipairs({"no-longer-sent","replaced-request","missing-start-time"})do
    local j=reset();tick()
    if scenario=="no-longer-sent"then j.pending.sent=false
    elseif scenario=="replaced-request"then j.pending.id="different-request"
    else T.state().collection.sourceWaitStarted=nil end
    local before=s.captures;tick(.34,"original-source")
    eq(T.state().running,false,scenario.." fails closed")
    eq(s.captures,before,scenario.." stops before claiming source stability")
    eq(j.pauseKind,"warning",scenario.." records warning")
    noActions(scenario)
end
print("Copy source stability: "..checks.." actual-source checks passed")
