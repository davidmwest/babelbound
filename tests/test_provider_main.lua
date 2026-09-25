local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
-- Actual-main integration with synthetic settings, AX elements and an in-memory
-- filesystem. No native input, timers, screen capture or live job writes.
local f=assert(io.open(paths.source("gemini_book.lua")));local source=f:read("*a");f:close()
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function eq(a,b,message)check(a==b,message..": expected "..tostring(b)..", got "..tostring(a))end
local function clone(value)
    if type(value)~="table"then return value end
    local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
end
local key="GeminiBookMac.v1"
local extensionURL="chrome-extension://hehggadaopoacecdllhhajmbjkdcmajg/codex-sidepanel/index.html"
local frame={x=0,y=0,w=1200,h=900}
local function calibration(provider)
    return {provider=provider,windowID=77,windowTitle="Synthetic Book - Reader",windowFrame=clone(frame),
        screenID=9,input={x=1000,y=800},next={x=350,y=450},crop={x=100,y=100,w=600,h=600},panel={x=800,y=80}}
end
local s={settings={},files={},dirs={},writes={},messages={},timers={},time=100,focuses=0}
s.settings[key..".calibration"]=calibration(nil) -- pre-provider legacy calibration
s.settings[key..".calibration.chatgpt"]=calibration("chatgpt")
local function element(values,pid)
    return {attributeValue=function(_,name)return values[name]end,pid=function()return pid or 7 end}
end
local screen={id=function()return 9 end,fullFrame=function()return {x=0,y=0,w=2000,h=1200}end}
local window={id=function()return 77 end,title=function()return "Synthetic Book - Reader"end,
    frame=function()return clone(frame)end,screen=function()return screen end,focus=function()s.focuses=s.focuses+1 end}
local function noInput()error("Provider metadata tests must not generate native input")end
local function attributes(path)
    return s.dirs[path] and {mode="directory"} or s.files[path]~=nil and {mode="file"} or nil
