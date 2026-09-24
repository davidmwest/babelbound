local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local S=require("gemini_book_source")
local function clone(x)
    if type(x)~="table" then return x end
    local y={};for k,v in pairs(x) do y[k]=clone(v) end;return y
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function fixture()
    local j={folder="/fixture",tag="test",remaining=8,lastSourceHash="original-hash",
        needAdvance=true,turnUncertain=false,records={}}
    for i=1,94 do j.records[i]={index=i,id="request-"..i,sourceHash="original-hash",first="first"..i,last="last"..i,text="translation"..i} end
    return j
end
local function reviewFor(j)
    return {status="ready",folder="/fixture/review",snapshot=S.snapshot(j),savedCount=#j.records,
        recordID=j.records[#j.records].id,oldHash=j.lastSourceHash,
        originalSourceHash=j.records[#j.records].sourceHash,candidateHash="new-hash"}
end
local function evidenceFor(r)
    return {savedCount=r.savedCount,recordID=r.recordID,oldHash=r.oldHash,
        candidateHash=r.candidateHash,reviewedBy="Codex",notes="Visually checked page 171 and every visible text column."}
end
do
    local j=fixture();local before=clone(j);local r=reviewFor(j);local e=evidenceFor(r)
    assert(S.apply(r,j,e,"new-hash","now"))
    assert(j.lastSourceHash=="new-hash" and equal(j.records,before.records))
    assert(j.remaining==8 and j.needAdvance and j.pending==nil and not j.turnUncertain)
    assert(j.navigationReference.originalSourceHash=="original-hash")
    for _,field in ipairs({"savedCount","recordID","oldHash","candidateHash","reviewedBy","notes"}) do
        local bad=clone(e);bad[field]=nil
        assert(S.approvalProblem(reviewFor(before),before,bad),field.." must be required")
    end
    local changed=fixture();local review=reviewFor(changed);local original=clone(changed)
    assert(not S.apply(review,changed,evidenceFor(review),"another-page","now"))
    assert(equal(changed,original),"changing source must leave the job untouched")
    changed.remaining=7
    assert(S.approvalProblem(review,changed,evidenceFor(review)),"changed progress must invalidate review")
    for _,mutation in ipairs({function(t)t.pending={id="pending"}end,
        function(t)t.turnUncertain=true end,function(t)t.needAdvance=false end}) do
        local t=fixture();mutation(t);assert(S.problem(t))
    end
end

-- Exercise the actual module with a virtual filesystem, screenshots and timers.
-- No Hammerspoon UI, real files, page turns or external requests are invoked.
local clock,queue,files,dirs,moves,clicks,captureCount=0,{}, {},{["/fixture"]=true},0,0,0
local hashes,hashIndex={"new-hash"},1
local jsonStore,jsonSerial={},0
local function encode(value) jsonSerial=jsonSerial+1;local key="json"..jsonSerial;jsonStore[key]=clone(value);return key end
local function decode(key) return clone(assert(jsonStore[key],key)) end
local function write(path,data) files[path]=data end
local function image(hash)
    local img={}
    function img:copy() return image(hash) end
    function img:size() return self end
    function img:encodeAsURLString() return hash end
    function img:saveToFile(path) write(path,"image:"..hash);return true end
    return img
end
local wf={x=0,y=0,w=2000,h=1200}
local cal={windowID=1,windowTitle="Book",windowFrame=wf,screenID=1,
    crop={x=0,y=0,w=1000,h=1000},input={x=1600,y=1100},panel={x=1500,y=100},next={x=10,y=500}}
local window={id=function()return 1 end,title=function()return "Book" end,
    frame=function()return wf end,focus=function()end}
local hs={configdir="/fixture",menubar={new=function()return nil end},
    settings={get=function(key)if key:match("calibration$")then return cal end end,set=function()end},
    timer={secondsSinceEpoch=function()return clock end,
        doAfter=function(delay,fn)queue[#queue+1]={at=clock+delay,fn=fn};return {}end,
        doEvery=function()return {}end},
    alert={show=function()return 1 end,closeAll=function()end,closeSpecific=function()end},
    fs={attributes=function(path)return files[path] and {mode="file"} or dirs[path] and {mode="directory"}end,
        mkdir=function(path)dirs[path]=true;return true end},
    json={encode=encode,decode=decode},hash={SHA256=function(v)return v end},
    application={frontmostApplication=function()return {bundleID=function()return "com.google.Chrome"end}end},
    window={frontmostWindow=function()return window end},screenRecordingState=function()return true end,
    screen={find=function()return {fullFrame=function()return {x=0,y=0}end,
        snapshot=function()captureCount=captureCount+1;local h=hashes[math.min(hashIndex,#hashes)];hashIndex=hashIndex+1;return image(h)end}end},
    mouse={absolutePosition=function()moves=moves+1 end},
    eventtap={isSecureInputEnabled=function()return false end,leftClick=function()clicks=clicks+1 end,
        event={types={mouseMoved=1},newMouseEvent=function()return {post=function()end}end}},
    pasteboard={readAllData=function()return {}end,changeCount=function()return 0 end,writeAllData=function()end},
    caffeinate={get=function()return false end,set=function()end},
    hotkey={bind=function()return {}end},dialog={blockAlert=function()error("Unexpected UI prompt")end}}
local virtualIO={open=function(path,mode)
    if mode=="rb" then
        if files[path]==nil then return nil,"missing" end
        return {read=function()return files[path]end,close=function()return true end}
    end
    local buffer=mode=="a" and files[path] or ""
    buffer=buffer or ""
    return {write=function(_,text)buffer=buffer..text;return true end,
        close=function()files[path]=buffer;return true end}
end}
local virtualOS={};for k,v in pairs(os)do virtualOS[k]=v end
virtualOS.rename=function(a,b)files[b]=files[a];files[a]=nil;return true end
local env=setmetatable({hs=hs,io=virtualIO,os=virtualOS,print=function()end},{__index=_G})
local M=assert(loadfile(paths.source("gemini_book.lua"),"t",env))()
M.config.illustrationsEnabled=false
local function upvalue(fn,name,value,set)
    for i=1,100 do local key,old=debug.getupvalue(fn,i);if not key then break end
        if key==name then if set then debug.setupvalue(fn,i,value) end;return old end
    end
    error("Missing upvalue "..name)
end
local function flush(max)
    for _=1,max or 100 do
        if #queue==0 then return end
        table.sort(queue,function(a,b)return a.at<b.at end)
        local next=table.remove(queue,1);clock=next.at;next.fn()
    end
    error("Timer queue did not settle")
end
local function setup(hash)
    M.stop();queue={};clock=0;hashes={hash or "new-hash"};hashIndex=1;captureCount=0
    local j=fixture();upvalue(M.runNextOne,"job",j,true)
    files["/fixture/sources/00094.png"]="original archive"
    files["/fixture/checkpoint.json"]=encode(j)
    return j
end
local function ready()
    assert(M.prepareSavedSourceReview());flush()
    local r=M.sourceState().review;assert(r.status=="ready");return r
end
do
    local j=setup();local records=clone(j.records);local r=ready()
    assert(captureCount>=3 and moves>0 and clicks==0)
    assert(M.approveSavedSourceReview(evidenceFor(r)));flush()
    assert(M.sourceState().review.status=="approved" and j.lastSourceHash=="new-hash")
    assert(equal(j.records,records) and files["/fixture/sources/00094.png"]=="original archive")
    assert(j.remaining==8 and clicks==0,"review cannot consume a screen or turn a page")
    local state=M.sourceState();state.review.candidateHash="tampered"
    assert(M.sourceState().review.candidateHash=="new-hash","diagnostics must be detached")
    assert(M.runNextOne());assert(j.remaining==8 and j.pauseAfterNext)
    flush();assert(M.sourceState().running and M.sourceState().phase=="saved")
    assert(j.remaining==8 and #j.records==94 and clicks==0)
    -- Drive the existing save boundary with the next validated response. The
    -- bounded-run flag must pause after this commit and preserve the batch.
    hashes={"next-hash"};hashIndex=1
    j.pending={index=95,id="request-95",sourceHash="next-hash",sent=true}
    local save=upvalue(M.acceptClipboard,"saveAnswer")
    save({raw="validated reply",first="first95",last="last95",text="next translation"},false)
    assert(#j.records==95 and j.remaining==7 and not M.sourceState().running)
    assert(j.pending==nil and j.pauseAfterNext==nil and j.navigationReference==nil)
    assert(j.lastSourceHash=="next-hash" and clicks==0)
end
do
    local j=setup();local r=ready();hashes={"another-page"};hashIndex=1
    assert(M.approveSavedSourceReview(evidenceFor(r)));flush()
    assert(j.lastSourceHash=="original-hash" and j.navigationReference==nil)
    assert(M.sourceState().review.status=="stopped" and clicks==0)
end
do
    local j=setup();local r=ready();M.stop()
    assert(not M.approveSavedSourceReview(evidenceFor(r)))
    assert(j.lastSourceHash=="original-hash")
end
do
    local j=setup();local r=ready();assert(M.approveSavedSourceReview(evidenceFor(r)))
    M.stop();flush();assert(j.lastSourceHash=="original-hash","Stop must cancel approval timers")
end
do
    local j=setup("original-hash");M.resume();M.resume();flush()
    assert(M.sourceState().running and captureCount<10,"duplicate resume must not create duplicate capture loops")
    M.stop();assert(not M.sourceState().running)
    M.resume();M.stop();flush();assert(not M.sourceState().running,"Stop must cancel pending resume")
end
do
    local j=setup("changed-page");M.resume();flush()
    assert(not M.sourceState().running and j.lastSourceHash=="original-hash" and clicks==0)
end
do
    local j=setup();hashes={};for i=1,100 do hashes[i]="moving-"..i end
    assert(M.prepareSavedSourceReview());flush()
    assert(M.sourceState().review.status=="stopped" and clock<=13)
    assert(j.lastSourceHash=="original-hash" and clicks==0,"unstable capture must fail within its time bound")
end
print("PASS: reviewed-source policy and actual-module recovery/resume integration")
