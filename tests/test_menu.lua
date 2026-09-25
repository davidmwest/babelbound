local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local menu=dofile(paths.source("gemini_book_menu.lua"))
local checks=0
local function eq(actual,expected,message)
    checks=checks+1
    assert(actual==expected,(message or "check")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function has(text,expected,message)
    checks=checks+1
    assert(type(text)=="string" and text:find(expected,1,true),(message or "text missing")..": "..expected)
end
local function snapshot(changes)
    local result={provider="gemini",providerName="Gemini",version="1.5.0",calibrated=true,
        running=false,checking=false,scheduled=false,phase="idle",model="Flash",
        job={bookTitle="The Lantern Archive — Vol. 01",folder="/books/Lantern",tag="test",
            records={{index=1,id="test-00001",sourceHash="saved"}},remaining=3,
            lastSourceHash="saved",needAdvance=true,pauseKind="paused"},
        outputs={html=true,epub=true,folder=true},epub={status="ready"}}
    for key,value in pairs(changes or {}) do result[key]=value end
    return result
end
local function itemFor(items,action)
    for _,item in ipairs(items)do
        if item.action==action then return item end
        if item.menu then local found=itemFor(item.menu,action);if found then return found end end
    end
end
local function group(items,title)
    for _,item in ipairs(items)do if item.title==title then return item end end
    error("No group: "..title)
end
local function primary(s,action,text)
    local item=menu.primary(s)
    eq(item.action,action,"primary action")
    if text then has(item.title,text,"primary label") end
    if action then eq(item.disabled,false,"primary is available") end
end
local function denied(s,action,text)
    local allowed,why=menu.allowed(s,action)
    eq(allowed,false,"blocked "..action)
    has(why,text or "first","reason for "..action)
end
local function pending(s,sent)
    s.job.needAdvance=false
    s.job.pending={index=2,id="test-00002",sourceHash="pending",sent=sent}
    return s
end

local s=snapshot()
primary(s,"resume",s.job.bookTitle)
local menuItems=menu.build(s)
eq(menuItems[1].title,s.job.bookTitle,"book first")
has(menuItems[2].title,"Flash (last observed)","model observation explicit")
has(menuItems[3].title,"Screen target: 4 (25%)","fixed target, not book progress")
for _,title in ipairs({"Read translation","Books","Setup","Advanced"})do eq(type(group(menuItems,title).menu),"table","stable group")end
local groups=0
for _,item in ipairs(menuItems)do if item.menu then groups=groups+1 end end
eq(groups,4,"exactly four top-level groups")
eq(menuItems[1].tooltip,s.job.bookTitle,"full book tooltip")

local noJob=snapshot();noJob.job=nil
primary(noJob,"newBook","Start translating")
denied(noJob,"rename","Open a book")
denied(noJob,"openReadingCopy","Open a book")
denied(noJob,"collectPending","Open a book")
denied(noJob,"rebuildReadingCopy","Save a translated screen")
eq(menu.allowed(noJob,"chooseSavedJob"),true,"can open saved books without loaded job")
noJob.calibrated=false
primary(noJob,"calibrate","Set up translator")
eq(menu.allowed(noJob,"restoreLatest"),true,"restore retains saved provider even without current calibration")
denied(noJob,"newBook","Calibrate")
denied(noJob,"preview","Calibrate")
primary(snapshot({calibrated=false}),"calibrate")

for _,phase in ipairs({"send","wait","turn","turn-release","copy-click","clipboard","preflight"})do
    local active=snapshot({running=true,phase=phase,warning="Old session warning",
        epub={status="failed",error="Disk full"}})
    primary(active,"pause")
    local items=menu.build(active)
    eq(items[3].title:find("Warning",1,true),nil,"execution precedes export/session warnings")
    has(itemFor(items,"openReadingCopy").title,"Pause and open","opening warns it pauses")
    eq(itemFor(items,"openReadingCopy").disabled,false,"reading output allowed during execution")
    has(itemFor(items,"details").title,"Pause and show details","details pause explicit")
    has(itemFor(items,"diagnostics").title,"Pause and inspect","diagnostics pause explicit")
    denied(active,"resume","Pause or stop")
    for _,action in ipairs({"newBook","chooseSavedJob","restoreLatest","providerGemini","providerChatgpt",
        "calibrate","calibrateNext","preview","rename","collectPending","resend","directPrompt",
        "scheduleResume","rebuildReadingCopy","rebuildEpub"})do denied(active,action,"Pause or stop") end
end
local checking=snapshot({checking=true,warning="Previous warning",epub={status="failed",error="Disk full"}})
local checkingMenu=menu.build(checking)
eq(menu.primary(checking).action,nil,"checking cannot trigger resume")
eq(menu.primary(checking).disabled,true,"checking primary disabled")
has(menu.primary(checking).title,"Checking","checking label")
eq(itemFor(checkingMenu,"stop").disabled,false,"stop exposed during checks")
local topStop=false
for _,item in ipairs(checkingMenu)do if item.action=="stop" then topStop=true end end
eq(topStop,true,"checking stop not buried in submenu")
denied(checking,"resume","Pause or stop")

local failed=snapshot({epub={status="failed",error="Disk full"},illustrationError="Image missing"})
primary(failed,"resume")
eq(itemFor(menu.build(failed),"rebuildEpub").title,"Retry EPUB export","EPUB recovery is independent")
eq(menu.allowed(failed,"rebuildEpub"),true,"EPUB repair needs no translation")
failed.job.remaining=0
primary(failed,"translateMore")
has(menu.build(failed)[3].title,"Batch complete","does not claim entire book finished")
denied(failed,"resume","Translate more")
failed.epubBusy=true
denied(failed,"rename","writers")
denied(failed,"rebuildEpub","writers")
failed.epubBusy=false;failed.illustrationBusy=true
denied(failed,"rename","writers")
denied(failed,"rebuildReadingCopy","writers")
for _,action in ipairs({"providerGemini","providerChatgpt"})do
    denied(failed,action,"reading copy writer")
    local item=itemFor(menu.build(failed),action)
    eq(item.disabled,true,"provider disabled while reading copy writer is active")
    has(item.tooltip,"before changing providers","provider writer gate explained in menu")
end
failed.illustrationBusy=false;failed.epubBusy=true
for _,action in ipairs({"providerGemini","providerChatgpt"})do
    eq(menu.allowed(failed,action),true,"EPUB writer alone does not block provider selection")
    eq(itemFor(menu.build(failed),action).disabled,false,"provider becomes available when reading copy writer finishes")
end

local warn=snapshot({warning="Provider is unavailable"})
primary(warn,"reviewProblem")
denied(warn,"resume","Review the problem")
denied(warn,"translateMore","Review the problem")
local longReason="Reader warning: "..string.rep("日本語é📚",30).."\n\nKeep this complete explanation in the tooltip."
local longWarning=snapshot({warning=longReason})
longWarning.job.bookTitle=string.rep("Book title 日本語 ",12)
local warningItems=menu.build(longWarning)
eq(utf8.len(warningItems[4].title),100,"warning truncates at a valid UTF-8 boundary")
eq(warningItems[4].title:sub(-#"…"),"…","long warning ends with ellipsis")
eq(warningItems[4].tooltip,longReason,"session warning tooltip retains full original paragraphs")
eq(warningItems[1].title,longWarning.job.bookTitle:gsub("%s+$",""),"long book title is not truncated")
longWarning.warning=nil;longWarning.job.pauseKind="warning";longWarning.job.pauseReason=longReason
eq(menu.build(longWarning)[4].tooltip,longReason,"saved warning tooltip retains full original paragraphs")
longWarning.job.pauseReason=string.rep("日",100)
eq(menu.build(longWarning)[4].title,longWarning.job.pauseReason,"100-character warning needs no ellipsis")
warn.warning=nil;warn.job.pauseKind="warning";warn.job.pauseReason="Turn check failed"
primary(warn,"reviewProblem")
warn.job.turnUncertain=true
primary(warn,"reviewPosition")
denied(warn,"resume","Review the page position")
denied(warn,"scheduleResume","page position")
denied(warn,"reviewSource","page turn")
local legacy=snapshot();legacy.job.pauseKind=nil;legacy.job.pauseReason="An old unclassified failure"
primary(legacy,"reviewProblem")
legacy.job.pauseReason="Paused. Gemini itself may still finish its reply."
primary(legacy,"resume")

local scheduled=snapshot({scheduled=true,warning="Quota reached"})
scheduled.job.autoResume={active=true,status="Armed for tomorrow at 10:00"}
primary(scheduled,"resume","Resume now")
eq(menu.allowed(scheduled,"cancelResume"),true,"scheduled cancellation")
local scheduledMenu=menu.build(scheduled)
has(scheduledMenu[3].title,"Resume scheduled","armed schedule not warning")
has(itemFor(scheduledMenu,"openEpub").title,"Cancel scheduled resume and open","focus change cancels timer")
for _,action in ipairs({"newBook","chooseSavedJob","providerGemini","calibrate","rename","directPrompt","translateMore"})do
    denied(scheduled,action,"Cancel the scheduled resume")
end
scheduled.scheduled=false
denied(scheduled,"cancelResume","No resume")
eq(itemFor(menu.build(scheduled),"cancelResume"),nil,"cancellation appears only while armed")
local chat=snapshot({provider="chatgpt",providerName="ChatGPT extension (experimental)"})
denied(chat,"scheduleResume","Gemini only")
eq(itemFor(menu.build(chat),"scheduleResume"),nil,"unsupported quota scheduler omitted")
eq(itemFor(menu.build(chat),"providerChatgpt").checked,true,"active provider checked")
eq(itemFor(menu.build(chat),"providerGemini").checked,false,"inactive provider unchecked")

local sent=pending(snapshot(),true)
primary(sent,"resume")
eq(menu.allowed(sent,"collectPending"),true,"sent reply collectable")
local pendingLine=false
for _,item in ipairs(menu.build(sent))do if item.title:find("will not be sent again",1,true) then pendingLine=true end end
eq(pendingLine,true,"pending collection explained")
denied(sent,"directPrompt","already sent")
denied(sent,"selectedSkill","already sent")
denied(sent,"collectPrior","Collect existing reply")
eq(menu.allowed(sent,"resend"),true,"explicit resend remains available")
eq(menu.allowed(sent,"clipboard"),true,"manual reviewed save remains available")
sent.job.turnUncertain=true
denied(sent,"collectPending","page position")
local unsent=pending(snapshot(),false)
eq(menu.allowed(unsent,"directPrompt"),true,"unsent source recovery")
eq(menu.allowed(unsent,"selectedSkill"),true,"Gemini skill compatibility")
denied(unsent,"collectPending","not been sent")
denied(unsent,"collectPrior","no earlier sent request")
unsent.job.pending.id="test-00002-r1234"
eq(menu.allowed(unsent,"collectPrior"),true,"legacy retry may inspect saved log")
unsent.job.pending.requestText="draft"
denied(unsent,"collectPrior","drafted retry")
unsent.job.pending.requestText=nil
unsent.provider="chatgpt"
denied(unsent,"selectedSkill","ChatGPT extension")
unsent.job.pending.sent=nil
denied(unsent,"directPrompt","send state is unknown")
unsent.job.pending.sent=false;unsent.job.pending.index=8
denied(unsent,"collectPending","does not follow")
unsent.job.pending.index=2;unsent.job.pending.sourceHash=""
denied(unsent,"clipboard","source reference")
unsent.job.pending.sourceHash="pending";unsent.job.remaining=0
denied(unsent,"resend","remaining screen count")

eq(menu.allowed(snapshot(),"reviewSource"),true,"saved-source review allowed only for saved reference")
local sourceMissing=snapshot();sourceMissing.job.lastSourceHash=nil
denied(sourceMissing,"reviewSource","incomplete")
local noOutput=snapshot({outputs={}})
for _,action in ipairs({"openReadingCopy","openEpub","openOutput"})do
    eq(itemFor(menu.build(noOutput),action).disabled,true,"missing output disabled")
    eq(type(itemFor(menu.build(noOutput),action).tooltip),"string","missing output reason visible")
end
denied(snapshot(),"unrecognized","Unknown")

-- Construction must remain passive even when the runtime has a loaded job.
-- Also ensure every leaf is data with its current handler gate represented.
local originalHs=_G.hs
_G.hs=setmetatable({}, {__index=function()error("Menu must not access Hammerspoon")end})
local before=snapshot();local job=before.job;local record=job.records[1]
local function inspect(items,snap)
    for _,item in ipairs(items)do
        for _,value in pairs(item)do eq(type(value)=="function",false,"no callbacks in policy output")end
        if item.action then eq(item.disabled,not menu.allowed(snap,item.action),"menu and guard agree: "..item.action)end
        if item.menu then inspect(item.menu,snap)end
    end
end
inspect(menu.build(before),before)
eq(before.job,job,"job reference retained")
eq(job.records[1],record,"record reference retained")
eq(job.remaining,3,"count not mutated")
eq(job.pauseKind,"paused","pause state not mutated")
eq(before.running,false,"execution not mutated")
_G.hs=originalHs
print("Menu and action policy: "..checks.." checks passed")