end
local hs={configdir="/fixture/config",settings={get=function(k)return clone(s.settings[k])end,
    set=function(k,v)s.settings[k]=clone(v)end},
    menubar={new=function()return {setTitle=function(_,v)s.menuTitle=v end,setTooltip=function(_,v)s.tooltip=v end,
        setMenu=function()end}end},hotkey={bind=function()return {}end},
    timer={secondsSinceEpoch=function()return s.time end,doEvery=function()return {stop=function()end}end,
        doAfter=function(_,fn)s.timers[#s.timers+1]=fn;return {stop=function()end}end},
    json={encode=clone,decode=clone},alert={show=function(text)s.messages[#s.messages+1]=text;return #s.messages end,
        closeSpecific=function()end,closeAll=function()end},
    application={frontmostApplication=function()return {bundleID=function()return "com.google.Chrome"end}end},
    window={frontmostWindow=function()return window end},screen={find=function()return screen end},
    accessibilityState=function()return true end,screenRecordingState=function()return true end,
    mouse={absolutePosition=function(value)assert(value==nil,"No pointer movement expected");return clone(s.pointer)end},
    eventtap={leftClick=noInput,keyStroke=noInput,isSecureInputEnabled=function()return false end},
    axuielement={systemWideElement=function()return {elementAtPosition=function()return s.seed end}end},
    fs={attributes=attributes,symlinkAttributes=attributes,mkdir=function(path)
        if attributes(path)then return false,"exists"end;s.dirs[path]=true;return true
    end,dir=function(root)
        local names={};for path in pairs(s.dirs)do
            if path:sub(1,#root+1)==root.."/"then
                local name=path:sub(#root+2);if not name:find("/",1,true)then names[#names+1]=name end
            end
        end
        table.sort(names);local i=0;return function()i=i+1;return names[i]end
    end},host={uuid=function()return "12345678-1234-1234-1234-123456789abc"end},
    pasteboard={changeCount=function()return 0 end},caffeinate={set=function()end},
    dialog={textPrompt=function()error("Explicit test parameters must avoid prompts")end},
    task={new=function()error("No subprocess expected")end}}
local modules={}
local function requireModule(name)
    if not modules[name]then modules[name]=dofile(paths.source(name..".lua"))end
    return modules[name]
end
local env=setmetatable({hs=hs,_S=s,_CLONE=clone,print=function()end,require=requireModule},{__index=_G})
local injection=[[
atomicWrite=function(path,value)_S.files[path]=_CLONE(value);_S.writes[#_S.writes+1]=path end
readFile=function(path)return _CLONE(_S.files[path])end
log=function()end
mkdir=function(path)_S.dirs[path]=true end
pendingSourceStillVisible=function()return true end
M.config.outputRoot='/fixture/jobs';M.config.illustrationsEnabled=false;M.config.epubEnabled=false
M._test={
    guard=guard,prepare=preparePage,save=saveAnswer,resume=resumeNow,
    set=function(value)
        provider=value.provider or 'gemini';job=value.job;cal=_CLONE(value.cal)
        running=value.running or false;phase=value.phase or 'restored';epoch=40
        recoveryActive=value.recovery or false;resumeCaptureEpoch=value.resuming and epoch or nil
        illustrationTask=value.illustrating and {} or nil;illustrationBuild={status='idle'}
        calibrationStep=nil;calibrationDraft=nil;nextCalibration=nil;sessionWarning=nil
        scan=nil;scanPending=false;verifiedInput=nil;lastModelReadback=nil;turnTrace=nil
        clipboardBackup=nil;clipboardOwnedCount=nil;sleepBackup=nil
    end,
    state=function()return {provider=provider,job=job,cal=cal,running=running,phase=phase,
        epoch=epoch,calibrationStep=calibrationStep,calibrationDraft=calibrationDraft,nextCalibration=nextCalibration}end,
    defer=function(fn)defer(0.1,fn)end,
    models=pageModels
}
return M
]]
local transformed,n=source:gsub("return M%s*$",injection);assert(n==1)
local M=assert(load(transformed,"actual main provider memory harness","t",env))()
local T=M._test
local function sidebar(url)
    local web=element({AXRole="AXWebArea",AXURL=url})
    s.seed=element({AXRole="AXTextArea",AXParent=web})
end
local function job(provider,name)
    return {folder="/fixture/jobs/Book-"..(name or "Fixture"),bookTitle=name or "Fixture",provider=provider,
        tag="fixture",records={{index=1,id="fixture-00001",first="Opening",last="Ending",text="Synthetic text."}},
        remaining=3,requestMode="inline",pending={index=2,id="fixture-00002",sourceHash="source-two",sent=true,provider=provider}}
end
local function putJob(j)s.dirs[j.folder]=true;s.files[j.folder.."/checkpoint.json"]=clone(j)end
local function reset(provider,j)
    s.files={};s.dirs={};s.writes={};s.timers={};s.messages={};s.focuses=0
    s.settings[key..".latest"]="/fixture/jobs/Book-Gemini"
    s.settings[key..".latest.chatgpt"]="/fixture/jobs/Book-ChatGPT"
    T.set({provider=provider or "gemini",job=j,cal=calibration(provider)})
    sidebar(provider=="chatgpt" and extensionURL or "https://gemini.google.com/")
end
eq(M.currentProvider(),"gemini","legacy installation defaults to Gemini")
eq(T.state().cal.provider,nil,"legacy calibration is loaded without migration")

-- Switching is a checkpoint-preserving selection, never a conversion or resume.
do
    local old=job(nil,"Gemini");reset("gemini",old)
    local callbackRan=false;T.defer(function()callbackRan=true end)
    eq(M.selectProvider("chatgpt"),true,"paused job allows provider switch")
    local state=T.state();eq(state.provider,"chatgpt","active provider changes")
    eq(state.job,nil,"old job is unloaded");eq(state.cal.provider,"chatgpt","loads ChatGPT calibration")
    eq(s.settings[key..".provider"],"chatgpt","selection persists")
    eq(s.settings[key..".latest"],old.folder,"Gemini pointer stays intact")
    eq(s.settings[key..".latest.chatgpt"],"/fixture/jobs/Book-ChatGPT","ChatGPT pointer stays intact")
    local saved=s.files[old.folder.."/checkpoint.json"]
    eq(saved.pending.id,"fixture-00002","pending ID survives switch")
    eq(saved.pending.sent,true,"sent state survives switch");eq(saved.provider,nil,"legacy job is not converted")
    s.timers[1]();eq(callbackRan,false,"callbacks from old provider are cancelled")
    local before=#s.writes;eq(M.selectProvider("chatgpt"),true,"same provider is harmless")
    eq(#s.writes,before,"same provider does not rewrite job")
    eq(M.selectProvider("unsupported"),nil,"unknown provider is rejected")
    eq(M.currentProvider(),"chatgpt","unknown provider leaves selection intact")
    eq(M.selectProvider("gemini"),true,"switching back works")
    eq(T.state().cal.provider,nil,"switching back restores legacy Gemini calibration")
end
for _,active in ipairs({"running","recovery","resuming","illustrating"})do
    local j=job("gemini");reset("gemini",j)
    local state={provider="gemini",job=j,cal=calibration("gemini")};state[active]=true;T.set(state)
    eq(M.selectProvider("chatgpt"),false,active.." operation prevents switching")
    eq(M.currentProvider(),"gemini",active.." retains provider")
    eq(T.state().job,j,active.." retains job");eq(#s.writes,0,active.." does not checkpoint partial conversion")
end

-- Five-point calibration writes only the selected provider's key.
do
    reset("chatgpt");local gemini=clone(s.settings[key..".calibration"])
    M.calibrate();eq(T.state().calibrationDraft.provider,"chatgpt","draft remembers provider")
    for _,point in ipairs({{x=1000,y=800},{x=350,y=450},{x=100,y=100},{x=700,y=700},{x=800,y=80}})do
        s.pointer=point;M.calibrate()
    end
    local saved=s.settings[key..".calibration.chatgpt"]
    eq(saved.provider,"chatgpt","completed calibration is tagged")
    eq(saved.crop.w,600,"source geometry preserved");eq(T.state().calibrationStep,nil,"calibration finishes")
    eq(s.settings[key..".calibration"].provider,gemini.provider,"Gemini calibration remains legacy")
    eq(s.settings[key..".calibration"].input.x,gemini.input.x,"Gemini input unchanged")
    M.calibrate();eq(T.state().calibrationStep,1,"new draft begins")
    M.selectProvider("gemini");eq(T.state().calibrationStep,nil,"provider switch clears unfinished calibration")
    M.calibrate();eq(T.state().calibrationDraft.provider,"gemini","fresh calibration belongs to new provider")
end

-- The real guard checks job/pending/calibration ownership AND the input's URL.
for _,provider in ipairs({"gemini","chatgpt"})do
    local j=job(provider);reset(provider,j)
    eq(T.guard(),window,provider.." valid context passes")
    sidebar(provider=="chatgpt" and "https://gemini.google.com/" or extensionURL)
    eq(T.guard(),nil,provider.." rejects opposite sidebar")
    sidebar(nil)
    if provider=="chatgpt"then eq(T.guard(),nil,"ChatGPT requires positive extension URL evidence")end
    sidebar(provider=="chatgpt" and extensionURL or "https://gemini.google.com/")
    local opposite=provider=="chatgpt" and "gemini" or "chatgpt"
    for _,mismatch in ipairs({"job","pending","calibration"})do
        local value=clone(j);local cal=calibration(provider)
        if mismatch=="job"then value.provider=opposite elseif mismatch=="pending"then value.pending.provider=opposite else cal.provider=opposite end
        T.set({provider=provider,job=value,cal=cal})
        eq(T.guard(),nil,provider.." rejects mismatched "..mismatch)
        T.resume(true);eq(T.state().running,false,mismatch.." cannot start")
        eq(value.pending.sent,true,mismatch.." preserves sent state")
        eq(value.pending.id,"fixture-00002",mismatch.." preserves request ID")
    end
end

-- Explicit restore changes selection only after validating the full checkpoint.
for _,provider in ipairs({"gemini","chatgpt"})do
    local opposite=provider=="chatgpt" and "gemini" or "chatgpt"
    reset(opposite,job(opposite,"Current"))
    local saved=job(provider,"Restored")
    if provider=="gemini"then saved.provider=nil;saved.pending.provider=nil end
    saved.requestMode=nil;saved.autoResume={active=true};putJob(saved)
    local before=#s.writes
    eq(M.restoreFolder(saved.folder),true,provider.." valid saved job restores")
    local state=T.state();eq(state.provider,provider,"restore selects checkpoint provider")
    eq(state.job.provider,provider,"restore gives legacy job explicit identity")
    eq(state.cal.provider,provider=="chatgpt" and "chatgpt" or nil,"restore loads matching calibration")
    eq(state.job.pending.id,saved.pending.id,"restore retains pending ID")
    eq(state.job.pending.sent,true,"restore retains sent state")
    eq(state.job.autoResume.active,false,"restore does not rearm timer")
    eq(state.running,false,"restore stays paused");eq(state.phase,"restored","restore requests position review")
    eq(#s.writes,before,"restore does not rewrite checkpoint or translation")
    eq(#s.timers,0,"restore schedules no request or page turn")
    local suffix=provider=="chatgpt" and ".chatgpt" or ""
    eq(s.settings[key..".latest"..suffix],saved.folder,"restore updates matching pointer")
end
for _,variant in ipairs({"unknown-provider","wrong-pending","untagged-chatgpt-pending","wrong-prior","skill-mode"})do
    local current=job("gemini","Current");reset("gemini",current)
    local invalid=job("chatgpt","Invalid")
    if variant=="unknown-provider"then invalid.provider="unsupported"
    elseif variant=="wrong-pending"then invalid.pending.provider="gemini"
    elseif variant=="wrong-prior"then invalid.priorSentReply={provider="gemini"}
    elseif variant=="skill-mode"then invalid.requestMode="skill"
    else invalid.pending.provider=nil end
    putJob(invalid);eq(M.restoreFolder(invalid.folder),false,variant.." restore rejected")
    eq(T.state().job,current,variant.." preserves loaded job")
    eq(M.currentProvider(),"gemini",variant.." preserves provider")
    eq(s.settings[key..".latest.chatgpt"],"/fixture/jobs/Book-ChatGPT",variant.." preserves pointer")
end

-- Restoring a job can implicitly switch providers just like the selector. A
-- partial calibration or armed forward-point capture must not cross that seam.
for _,draftKind in ipairs({"full-calibration","forward-point"})do
    reset("gemini")
    if draftKind=="full-calibration"then
        M.calibrate();s.pointer={x=1000,y=800};M.calibrate()
        eq(T.state().calibrationStep,2,"Gemini input captured in unfinished calibration")
        eq(T.state().calibrationDraft.provider,"gemini","unfinished calibration belongs to Gemini")
    else
        M.calibrateNext();eq(T.state().nextCalibration,true,"Gemini forward-point capture armed")
    end
    local saved=job("chatgpt","RestoredDuringCalibration");putJob(saved)
    eq(M.restoreFolder(saved.folder),true,"restore works during "..draftKind)
    eq(T.state().calibrationStep,nil,"restore clears old calibration step after "..draftKind)
    eq(T.state().calibrationDraft,nil,"restore clears old calibration draft after "..draftKind)
    eq(T.state().nextCalibration,nil,"restore clears old forward-point capture after "..draftKind)
    eq(s.settings[key..".calibration.chatgpt"].provider,"chatgpt","restore preserves ChatGPT calibration")
    if draftKind=="full-calibration"then
        M.calibrate()
        eq(T.state().calibrationStep,1,"next shortcut starts a fresh calibration")
        eq(T.state().calibrationDraft.provider,"chatgpt","new draft belongs to restored provider")
    else
        sidebar(extensionURL);s.pointer={x=450,y=400};M.calibrateNext()
        eq(T.state().nextCalibration,true,"next shortcut arms rather than captures an old request")
        eq(s.settings[key..".calibration.chatgpt"].next.x,350,"no forward point overwritten before second shortcut")
    end
end

-- The folder-based rename API may target another provider's saved job. Its
-- transactional mover is tested separately; exercise the actual pointer repair.
do
    reset("gemini",job("gemini","Current"))
    local saved=job("chatgpt","ChatGPT");putJob(saved)
    local renamed=clone(saved);renamed.folder="/fixture/jobs/Book-Renamed"
    local mover=requireModule("gemini_book_rename");local original=mover.rename
    mover.rename=function(folder,title)
        eq(folder,saved.folder,"rename delegates requested folder")
        eq(title,"Renamed","rename delegates requested title")
        return {folder=renamed.folder,title="Renamed",job=renamed}
    end
    check(M.renameJob("Renamed",saved.folder)~=nil,"other-provider rename succeeds")
    eq(s.settings[key..".latest.chatgpt"],renamed.folder,"rename repairs checkpoint provider's pointer")
    eq(s.settings[key..".latest"],"/fixture/jobs/Book-Gemini","rename preserves active provider pointer")
    eq(M.currentProvider(),"gemini","rename does not switch provider")
    eq(T.state().job.folder,"/fixture/jobs/Book-Current","rename preserves loaded book")
    mover.rename=original
end

-- Discovery never treats another provider's populated job as the latest job.
do
    reset("chatgpt");putJob(job(nil,"Only-Gemini"))
    eq(M.restoreLatest(),false,"ChatGPT does not adopt lone legacy Gemini job")
    eq(T.state().job,nil,"failed discovery leaves no job")
    local matching=job("chatgpt","Matching");putJob(matching)
    eq(M.restoreLatest(),true,"discovery finds matching provider")
    eq(T.state().job.folder,matching.folder,"matching job selected despite stale pointer")
    reset("gemini");putJob(job("chatgpt","Other"));putJob(job(nil,"Legacy"))
    eq(M.restoreLatest(),true,"Gemini discovers legacy job")
    eq(T.state().job.folder,"/fixture/jobs/Book-Legacy","legacy job remains Gemini")
end

-- A new ChatGPT job always uses inline instructions and carries ownership into
-- pending, committed records and the searchable page metadata index.
do
    reset("chatgpt");M.config.defaultRequestMode="skill"
    M.newJob(3,"Synthetic ChatGPT Book")
    local j=T.state().job;check(j~=nil,"new ChatGPT job created")
    eq(j.provider,"chatgpt","job is provider-tagged");eq(j.requestMode,"inline","ChatGPT cannot inherit skill default")
    eq(j.remaining,3,"batch count preserved");eq(#s.timers,1,"new job schedules one guarded resume")
    eq(s.settings[key..".latest.chatgpt"],j.folder,"new job updates ChatGPT pointer")
    T.prepare({saveToFile=function(_,path) s.files[path]="synthetic PNG fixture";return true end},"new-source")
    eq(j.pending.provider,"chatgpt","pending request records provider")
    eq(s.files[j.folder.."/checkpoint.json"].pending.provider,"chatgpt","pending ownership is durable")
    j.pending.sent=true
    local id=j.pending.id
    T.models.atSubmit(j.pending,"6 Astra Medium",{pendingID=id,phase="submit-check",scanStatus="completed",model="6 Astra Medium"})
    T.save({first="Synthetic opening",last="Synthetic ending",text="A wholly invented demonstration paragraph.",raw="fixture response"},false)
    eq(j.records[1].provider,"chatgpt","committed page records provider")
    eq(j.records[1].modelProvenance.provider,"chatgpt","model observation records provider")
    eq(s.files[j.folder.."/page-metadata.json"].records[1].provider,"chatgpt","searchable metadata records provider")
    eq(j.pending,nil,"save clears only committed pending request");eq(j.remaining,2,"one save consumes one screen")
    local items=M.menuItems();local skill
    for _,item in ipairs(items)do if item.title=="Continue with manually selected ln skill"then skill=item end end
    eq(skill.disabled,true,"ChatGPT menu disables Gemini skill flow")
    M.config.defaultRequestMode="inline"
end

-- Existing prepared prompts survive the neutral wording change; ownership still
-- demands the same request ID and full normalized editor equality.
do
    local core=requireModule("gemini_book_core")
    local id="synthetic-00001";local instructions=string.rep("Use the current visible source only. ",5)
    local old=instructions.."\n\nCURRENT AUTOMATED REQUEST\n"..core.requestText(id)
    local current=core.inlineRequestText(id,instructions)
    eq(core.isPreparedInlineRequest(old,id),true,"legacy inline suffix remains resumable")
    eq(core.isPreparedInlineRequest(current,id),true,"new neutral suffix is resumable")
    eq(core.isPreparedInlineRequest(old,"other-00001"),false,"legacy wrong ID rejected")
    eq(core.isPreparedInlineRequest(current.." extra",id),false,"trailing foreign text rejected")
    eq(core.requestDraftMatches(old,old,""),true,"legacy complete owned draft matches")
    eq(core.requestDraftMatches(old..old,old,""),false,"duplicate legacy draft rejected")
    eq(core.requestDraftMatches(old:sub(1,80),old,""),false,"partial legacy draft rejected")
end

-- An expanded ChatGPT composer has a bare named popup in its bottom toolbar.
-- This exception must not admit response text, draft text, menus or other panes.
do
    local ax=requireModule("gemini_book_ax");local providers=requireModule("gemini_book_provider")
    local limits=requireModule("gemini_book_limits");local cal=calibration("chatgpt")
    local panel=element({AXRole="AXWebArea",AXFrame={x=800,y=80,w=400,h=820}})
    local function control(parent,role,pid)
        return element({AXRole=role or "AXPopUpButton",AXTitle="6 Astra Medium",AXParent=parent,
            AXFrame={x=1040,y=830,w=135,h=28}},pid)
    end
    local function read(e,named,currentPanel)
        return ax.readModelControl(e,{cal=cal,panel=currentPanel or panel,composer=nil,namedPicker=named,
            parseLabel=function(value)return providers.modelLabel("chatgpt",value)end,normalize=limits.normalize})
    end
    check(read(control(panel),true)~=nil,"expanded composer named popup accepted")
    eq(read(control(panel),false),nil,"Gemini retains explicit caption requirement")
    eq(read(control(panel,"AXStaticText"),true),nil,"response model-name text rejected")
    eq(read(control(panel,"AXButton"),true),nil,"generic response button rejected")
    for _,role in ipairs({"AXTextArea","AXMenu","AXMenuItem","AXListBox"})do
        local parent=element({AXRole=role,AXParent=panel})
        eq(read(control(parent),true),nil,role.." ancestry rejected")
    end
    local other=element({AXRole="AXWebArea",AXFrame={x=800,y=80,w=400,h=820}})
    eq(read(control(other),true),nil,"different sidebar ancestry rejected")
    eq(read(control(panel,nil,999),true),nil,"different process rejected")
    local unknown=element({AXRole="AXPopUpButton",AXTitle="A story about Astra",AXParent=panel,
        AXFrame={x=1040,y=830,w=135,h=28}})
    eq(read(unknown,true),nil,"strict model parser still rejects incidental prose")
end
print("Provider integration: "..checks.." actual-source checks passed")
