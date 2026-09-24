local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local path=paths.source("gemini_book.lua")
assert(loadfile(path))
local f=assert(io.open(path));local source=f:read('*a');f:close()
local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function clone(value)
    if type(value)~='table' then return value end
    local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
end
local guardCode=assert(source:match('(local function turnInputGuard%(p%).-)\nlocal function startTurnTrace'))
local turnCode=assert(source:match('(local function startTurnTrace%(img,hash%).-)\nlocal function preparePage'))
local tickCode=assert(source:match('(tick = function%(%).-)\nfunction M.calibrate'))
local function fixture()
    local s={time=0,saves={},writes={},clicks=0,moves=0,checkpoints={},hash='saved',prepared=0,
        keys={},buttons={},pointer={x=100,y=500},hit={pid=123,AXRole='AXImage',AXEnabled=true}}
    local app={bundleID=function()return 'com.google.Chrome'end,pid=function()return 123 end}
    local env={phase='advance-ready',running=true,due=0,scanPending=false,epoch=1,
        cfg={chromeBundle='com.google.Chrome',detailedTurnScreenshots=false,turnHoverSeconds=.35,
            turnClickHoldUS=80000,postTurnDelay=.15,pageMinimumWait=2,pageStableSeconds=2,
            pageChangeTimeout=45,pageUnchangedTimeout=8,pollSeconds=1/3,turnFocusTimeout=2,turnFocusPollSeconds=.05},
        cal={windowFrame={x=0,y=0,w=2000,h=1200},panel={x=1500,y=100},input={x=1600,y=1150},
            next={x=100,y=500},crop={x=0,y=0,w=1400,h=1100}},
        job={folder='/fixture',records={{}},lastSourceHash='saved',remaining=1,needAdvance=true},
        M={version='test'},now=function()return s.time end,mkdir=function()end,log=function()end,
        pointDescription=function()return 'reader image'end,
        pidOf=function(hit)return hit and hit.pid end,attr=function(hit,key)return hit[key]end,
        guard=function()return not s.badWindow and {} or nil,'Window changed'end,
        movePointer=function(p)s.moves=s.moves+1;s.pointer={x=p.x,y=p.y}end,
        atomicWrite=function(path,value)s.writes[path]=clone(value)end,
        hs={json={encode=clone},application={frontmostApplication=function()return not s.noApp and app or nil end},
            mouse={absolutePosition=function()if s.pointerError then error('pointer unavailable')end;return s.pointer end},
            axuielement={systemWideElement=function()return {elementAtPosition=function()
                if s.hitError then error('AX unavailable')end;return s.hit
            end}end},eventtap={checkKeyboardModifiers=function()
                if s.keysError then error('keys unavailable')end;return s.keys
            end,checkMouseButtons=function()
                if s.buttonsError then error('buttons unavailable')end;return s.buttons
            end}},
    }
    local img={saveToFile=function(_,path)s.saves[path]=true;return true end}
    env.capture=function()return img,s.hash end
    -- AX identity/focus logic is exercised independently against the real module
    -- in test_focus.lua; here controlled readiness drives the actual tick phases.
    env.bookFocus={prepare=function(_,_,_,at)
        s.focusSets=(s.focusSets or 0)+1
        local evidence={startedAt=at,ready=false}
        if s.focusPrepareError then evidence.error=s.focusPrepareError;return nil,s.focusPrepareError,evidence end
        s.expectedFocus={startedAt=at,evidence=evidence}
        return s.expectedFocus,nil,evidence
    end,check=function(_,_,state,at)
        check(state==s.expectedFocus,'Focus readback verifies the same resolved book area')
        s.focusChecks=(s.focusChecks or 0)+1
        state.evidence.ready=not s.focusWaiting and not s.focusLost and not s.focusError
        state.evidence.lastCheckedAt=at
        return state.evidence.ready,s.focusError
    end}

    env.setPhase=function(phase,delay)env.phase=phase;env.due=s.time+(delay or 0)end
    env.pause=function(why)env.running=false;s.paused=why end
    env.checkpoint=function()s.checkpoints[#s.checkpoints+1]={uncertain=env.job.turnUncertain,at=s.time}end
    env.hs.eventtap.leftClick=function(p,hold)
        check(env.job.turnUncertain==true,'Uncertainty is set before delivery')
        check(#s.checkpoints==1 and s.checkpoints[1].uncertain,'Checkpoint is written before delivery')
        local trace=s.writes[env.turnTrace.folder..'/trace.json']
        check(trace.clicks==1 and trace.preClickGuard.allowed,'One-click intent and guard evidence are durable before delivery')
        check(p.x==100 and p.y==500 and hold==80000,'Exact target and original hold are retained')
        check(not trace.clickCallReturnedAt,'Write-ahead trace does not claim delivery completed')
        s.clicks=s.clicks+1;s.time=s.time+.08
    end
    env.scheduleReadinessCheck=function(_,started)env.due=started+1/3 end
    env.preparePage=function(_,hash)s.prepared=s.prepared+1;s.preparedHash=hash;env.running=false end
    setmetatable(env,{__index=_G})
    assert(load(guardCode..'\n'..turnCode..'\n'..tickCode,'actual guard + turn + tick','t',env))()
    function s.step(time)s.time=time or math.max(s.time,env.due);env.tick()end
    function s.hover()s.step(0);s.step(.05);s.step(.05)end
    function s.click()s.step(.4)end
    function s.turn()s.hover();s.click();s.step(.64)
        check(env.phase=='settle' and s.clicks==1,'One click enters normal settling after the unchanged release delay')
    end
    function s.sample(elapsed,hash)
        if hash then s.hash=hash end
        env.due=0;s.step(env.pageStarted+elapsed)
    end
    s.env=env;return s
end

do
    local t=fixture();t.turn()
    local trace=t.env.turnTrace
    check(trace.preClickGuard.targetPID==123 and trace.preClickGuard.targetRole=='AXImage','Generic reader image is allowed after PID verification')
    check(trace.preClickGuard.pointer.x==100 and getmetatable(trace.preClickGuard.pointer)==nil,'Trace stores primitive pointer coordinates')
    check(trace.clickCallReturnedAt>trace.clickCallStartedAt,'Trace separately records click-wrapper start and return')
    check(trace.pointerAfterClick.x==100 and trace.pointerAfterClick.y==500,'Trace retains post-call pointer without claiming app acknowledgment')
    t.sample(0,'next');t.sample(1.999)
    check(t.prepared==0,'Fresh source still needs two seconds continuous stability')
    t.sample(2)
    check(t.prepared==1 and t.preparedHash=='next' and t.clicks==1,'Stable next source accepted with one click')
end
local blocks={
    {'pointer moved',function(t)t.pointer={x=103,y=500}end},
    {'held command',function(t)t.keys={cmd=true}end},
    {'held option',function(t)t.keys={alt=true}end},
    {'held shift',function(t)t.keys={shift=true}end},
    {'held control',function(t)t.keys={ctrl=true}end},
    {'held fn',function(t)t.keys={fn=true}end},
    {'held left mouse',function(t)t.buttons={[1]=true,left=true}end},
    {'held sparse other mouse',function(t)t.buttons={[8]=true}end},
    {'foreign hit PID',function(t)t.hit.pid=999 end},
    {'unknown hit PID',function(t)t.hit.pid=nil end},
    {'missing hit',function(t)t.hit=nil end},
    {'failed hit lookup',function(t)t.hitError=true end},
    {'disabled hit',function(t)t.hit.AXEnabled=false end},
    {'no frontmost Chrome',function(t)t.noApp=true end},
    {'unavailable keys',function(t)t.keysError=true end},
    {'unavailable buttons',function(t)t.buttonsError=true end},
    {'unavailable pointer',function(t)t.pointerError=true end},
}
for _,case in ipairs(blocks)do
    local t=fixture();t.hover();case[2](t);t.click()
    check(t.paused and t.clicks==0,case[1]..' pauses without a click')
    check(not t.env.job.turnUncertain and #t.checkpoints==0,case[1]..' does not commit click intent')
    check(t.env.job.remaining==1 and #t.env.job.records==1,case[1]..' retains remaining count and saved records')
    local trace=t.writes[t.env.turnTrace.folder..'/trace.json']
    check(trace.outcome=='blocked-before-click' and trace.clicks==0 and trace.preClickGuard.error,
        case[1]..' preserves explicit zero-click evidence')
end
do
    local t=fixture();t.hover();t.pointer={x=100.7,y=499.4};t.keys={capslock=true};t.click()
    check(t.clicks==1,'Normal pointer rounding and Caps Lock toggle are allowed')
    check(t.env.turnTrace.preClickGuard.keyboardModifiers[1]=='capslock','Caps Lock is still recorded')
    t=fixture();t.hover();t.badWindow=true;t.click()
    check(t.paused and t.clicks==0,'Existing window guard still prevents click')
    t=fixture();t.hover();t.env.running=false;t.click()
    check(t.clicks==0,'Pause while hovering still prevents click')
    t=fixture();t.hash='wrong source';t.step(0)
    check(t.paused and t.clicks==0,'Saved source mismatch still prevents navigation')
end
do
    local t=fixture();t.turn();t.sample(0);t.sample(7.999)
    check(not t.paused and t.clicks==1,'Unchanged page gets the full eight seconds')
    t.sample(8)
    check(t.paused and t.clicks==1 and t.prepared==0,'Wholly unchanged turn pauses at eight seconds without retry')
    check(t.env.job.turnUncertain and t.env.turnTrace.outcome=='failed-to-verify','Early failure preserves uncertain-turn recovery requirements')
    check(t.env.job.remaining==1 and #t.env.job.records==1,'Early failure does not consume or create a saved record')
    check(t.saves['/fixture/turn-failure.png'] and t.saves[t.env.turnTrace.folder..'/after.png'],
        'Early failure retains normal forensic source captures')
    t.sample(46)
    check(t.clicks==1,'Further ticks after the pause never retry the click')
end
do
    local t=fixture();t.turn();t.sample(0);t.sample(7.5,'loading');t.sample(8,'saved')
    check(not t.paused and t.env.turnTrace.changedSamples==1,'A change before eight seconds disables the short deadline even if the saved source returns')
    t.sample(44.9)
    check(not t.paused and t.clicks==1,'Previously changed source retains the existing 45-second deadline')
    t.sample(45.01)
    check(t.paused and t.clicks==1,'Changed-then-returned source eventually pauses without retry')
end
do
    local t=fixture();t.turn();t.sample(0);t.sample(7.9,'next');t.sample(8)
    check(not t.paused and t.prepared==0,'A newly changed source is not rejected at the eight-second deadline')
    t.sample(10)
    check(t.prepared==1 and t.clicks==1,'Late changing source can settle normally')
    t=fixture();t.env.phase='settle';t.env.job.expectChange=false;t.env.pageStarted=0
    t.sample(8,'initial')
    check(not t.paused,'Initial page capture is unaffected by the turn-only short deadline')
end

do
    local t=fixture();t.step(0)
    check(t.env.phase=='turn-focus' and t.moves==0 and t.clicks==0,
        'Focus preparation does not move/click the page target')
    t.focusWaiting=true;t.step(.05);t.step(1.999)
    check(not t.paused and t.focusSets==1 and t.clicks==0,'Focus polling waits without repeating focus assignment or clicking')
    t.env.due=0;t.step(2)
    check(t.paused and t.clicks==0 and not t.env.job.turnUncertain,'Focus timeout stops before click intent')
    check(t.env.turnTrace.outcome=='blocked-before-click' and t.env.turnTrace.bookFocus.error,
        'Focus timeout retains zero-click evidence')
    check(t.env.job.remaining==1 and #t.env.job.records==1,'Focus timeout retains the batch')
end
do
    local t=fixture();t.step(0);t.focusWaiting=true;t.step(.05)
    t.focusWaiting=false;t.env.due=0;t.step(.2)
    check(t.env.phase=='turn-hover' and t.moves==1 and t.clicks==0,'Verified delayed focus proceeds to hover without a wake-up click')
    check(t.env.turnTrace.bookFocus.sourceHashAfterFocus=='saved','Focus completion rechecks the saved source')
    t.step(.2);t.step(.55)
    check(t.clicks==1 and t.focusSets==1,'Delayed focus still results in exactly one page click')
end
for _,case in ipairs({
    {'prepare rejected',function(t)t.focusPrepareError='Focus not settable';t.step(0)end},
    {'source changed during focus',function(t)t.step(0);t.hash='different';t.step(.05)end},
    {'identity changed during focus',function(t)t.step(0);t.focusError='Book area changed';t.step(.05)end},
    {'focus lost during hover',function(t)t.hover();t.focusLost=true;t.click()end},
    {'identity changed during hover',function(t)t.hover();t.focusError='Area changed';t.click()end},
})do
    local t=fixture();case[2](t)
    check(t.paused and t.clicks==0 and not t.env.job.turnUncertain,case[1]..' fails before any turn')
    check(t.env.job.remaining==1 and #t.env.job.records==1,case[1]..' retains remaining batch')
    check(t.env.turnTrace.outcome=='blocked-before-click',case[1]..' persists blocked outcome')
end
do
    local t=fixture();t.step(0);t.env.running=false;t.step(.05)
    check(not t.focusChecks and t.moves==0 and t.clicks==0,'Pause cancels pending focus readback/hover/click')
    t=fixture();t.step(0);t.badWindow=true;t.step(.05)
    check(t.paused and not t.focusChecks and t.moves==0 and t.clicks==0,'Window change during focus wait stops before further actions')
end
print('PASS '..checks..' actual-code focus-phase, turn-guard, write-ahead, cancellation and deadline checks')
