-- Babelbound, v1.5.0 (Gemini and ChatGPT side panels) — Hammerspoon / macOS / Chrome sidebar. No API or network code.
-- Load with: GeminiBook = require("gemini_book")
-- UI integration MUST be tested on your Chrome build before a long run.
local core = require("gemini_book_core")
local skillUI = require("gemini_book_skill")
local scopedAX = require("gemini_book_ax")
local limits = require("gemini_book_limits")
local resetClock = require("gemini_book_resume")
local savedJobs = require("gemini_book_jobs")
local jobNames = require("gemini_book_names")
local jobRename = require("gemini_book_rename")
local jobStatus = require("gemini_book_status")
local epubExport = require("gemini_book_epub")
local priorReply = require("gemini_book_prior_reply")
local sourcePolicy = require("gemini_book_source")
local bookFocus = require("gemini_book_focus")
local providers = require("gemini_book_provider")
local turnFocus
local quota = {}
local M = {version="1.5.0"}

-- User-adjustable defaults. Screen coordinates are calibrated, not hard-coded.
M.config = {
    provider = "gemini", -- Gemini or the official ChatGPT Chrome side panel.
    skill = "/ln",
    defaultRequestMode = "inline", -- New/legacy jobs use the working direct prompt; skill is explicit opt-in.
    usageLimitDetection = true,
    offerAutoResume = false, -- Pause-only by default. Manual scheduling remains explicitly opt-in.
    usageResumeBufferSeconds = 60, -- One minute after the stated reset, not before it.
    usageResumeMaxLateSeconds = 600, -- A slept/locked Mac does not resume hours later.
    completedReplyAfterLimitSeconds = 60, -- Bounded collection of an already-sent reply on any model.
    limitPhrasesFile = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon"))
        .. "/gemini_book_limit_phrases.txt",
    -- Exact English hint visible in this Chrome/Gemini setup. Used ONLY after
    -- the editor's focus, process and composer location have been verified.
    inputPlaceholders = {"Type @ to add tabs", "Type / to use skills"},
    -- No Return is used to select a skill. It is reserved for verified submission.
    skillMenuTimeout = 18,
    focusTimeout = 5,             -- Bounded, asynchronous focus retries; never blind typing.
    focusPollSeconds = 0.05,
    skillMenuDelay = 0.8,          -- First poll, not a declaration that a menu is ready.
    skillSelectDelay = 0.5,
    inputReadbackTimeout = 15,     -- Bounded async wait for actual editor CONTENT, not a blind sleep.
    inputReadbackStableSeconds = 0.15, -- Exact complete draft is rechecked again immediately before Send.
    inputReadbackPollSeconds = 0.05,
    pollSeconds = 1/3,           -- Lightweight readiness checks target three starts per second.
    readinessProbeTimeout = 0.75,
    readinessProbeMaxNodes = 512,
    responseTimeout = 300,        -- Timeout PAUSES. It never means "finished".
    copyTimeout = 10,             -- Wait for asynchronous clipboard data; never assume AXPress succeeded.
    copyNoChangeTimeout = 2,      -- Retry a no-op Copy sooner; changed ownership retains the full data wait.
    copyHoverSeconds = 0.05,      -- Live target is revalidated after pointer delivery, before each click.
    copyClickHoldUS = 80000,
    maxCopyAttempts = 8,          -- Per collection attempt, NOT a silent loop until timeout.
    maxResponseScrolls = 3,       -- Only the right-hand response pane; never the book.
    responseScrollSettle = 1.25,
    stableResponseSeconds = 1,
    pageMinimumWait = 2,         -- The independent two-second continuous hash stability check still applies.
    pageStableSeconds = 2,
    pageChangeTimeout = 45,
    pageUnchangedTimeout = 8,    -- A never-changing turn pauses early; never clicks again automatically.
    turnFocusTimeout = 2,        -- Direct AX focus and readback; no wake-up page click.
    turnFocusPollSeconds = 0.05,
    turnHoverSeconds = 0.35,      -- Small delivery margin after a dropped click at 0.1s; still ONE click.
    turnClickHoldUS = 80000,
    postTurnDelay = 0.15,
    detailedTurnScreenshots = false, -- Saved source plus failure capture normally suffice; opt in for hover debugging.
    modelReadbackAttempts = 3,    -- Fresh sidebar reads, not request retries. Model labels are diagnostic.
    modelReadbackRetryDelay = 2,  -- Read-only wait; Stop/pause cancels the pending check.
    axSearchTimeout = 15,
    axMaxNodes = 6000,            -- Skill/composer scans keep the original bounds.
    axControlMaxNodes = 24000,    -- Finite fallback budget for long sidebar conversations.
    axControlTimeout = 45,       -- Child scans yield asynchronously and remain cancellable.
    promptFile = hs.configdir and (hs.configdir .. "/gemini_book_prompt.txt")
        or (os.getenv("HOME") .. "/.hammerspoon/gemini_book_prompt.txt"),
    betweenPages = 0.5,
    defaultBatch = 3,
    chromeBundle = "com.google.Chrome",
    outputRoot = os.getenv("HOME") .. "/Documents/GeminiBookTranslations",
    jobMoveScript = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/gemini_book_move.py",
    illustrationsEnabled = true,
    epubEnabled = true,
    epubScript = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/gemini_book_epub.py",
    illustrationPython = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/.bt-venv/bin/python3",
    illustrationScript = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/gemini_book_illustrations.py",
}
-- Set GeminiBookConfig in init.lua BEFORE require("gemini_book"). This also
-- configures helpers whose runtime paths are captured during initialization.
local overrides = rawget(_G, "GeminiBookConfig")
if overrides ~= nil then
    assert(type(overrides) == "table", "GeminiBookConfig must be a table")
    for key, value in pairs(overrides) do
        assert(M.config[key] ~= nil, "Unknown GeminiBookConfig option: " .. tostring(key))
        M.config[key] = value
    end
end
local cfg = M.config
local mods = {"ctrl", "alt", "cmd"}
local settingKey = "GeminiBookMac.v1"
local provider = providers.id(hs.settings.get(settingKey .. ".provider") or cfg.provider)
assert(provider, "Unknown translation provider")
local function providerKey(suffix)
    return settingKey .. suffix .. (provider == "gemini" and "" or "." .. provider)
end
local function providerName() return providers.get(provider).name end
local function inputHints()
    return provider == "gemini" and cfg.inputPlaceholders or providers.get(provider).placeholders
end
local function modelLabel(value) return providers.modelLabel(provider, value) end
local cal = hs.settings.get(providerKey(".calibration"))
local job, running, phase, due = nil, false, "idle", 0
local scan, scanStarted, epoch = nil, 0, 0
local scanKind, scanRootDescription
local lastModelReadback
local calibrationStep, calibrationDraft = nil, nil
local clipboardBackup, clipboardOwnedCount, sleepBackup
local responseCandidate, responseSince, pageCandidate, pageSince, pageStarted
local copyBefore, copyStarted, scanPending = nil, nil, false
local collection, responseScrollPoint, copyTarget, copyClipboardState
local menu = hs.menubar.new()
local tick, pause, scanButtons, saveAnswer, checkpoint
local rebuildIllustrations
local epubManager, requestEpub, flushEpubs
local illustrationTask, illustrationQueued
local illustrationBuild = {status="idle"}
local timer
local resumeNow
local stableSourceCapture, savedSourceReview, resumeCaptureEpoch
local inputWaitPhase, inputWaitStarted, inputReclicked
local verifiedInput
local inputReadback
local pasteInFlight = false
local skillFlow
local scanSkillItems
local turnTrace, nextCalibration
local noticeID
local recoveryActive = false
local lastNotice = hs.settings.get(settingKey .. ".lastNotice")

local sessionWarning
local function uiState()
    local view=jobStatus.view(job,{running=running,phase=phase,recoveryActive=recoveryActive,
        resuming=resumeCaptureEpoch~=nil and resumeCaptureEpoch==epoch,
        illustrationBuild=illustrationBuild,epubBuild=epubManager and job and epubManager:state(job.folder),warning=sessionWarning})
    view.provider=provider
    view.tooltip=view.tooltip.."\nProvider: "..providerName()
    return view
end
local function refreshMenu()
    local view=uiState()
    if menu then menu:setTitle(view.menuTitle);menu:setTooltip(view.tooltip)end
    return view
end
local function now() return hs.timer.secondsSinceEpoch() end
local function wrapNotice(s)
    local out={}
    for line in (tostring(s).."\n"):gmatch("([^\n]*)\n") do
        local row=""
        for word in line:gmatch("%S+") do
            if #row+#word+1>84 and row~="" then out[#out+1]=row; row="" end
            row=row=="" and word or row.." "..word
        end
        out[#out+1]=row
    end
    return table.concat(out,"\n")
end
local function dismissNotice()
    if noticeID then hs.alert.closeSpecific(noticeID,0); noticeID=nil end
end
local function alert(s)
    hs.alert.show("Babelbound: "..wrapNotice(s),12)
end
local function persistentNotice(s, remember)
    dismissNotice()
    if remember then
        lastNotice={text=s,at=os.date("%Y-%m-%d %H:%M:%S"),atEpoch=now(),
            folder=job and job.folder,phase=phase,version=M.version}
        hs.settings.set(settingKey..".lastNotice",lastNotice)
    end
    noticeID=hs.alert.show("Babelbound\n\n"..wrapNotice(s)
        .."\n\nDismiss: Control-Option-Command-D or BT > Dismiss message"
        .."\nDismissing does NOT resume automation.",
        {textSize=19,fadeInDuration=0,fadeOutDuration=0},"until-dismissed")
end
-- An unsuccessful UI action is visible without marking an unrelated loaded
-- book as failed (for example, an attempted restore of a missing checkpoint).
local function warningNotice(reason)
    sessionWarning=reason;refreshMenu();persistentNotice(reason,true)
end
local function exists(p) return hs.fs.attributes(p) ~= nil end
local function mkdir(p)
    if exists(p) then return end
    local parent = p:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not exists(parent) then mkdir(parent) end
    local ok, err = hs.fs.mkdir(p)
    assert(ok or exists(p), err or ("Cannot create " .. p))
end
local function atomicWrite(path, data)
    local f, err = io.open(path .. ".tmp", "wb")
    assert(f, err)
    local ok, writeErr = f:write(data)
    if not ok then f:close(); error(writeErr) end
    assert(f:close())
    assert(os.rename(path .. ".tmp", path))
end
local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local function log(s)
    print("[Babelbound] " .. s)
    if job and job.folder then
        local f = io.open(job.folder .. "/run.log", "a")
        if f then f:write(os.date("%Y-%m-%d %H:%M:%S ") .. s .. "\n"); f:close() end
    end
end
local function attr(e, key)
    if not e then return nil end
    local ok, value = pcall(function() return e:attributeValue(key) end)
    if ok then return value end
end
local function frameOf(e)
    local f = attr(e, "AXFrame")
    if f and f.x and f.w then return f end
    local p, s = attr(e, "AXPosition"), attr(e, "AXSize")
    if p and s then return {x=p.x, y=p.y, w=s.w or s.width, h=s.h or s.height} end
end
local function plainFrame(f) return {x=f.x, y=f.y, w=f.w, h=f.h} end
local function inRect(p, r)
    return p.x >= r.x and p.x <= r.x+r.w and p.y >= r.y and p.y <= r.y+r.h
end
local function sameFrame(a, b)
    if not a or not b then return false end
    for _, k in ipairs({"x", "y", "w", "h"}) do
        if math.abs(a[k] - b[k]) > 1 then return false end
    end
    return true
end
local function chromeWindow()
    local app = hs.application.frontmostApplication()
    local w = hs.window.frontmostWindow()
    if not app or app:bundleID() ~= cfg.chromeBundle or not w then
        return nil, "Bring the BOOKWALKER Chrome window to the front."
    end
    return w
end
local function guard()
    local problem = providers.problem(provider, job, cal)
    if problem then return nil, problem end
    if not cal then return nil, "Calibrate first with Control-Option-Command-C." end
    local w, err = chromeWindow()
    if not w then return nil, err end
    if w:id() ~= cal.windowID then return nil, "Different Chrome window. Recalibrate." end
    if not sameFrame(w:frame(), cal.windowFrame) then
        return nil, "Chrome moved/resized. Restore its position or recalibrate."
    end
    if w:title() ~= cal.windowTitle then
        return nil, "Chrome tab/title changed. Return to the calibrated book tab."
    end
    if hs.eventtap.isSecureInputEnabled() then return nil, "macOS Secure Input is active." end
    -- The reader window/title can survive switching side panels. Verify the
    -- ChatGPT extension's own web area from the calibrated input ancestry.
    -- A coordinate or a model name alone is not provider identity evidence.
    local e=hs.axuielement.systemWideElement():elementAtPosition(cal.input.x,cal.input.y)
    local foundURL
    for _=1,24 do
        if not e or attr(e,"AXRole")=="AXWindow" then break end
        if attr(e,"AXRole")=="AXWebArea" then
            local url=attr(e,"AXURL")
            foundURL=type(url)=="table" and url.url or (type(url)=="string" and url or nil)
            if foundURL then break end
        end
        e=attr(e,"AXParent")
    end
    local chatgptURL="chrome-extension://hehggadaopoacecdllhhajmbjkdcmajg/codex-sidepanel/index.html"
    if provider=="chatgpt" and foundURL~=chatgptURL then
        return nil,"The calibrated input is not in the ChatGPT extension. Open its side panel and recalibrate."
    elseif provider=="gemini" and foundURL==chatgptURL then
        return nil,"ChatGPT is open, but this job uses Gemini. Restore the Gemini sidebar before continuing."
    end
    return w
end
-- absolutePosition warps the cursor. Post a mouseMoved event as well so
-- Chrome has an actual movement event for hover/leave handling. No click here.
local function movePointer(p)
    hs.mouse.absolutePosition(p)
    local e=hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved,p,{})
    assert(e,"Cannot create mouse-movement event")
    e:post()
end
local function capture()
    local sc = hs.screen.find(cal.screenID)
    assert(sc, "Calibrated display is no longer available")
    local sf = sc:fullFrame()
    local r = cal.crop
    local img = sc:snapshot({x=r.x-sf.x, y=r.y-sf.y, w=r.w, h=r.h})
    assert(img, "Screenshot failed. Check Hammerspoon Screen Recording permission.")
    -- Downscale only the fingerprint, NOT the saved source image.
    local small = img:copy():size({w=480, h=640}, false)
    local hash = hs.hash.SHA256(small:encodeAsURLString(true, "PNG"))
    return img, hash
end
local function pendingSourceStillVisible()
    if not job or not job.pending then return true end
    local img, hash = capture()
    return hash == job.pending.sourceHash, img, hash
end
local function setPhase(p, delay)
    if p ~= phase then inputReadback=nil end
    phase, due = p, now() + (delay or 0)
    refreshMenu()
end
-- Page model provenance describes observed UI selection, never a claim about
-- Gemini's undisclosed serving model. Keep submission and collection distinct.
local pageModels={}
function pageModels.copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value)do out[k]=pageModels.copy(v) end;return out
end
function pageModels.identity(value)
    local normalized=limits.normalize(value)
    if normalized=="" or normalized=="unverified" or normalized=="unknown" then return "Unknown","unknown" end
    local parsed=modelLabel(value) or value
    local key=limits.normalize(parsed):gsub("%s+","-"):gsub("[^%w\128-\255%-]","")
    local known={pro="Pro",["flash-lite"]="Flash-Lite",flash="Flash",fast="Fast",thinking="Thinking",auto="Auto"}
    return known[key] or parsed,key
end
function pageModels.observation(sample,id,expectedPhase)
    if type(sample)~="table" or sample.pendingID~=id or sample.phase~=expectedPhase
        or sample.scanStatus~="completed" then return nil end
    local model,key=pageModels.identity(sample.model)
    local fallbacks={}
    for _,notice in ipairs(sample.limitNotices or {})do
        if notice.classification=="continuing-fallback" then fallbacks[#fallbacks+1]=notice.text end
    end
    return {selectedModel=model,selectedModelKey=key,observedAt=sample.observedAt,
        observedAtEpoch=sample.observedAtEpoch,version=sample.version,
        fallbackNotices=fallbacks}
end
function pageModels.atSubmit(p,model,sample)
    p.modelAtSubmit=model or "unverified"
    local observation=pageModels.observation(sample,p.id,"submit-check")
    local label,key=pageModels.identity(model)
    local verified=observation and observation.selectedModelKey==key and key~="unknown"
    p.modelProvenance={basis=verified and "composer-at-submit" or "unknown",
        provider=provider,
        selectedModel=verified and label or "Unknown",selectedModelKey=verified and key or "unknown",
        observedAt=observation and observation.observedAt,
        observedAtEpoch=observation and observation.observedAtEpoch,version=M.version,
        requestID=p.id,actualServingModel="unknown",
        fallbackNoticesAtSubmit=observation and observation.fallbackNotices or {}}
end
function pageModels.status(key,provenance)
    local possible={}
    if key~="unknown" then possible[#possible+1]=key end
    local collection=provenance and provenance.collectionObservation
    local _,collectionKey=pageModels.identity(collection and collection.selectedModel)
    if collectionKey~="unknown" and collectionKey~=key then possible[#possible+1]=collectionKey end
    local status=key=="unknown" and "unknown" or "selected-at-submit"
    -- This flags differing UI observations, not a proven backend model switch.
    if key~="unknown" and collectionKey~="unknown" and collectionKey~=key then
        status="changed-during-generation"
    end
    return status,possible
end
function pageModels.forRecord(p,sample)
    local provenance=p.sent and p.modelProvenance and p.modelProvenance.requestID==p.id
        and pageModels.copy(p.modelProvenance) or nil
    if not provenance then
        local label,key=pageModels.identity(p.sent and p.modelAtSubmit or nil)
        provenance={basis=key~="unknown" and "legacy-composer-at-submit" or "unknown",
            selectedModel=label,selectedModelKey=key,version=M.version,
            requestID=p.id,actualServingModel="unknown"}
    end
    local observation=pageModels.observation(sample,p.id,"wait")
    if observation then provenance.collectionObservation=observation end
    local label,key=pageModels.identity(provenance.selectedModel)
    local status,possible=pageModels.status(key,provenance)
    return label,key,provenance,status,possible
end
function pageModels.index(records,generatedAt)
    local out={schemaVersion=1,generatedAt=generatedAt,translatorVersion=M.version,
        recordCount=#records,records={}}
    for _,r in ipairs(records)do
        local label,key=pageModels.identity(r.model)
        local status,possible=pageModels.status(key,r.modelProvenance)
        out.records[#out.records+1]={index=r.index,id=r.id,savedAt=r.savedAt,provider=r.provider or "gemini",
            model=label,modelKey=r.modelKey or key,modelAtSubmit=r.modelAtSubmit or "unverified",
            modelStatus=r.modelStatus or status,possibleModelKeys=pageModels.copy(r.possibleModelKeys or possible),
            modelProvenance=pageModels.copy(r.modelProvenance)
                or {basis="unknown",actualServingModel="unknown",requestID=r.id}}
    end
    return out
end
-- Keep the searchable page index beside the authoritative checkpoint.
checkpoint = function()
    if not job then return end
    job.lastPhase = phase
    job.updatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
    atomicWrite(job.folder .. "/checkpoint.json", hs.json.encode(job, true))
    atomicWrite(job.folder .. "/page-metadata.json",hs.json.encode(pageModels.index(job.records,job.updatedAt),true))
    refreshMenu()
end
local function beginOwnership()
    clipboardBackup = hs.pasteboard.readAllData()
    clipboardOwnedCount = nil
    sleepBackup = hs.caffeinate.get("displayIdle")
    hs.caffeinate.set("displayIdle", true)
end
local function releaseOwnership()
    -- Do not overwrite a clipboard changed by the user/another application.
    if clipboardBackup and clipboardOwnedCount
       and hs.pasteboard.changeCount() == clipboardOwnedCount then
        if pasteInFlight then
            -- A posted Cmd-V could still be pending in Chrome. Restoring the
            -- old clipboard now could paste unrelated/private user data.
            log("Paste delivery was not confirmed; leaving the generated request on the clipboard rather than restoring unrelated data.")
        else hs.pasteboard.writeAllData(clipboardBackup) end
    end
    clipboardBackup, clipboardOwnedCount = nil, nil
    if sleepBackup ~= nil then hs.caffeinate.set("displayIdle", sleepBackup) end
    sleepBackup = nil
end
local function cancelScan()
    recoveryActive = false
    epoch = epoch + 1
    local old = scan
    scan, scanPending = nil, false
    if old then pcall(function() if old:isRunning() then old:cancel("paused") end end) end
end
pause = function(reason,kind)
    local wasRunning=running
    local prior=jobStatus.idle(job)
    if quota.cancel then quota.cancel("Paused/stopped", false) end
    running = false
    cancelScan()
    releaseOwnership()
    if job then
        local preserve=not wasRunning and (reason==nil or kind=="paused")
            and (prior=="warning" or prior=="finished")
        if not preserve then
            job.pauseKind=reason~=nil and (kind or "warning") or "paused"
            if reason~=nil then job.pauseReason=reason;job.pauseReasonAt=now()end
        elseif not job.pauseKind then job.pauseKind=prior end
        local ok, err = pcall(checkpoint)
        if not ok then
            sessionWarning="Could not save the job checkpoint: "..tostring(err)
            print("[Babelbound] Checkpoint error: " .. tostring(err))
        end
    elseif reason and kind~="paused" and kind~="finished" then sessionWarning=reason end
    refreshMenu()
    if reason then
        log(reason)
        if job and job.folder then
            local ok,err=pcall(function()
                atomicWrite(job.folder.."/last-pause.json",hs.json.encode({
                    version=M.version,at=os.date("%Y-%m-%d %H:%M:%S"),
                    phase=phase,reason=reason,kind=uiState().kind,pending=job.pending and job.pending.index,
                    sent=job.pending and job.pending.sent or false,
                    saved=#job.records,remaining=job.remaining},true))
            end)
            if not ok then print("[Babelbound] Last-pause report error: "..tostring(err)) end
        end
        persistentNotice(reason,true)
    end
end
local function safe(fn)
    return function(...)
        local args = {...}
        local ok, err = xpcall(function() return fn(table.unpack(args)) end, debug.traceback)
        if not ok then pause("Error; no automatic advance. See Hammerspoon Console."); log(err) end
    end
end
local function defer(seconds, fn)
    local token = epoch
    return hs.timer.doAfter(seconds, safe(function()
        if token == epoch then fn() end
    end))
end
local function openPath(path)
    hs.task.new("/usr/bin/open", nil, {path}):start()
end
local function illustrationManifest(folder)
    local raw=readFile(folder.."/illustrations/manifest.json")
    if not raw then return nil end
    local ok,value=pcall(hs.json.decode,raw)
    if ok and type(value)=="table" and type(value.records)=="table" then return value end
end
-- Completed batches queue an EPUB. Wait for all HTML/illustration writers
-- before exporting; the file-only worker never interacts with the browser.
flushEpubs=function()
    if not epubManager or illustrationTask or illustrationQueued then return end
    for _,folder in ipairs(epubManager:pendingFolders())do
        if cfg.illustrationsEnabled then
            local saved=job and job.folder==folder and job or hs.json.decode(assert(readFile(folder.."/checkpoint.json")))
            local manifest=illustrationManifest(folder)
            if not manifest or (tonumber(manifest.sourceCount)or 0)<#saved.records then
                local started,problem=rebuildIllustrations(false,folder)
                if not started then epubManager:fail(folder,tostring(problem))end
                return
            end
        end
        epubManager:flush(folder)
    end
end
epubManager=epubExport.new({
    python=cfg.illustrationPython,script=cfg.epubScript,exists=exists,
    taskNew=function(command,callback,args)return hs.task.new(command,callback,args)end,
    decode=hs.json.decode,now=now,log=log,onChange=refreshMenu,onReady=flushEpubs,
})
requestEpub=function(saved)
    if not cfg.epubEnabled or not saved or #saved.records==0 then return end
    epubManager:request(saved.folder,jobStatus.bookTitle(saved),#saved.records)
    if cfg.illustrationsEnabled and illustrationBuild.folder==saved.folder
        and illustrationBuild.status=="failed" then
        epubManager:fail(saved.folder,"Finish rebuilding the illustrations before exporting EPUB: "..tostring(illustrationBuild.error))
    else flushEpubs()end
end
-- File-only, asynchronous archive pass. The reader and Gemini are untouched.
-- Each committed page queues an incremental refresh; manual rebuild scans the
-- entire saved book. Coalescing avoids competing HTML/manifest writers.
rebuildIllustrations=function(manual,targetFolder)
    local folder=targetFolder or (job and job.folder)
    if not folder then return nil,"Restore a saved book first." end
    if illustrationTask then illustrationQueued=folder;return {status="queued"} end
    if not exists(cfg.illustrationPython) or not exists(cfg.illustrationScript) then
        local reason="Illustration helper/runtime missing. Set GeminiBook.config.illustrationPython to a Python with Pillow and verify illustrationScript."
        illustrationBuild={status="failed",folder=folder,error=reason};refreshMenu()
        if manual and not running then alert(reason) else log(reason) end
        return nil,reason
    end
    local savedAtStart=job and job.folder==folder and job or hs.json.decode(assert(readFile(folder.."/checkpoint.json")))
    local count=#savedAtStart.records
    illustrationBuild={status="running",folder=folder,savedCount=count,startedAt=now()}
    local function finish(code,stdout,stderr)
        illustrationTask=nil
        local success,problem=pcall(function()
            assert(code==0,"Illustration scan failed: "..tostring(stderr or stdout or code))
            local manifest=assert(illustrationManifest(folder),"Illustration manifest was not produced.")
            local saved=job and job.folder==folder and job or hs.json.decode(assert(readFile(folder.."/checkpoint.json")))
            atomicWrite(folder.."/translation.html",core.html(saved.records,manifest))
            local images,screens=0,0
            for _,entry in ipairs(manifest.records)do
                local n=type(entry.illustrations)=="table" and #entry.illustrations or 0
                images=images+n;if n>0 then screens=screens+1 end
            end
            illustrationBuild={status="complete",folder=folder,savedCount=#saved.records,
                scannedCount=manifest.sourceCount,illustrations=images,illustratedScreens=screens,
                completedAt=now(),html=folder.."/translation.html"}
            refreshMenu()
            log("Illustrated reading copy updated: "..images.." illustrations across "..screens.." screens; "..#saved.records.." saved screens.")
            if #saved.records>count then illustrationQueued=illustrationQueued or folder end
        end)
        if not success then
            illustrationBuild={status="failed",folder=folder,error=tostring(problem),completedAt=now()}
            refreshMenu()
            log("Illustrated reading copy: "..tostring(problem))
            if manual and not running then alert("Illustration rebuild failed. Existing translation saves remain intact. "..tostring(problem)) end
        elseif manual and not running then
            alert("Reading copy rebuilt: "..illustrationBuild.illustrations.." illustrations in their original screen order.")
        end
        if not success and epubManager:state(folder).status=="queued" then
            epubManager:fail(folder,"Illustration rebuild failed before EPUB export: "..tostring(problem))
        end
        if illustrationQueued then
            local queuedFolder=illustrationQueued;illustrationQueued=nil
            rebuildIllustrations(false,queuedFolder)
        end
        flushEpubs()
    end
    illustrationTask=hs.task.new(cfg.illustrationPython,finish,{cfg.illustrationScript,"--job",folder})
    if not illustrationTask or not illustrationTask:start() then
        illustrationTask=nil;illustrationBuild={status="failed",folder=folder,error="Cannot start illustration helper."};refreshMenu()
        return nil,illustrationBuild.error
    end
    refreshMenu()
    return {status="running",folder=folder,savedCount=count}
end
function M.rebuildIllustrations()
    if not job then
        alert("Restore a saved book first, then rebuild its illustrations.")
        return nil,"No saved book is loaded."
    end
    local result,problem=rebuildIllustrations(true)
    if result and jobStatus.idle(job)=="finished" then requestEpub(job)end
    return result,problem
end
function M.epubStatus()
    return epubManager:state(job and job.folder)
end
function M.exportEpub()
    if not job then return nil,"Restore a saved book first."end
    requestEpub(job)
    return M.epubStatus()
end
function M.openEpub()
    if not job then alert("Restore a saved book first.");return end
    local path=job.folder.."/translation.epub"
    if exists(path)then openPath(path)
    else requestEpub(job);alert("The EPUB is being prepared in the book's output folder.")end
end
function M.illustrationStatus()
    return hs.json.decode(hs.json.encode(illustrationBuild))
end
function M.openReadingCopy()
    if not job then alert("Restore a saved book first.");return end
    openPath(job.folder.."/translation.html")
end
-- Inspect the real editor, not just the coordinates of its first text line.
-- Chrome can expose a focused static-text child and can move its text line
-- inside the composer when a skill chip is selected or a request wraps.
local function editorRole(e)
    local role = attr(e, "AXRole")
    return role == "AXTextArea" or role == "AXTextField"
        or role == "AXComboBox" or attr(e, "AXEditable") == true
end
local function editorAtOrAbove(e)
    for _=1,7 do
        if not e then break end
        if editorRole(e) then return e end
        e = attr(e, "AXParent")
    end
end
local function pidOf(e)
    if not e then return nil end
    local ok, pid = pcall(function() return e:pid() end)
    if ok then return pid end
end
local function inComposer(e)
    local f = frameOf(e)
    if not f or not f.w or not f.h or f.w <= 0 or f.h <= 0 then return false end
    local window = cal.windowFrame
    if f.x < cal.panel.x-5 or f.y < cal.panel.y
        or f.x+f.w > window.x+window.w+5
        or f.y+f.h > window.y+window.h+5 then return false end
    if inRect(cal.input, f) then return true end
    -- A previously verified editor may grow upward as text wraps. Keep the
    -- match local to the composer; never accept an arbitrary sidebar textbox.
    if verifiedInput and e == verifiedInput
        and math.abs(f.y+f.h-cal.input.y) <= 180
        and f.h <= 320 then return true end
    -- Require an actual compact parent containing BOTH the calibrated point
    -- and the text area. An entire panel/window/web area is not such a parent.
    local parent = attr(e, "AXParent")
    for _=1,7 do
        if not parent then break end
        local r = frameOf(parent)
        if attr(parent,"AXRole") == "AXGroup" and r and r.h and r.w
            and r.h > 0 and r.h <= math.min(320,window.h*0.4)
            and r.w > 0 and r.x >= cal.panel.x-5
            and r.x+r.w <= window.x+window.w+5
            and inRect(cal.input,r)
            and inRect({x=f.x,y=f.y},r)
            and inRect({x=f.x+f.w,y=f.y+f.h},r) then return true end
        parent = attr(parent,"AXParent")
    end
    return false
end
local function focusDescription(e)
    if not e then return "no element" end
    local f = frameOf(e)
    local value = attr(e,"AXValue")
    local placeholder = attr(e,"AXPlaceholderValue")
    local normalized, valueClass = core.composerValue(value, placeholder, inputHints())
    return string.format("role=%s focused=%s enabled=%s pid=%s frame=%s valueBytes=%s placeholderBytes=%s equalsPlaceholder=%s valueClass=%s matchesSkill=%s hasRequestID=%s",
        tostring(attr(e,"AXRole")),tostring(attr(e,"AXFocused")),
        tostring(attr(e,"AXEnabled")),tostring(pidOf(e)),
        f and string.format("%.1f,%.1f,%.1f,%.1f",f.x,f.y,f.w,f.h) or "none",
        type(value)=="string" and #value or type(value),
        type(placeholder)=="string" and #placeholder or type(placeholder),
        tostring(type(value)=="string" and type(placeholder)=="string"
            and placeholder~="" and value==placeholder),
        valueClass, tostring(type(normalized)=="string" and core.trim(normalized)==cfg.skill),
        tostring(job and job.pending and type(normalized)=="string"
            and normalized:find(job.pending.id,1,true)~=nil or false))
end
local function focusedInput(requireEmpty)
    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= cfg.chromeBundle then
        return nil,"Chrome is not frontmost.",nil,"focus","wrong foreground app"
    end
    local root = hs.axuielement.applicationElement(app)
    local system = hs.axuielement.systemWideElement()
    local appFocus = attr(root,"AXFocusedUIElement")
    local systemFocus = attr(system,"AXFocusedUIElement")
    local hit
    local ok, result = pcall(function()
        return system:elementAtPosition(cal.input.x,cal.input.y)
    end)
    if ok then hit = result end
    -- Successful readiness polls need the validation below, not repeated AX
    -- reads for three verbose diagnostic descriptions. Build those on failure.
    local function description()
        return "app: "..focusDescription(appFocus)
            .."\nsystem: "..focusDescription(systemFocus)
            .."\npoint: "..focusDescription(hit)
    end
    local candidates = {
        {seed=systemFocus,fromFocus=true},
        {seed=appFocus,fromFocus=true},
        {seed=hit,fromFocus=false},
    }
    for _,candidate in ipairs(candidates) do
        local e = editorAtOrAbove(candidate.seed)
        -- Root focus queries already identify focus. A hit-tested editor must
        -- explicitly report focus. A reported false is never treated as true.
        local focused = attr(e,"AXFocused")
        local focusOK = focused == true or (candidate.fromFocus and focused == nil)
        if e and focusOK and attr(e,"AXEnabled") ~= false
            and attr(e,"AXSubrole") ~= "AXSecureTextField"
            and pidOf(e) == app:pid() and inComposer(e) then
            -- Some Chrome composers expose the visual hint as AXValue but
            -- omit AXPlaceholderValue. Match the whole configured hint only;
            -- unknown nonempty values still stop before any typing.
            local value = core.composerValue(attr(e,"AXValue"),
                attr(e,"AXPlaceholderValue"), inputHints())
            if requireEmpty and (type(value)~="string" or core.trim(value)~="") then
                return nil,"The chat input is not verifiably empty. Do not send the draft. Clear it manually, then use BT > Retry pending screen.",
                    nil,"content",description().."\neditor: "..focusDescription(e)
            end
            verifiedInput=e
            return e,nil,value
        end
    end
    return nil,"Cannot verify focus in Gemini's input.",nil,"focus",description()
end
local function inputFailure(why, details)
    if job and skillFlow then
        local trace={version=M.version,phase=phase,pendingID=job.pending and job.pending.id,
            openedAt=skillFlow.openedAt,selectionAttempted=skillFlow.pressed or false,
            method="native-slash-key-then-visible-ln-AXPress-no-selection-Enter",
            baseline=skillUI.summary(skillFlow.baseline or {}),
            lastCandidates=skillFlow.lastCandidates or {},
            lastNewCandidates=skillFlow.lastNewCandidates or {},
            pressResult=skillFlow.pressResult,error=why}
        atomicWrite(job.folder.."/skill-selection.txt",hs.json.encode(trace,true).."\n")
    end
    local report="Babelbound "..M.version.." input failure\nPhase: "..phase
        .."\n"..why.."\nText contents omitted.\n"..(details or "").."\n"
        .."Pending ID: "..tostring(job and job.pending and job.pending.id).."\n"
        .."Readback wait seconds: "..tostring(inputReadback and now()-inputReadback.started or 0).."\n"
        .."Paste unconfirmed: "..tostring(pasteInFlight).."\n"
    if job then atomicWrite(job.folder.."/focus-failure.txt",report) end
    log(report)
    pause(why.." Stopped at "..phase.."; see focus-failure.txt in the output folder.")
end
local function readyInput(requireEmpty)
    local e,why,value,kind,details = focusedInput(requireEmpty)
    if e then
        if inputWaitPhase then log("Input verified in phase "..phase.." after retry.") end
        inputWaitPhase,inputWaitStarted,inputReclicked=nil,nil,false
        return e,nil,value
    end
    if inputWaitPhase~=phase then
        inputWaitPhase,inputWaitStarted,inputReclicked=phase,now(),false
        log("Waiting for input in phase "..phase..": "..why.."\n"..(details or ""))
    end
    if kind=="focus" and now()-inputWaitStarted<cfg.focusTimeout then
        -- Retry a click only while obtaining INITIAL focus, before typing.
        -- During skill selection/wrapping, only re-read; do not disrupt a menu.
        if (phase=="type-skill" or phase=="paste-inline") and not inputReclicked and now()-inputWaitStarted>=1.0 then
            inputReclicked=true
            hs.mouse.absolutePosition(cal.input)
            hs.eventtap.leftClick(cal.input,50000)
        end
        due=now()+cfg.focusPollSeconds
        return nil
    end
    inputFailure(why, details)
    return nil
end

-- Re-read Chrome's live focused editor until the expected CONTENT is stable.
-- readyInput() above verifies focus; its success alone does not say the new
-- text has arrived. No typing, Enter, reclicking, or deletion occurs here.
local function awaitInputContent(predicate, why, expected)
    if not inputReadback or inputReadback.phase~=phase then
        inputReadback={phase=phase,started=now(),lastSummary=nil,matchSince=nil}
    end
    local e, _, value=readyInput(false)
    if not e then return nil end
    local matched=predicate(value)
    local normalized=core.normalizedDraft(value)
    local summary=string.format("phase=%s bytes=%s expectedBytes=%s match=%s rawSkill=%s",
        phase, type(value)=="string" and #value or type(value),
        type(expected)=="string" and #expected or "n/a",tostring(matched),
        tostring(normalized==cfg.skill))
    if summary~=inputReadback.lastSummary then
        log("Input readback: "..summary)
        inputReadback.lastSummary=summary
    end
    if matched then
        if not inputReadback.matchSince or inputReadback.matchValue~=normalized then
            inputReadback.matchSince=now()
            inputReadback.matchValue=normalized
        end
        if now()-inputReadback.matchSince>=cfg.inputReadbackStableSeconds then
            log(string.format("Input content verified in %s after %.2fs.",phase,now()-inputReadback.started))
            return e,value
        end
    else inputReadback.matchSince=nil;inputReadback.matchValue=nil end
    if now()-inputReadback.started>=cfg.inputReadbackTimeout then
        inputFailure(why,"editor: "..focusDescription(e).."\n"..summary)
        return nil
    end
    due=now()+cfg.inputReadbackPollSeconds
    return nil
end

local function pasteRequestOnce(text)
    -- Focus is checked again immediately before the only paste keystroke.
    local e, why=focusedInput(false)
    if not e then inputFailure(why,"Focus lost before request paste."); return false end
    if not hs.pasteboard.setContents(text) then
        inputFailure("Could not place the generated request on the clipboard. No paste was sent.")
        return false
    end
    clipboardOwnedCount=hs.pasteboard.changeCount()
    if hs.pasteboard.getContents()~=text then
        inputFailure("Clipboard changed before pasting. No paste was sent.")
        return false
    end
    pasteInFlight=true
    hs.eventtap.keyStroke({"cmd"},"v",50000)
    return true
end

local function labelsOf(e)
    local out = {}
    for _, k in ipairs({"AXTitle", "AXDescription", "AXHelp", "AXIdentifier"}) do
        local v = attr(e, k)
        if type(v) == "string" and v ~= "" then out[#out+1] = v end
    end
    return out
end
-- Limit notices are service UI, not translations. Preserve a sent request;
-- an optional local timer never guesses that a sent request should be resent.
local function limitPhrases()
    return limits.readPhrases(readFile(cfg.limitPhrasesFile))
end
local function rememberUsageLimit(event, origin)
    event.version=M.version; event.origin=origin; event.phase=phase
    event.at=os.date("%Y-%m-%d %H:%M:%S"); event.atEpoch=now()
    event.pendingID=job.pending and job.pending.id
    event.pendingIndex=job.pending and job.pending.index
    event.sent=job.pending and job.pending.sent or false
    event.saved=#job.records; event.remaining=job.remaining; event.active=true
    job.usageLimit=event
    local ok,err=pcall(function()
        atomicWrite(job.folder.."/usage-limit.txt",event.text.."\n")
        atomicWrite(job.folder.."/usage-limit.json",hs.json.encode(event,true))
    end)
    if not ok then log("Could not write usage-limit evidence: "..tostring(err)) end
end
local function handleUsageLimit(event, origin)
    if not cfg.usageLimitDetection or not job then return false end
    rememberUsageLimit(event,origin)
    responseCandidate,responseSince=nil,nil
    job.deferredUsageLimit=nil
    pause("Gemini usage-limit notice detected. Progress saved; no new request or page turn will be sent. "
        .."The notice was NOT saved as a translation. "
        .."See usage-limit.txt in the output folder. "
        ..(cfg.offerAutoResume and "An optional reset-time prompt follows when a future timestamp is readable."
            or "Pause-only mode: when Gemini is available, close the model picker and use Start / resume with the currently selected model. Nothing is scheduled automatically."))
    refreshMenu()
    if cfg.offerAutoResume and quota.offer and job.remaining>0 then
        defer(0.4,function() quota.offer(event) end)
    end
    return true
end
local function checkLimitCopy(raw,origin)
    if not cfg.usageLimitDetection then return false end
    local event=limits.detect(raw,limitPhrases())
    return event and handleUsageLimit(event,origin) or false
end

-- Locate the active sidebar/composer via the known input's short parent chain.
-- There is deliberately no fallback to an entire Chrome app/window scan.
local function scopedRoots()
    local app=hs.application.frontmostApplication()
    if not app or app:bundleID()~=cfg.chromeBundle then return nil,nil end
    local ok,hit=pcall(function()
        return hs.axuielement.systemWideElement():elementAtPosition(cal.input.x,cal.input.y)
    end)
    local composer,panel
    if ok and hit then composer,panel=scopedAX.roots(hit,cal,app:pid())end
    if (not composer or not panel) and verifiedInput then
        local c,p=scopedAX.roots(verifiedInput,cal,app:pid())
        composer,panel=composer or c,panel or p
    end
    return composer,panel
end
local function scanFailure(message,stats)
    local report={"Babelbound "..M.version.." scoped accessibility scan",
        "Phase: "..phase,"Scope: "..tostring(scanKind),
        "Root: "..tostring(scanRootDescription),"Reason: "..message,
        "Visited AXChildren nodes: "..tostring(stats and stats.visited),
        "Elapsed seconds: "..tostring(stats and stats.elapsed),
        "Pruned text/editor/hidden branches: "..tostring(stats and stats.prunedText).."/"
            ..tostring(stats and stats.prunedEditors).."/"..tostring(stats and stats.prunedHidden),
        "Visible child lists used: "..tostring(stats and stats.visibleChildLists),
        "Pending ID: "..tostring(job and job.pending and job.pending.id),
        "Pending marked sent: "..tostring(job and job.pending and job.pending.sent),
        "This scan itself performed no click, paste, send, or page turn."}
    if stats and stats.error then report[#report+1]=stats.error end
    if job then atomicWrite(job.folder.."/ax-scan-failure.txt",table.concat(report,"\n").."\n")end
    log(table.concat(report,"\n"))
    pause(message.." Paused at "..phase.."; see ax-scan-failure.txt in the output folder.")
end
local function startScopedScan(root,kind,predicate,done)
    scanKind=kind
    local f=root and frameOf(root)
    scanRootDescription=root and (tostring(attr(root,"AXRole")).." "..(f and hs.json.encode(plainFrame(f))or "no frame"))or "not found"
    if not root then scanFailure("Cannot locate the current Gemini "..kind.." without searching all of Chrome.");return end
    local token=epoch
    scanPending,scanStarted=true,now()
    local readiness=kind=="composer-ready"
    local controls=kind=="sidebar" or readiness
    local timeout=readiness and cfg.readinessProbeTimeout
        or (controls and cfg.axControlTimeout or (cfg.axSearchTimeout-1))
    local budget=readiness and cfg.readinessProbeMaxNodes
        or (controls and cfg.axControlMaxNodes or cfg.axMaxNodes)
    scan=scopedAX.scan(root,{timeout=timeout,maxNodes=budget,controlScan=controls,
        -- Keep the 20ms responsiveness bound, but avoid a 10ms timer gap after
        -- every twelve cheap history nodes in a long conversation.
        sliceNodes=controls and 64 or nil,
        maxDepth=40,valid=function()return token==epoch end},predicate,safe(function(msg,results,stats)
        if token~=epoch then return end
        scan,scanPending=nil,false
        if msg~="completed" and not readiness then
            scanFailure("The scoped "..kind.." scan ended with "..msg..".",stats);return
        end
        -- A completion callback can immediately move the pointer for a copy
        -- or scroll. Recheck the foreground/window here after read-only work.
        local w,err=guard()
        if not w then pause(err);return end
        done(msg=="completed" and results or nil,stats)
    end))
end
-- This probe never authorizes a copy by itself. Explicit Stop lets us wait
-- cheaply; idle/unknown state always proceeds through the full quota/model/
-- Copy scan before any collection. No missing control is interpreted as idle.
local readinessStats
local function probeComposerReadiness(done)
    local started=now()
    local callback=done
    done=function(state,evidence)
        local id=job and job.pending and job.pending.id
        if not readinessStats or readinessStats.pendingID~=id then
            readinessStats={pendingID=id,checks=0,generating=0,idle=0,unknown=0,
                fullScans=0,intervals=0,intervalTotal=0,firstStartedAt=started,probeSeconds=0}
        end
        local stats=readinessStats
        if stats.lastState=="generating" and stats.lastStartedAt then
            local interval=started-stats.lastStartedAt
            stats.intervals=stats.intervals+1;stats.intervalTotal=stats.intervalTotal+interval
            stats.minInterval=math.min(stats.minInterval or interval,interval)
            stats.maxInterval=math.max(stats.maxInterval or interval,interval)
        end
        stats.checks=stats.checks+1;stats[state]=stats[state]+1
        stats.probeSeconds=stats.probeSeconds+(now()-started)
        stats.lastStartedAt=started;stats.lastState=state
        callback(state,evidence)
    end
    local composer,panel=scopedRoots()
    if not composer or not panel then done("unknown",{startedAt=started,reason="no-compact-composer"});return end
    local cf=frameOf(composer)
    if not cf then done("unknown",{startedAt=started,reason="no-composer-frame"});return end
    startScopedScan(composer,"composer-ready",function(e)
        local role=attr(e,"AXRole")
        return role=="AXButton" or role=="AXMenuButton" or role=="AXPopUpButton"
    end,function(results,stats)
        local stopped,idle=false,false
        for _,e in ipairs(results or {})do
            local f=frameOf(e)
            if f and f.w and f.h and f.w>0 and f.h>0 and attr(e,"AXHidden")~=true
                and attr(e,"AXEnabled")~=false
                and inRect({x=f.x+f.w/2,y=f.y+f.h/2},cf) then
                for _,label in ipairs(labelsOf(e))do
                    if core.isStopLabel(label) then stopped=true end
                    if core.isIdleComposerLabel(label) then idle=true end
                end
            end
        end
        local state=results and stopped and not idle and "generating"
            or (results and idle and not stopped and "idle" or "unknown")
        done(state,{startedAt=started,elapsed=now()-started,nodes=stats and stats.visited})
    end)
end
-- Schedule from the previous check's START, not completion. A precise wakeup
-- avoids rounding a 1/3-second cadence up to the main timer's 100ms interval.
-- Epoch cancellation, phase, due and scanPending prevent stale/overlapping work.
local function scheduleReadinessCheck(expectedPhase,started)
    due=started+cfg.pollSeconds
    defer(math.max(0,due-now()),function()
        if running and phase==expectedPhase and not scanPending then tick() end
    end)
end
-- Model evidence is scoped to the live bottom toolbar. Inline text may expand
-- the composer beyond its old compact-root threshold; do not lose the actual
-- picker merely because that compact root is absent.
local function composerModel(e,composer,panel,scanPath,role)
    return scopedAX.readModelControl(e,{cal=cal,composer=composer,panel=panel,scanPath=scanPath,
        knownRole=role,parseLabel=modelLabel,normalize=limits.normalize,namedPicker=provider=="chatgpt"})
end
scanButtons = function(done, readback)
    -- Reacquire an unavailable sidebar with bounded read-only retries. Model
    -- labels are diagnostic; a completed scan need not expose the picker.
    readback=readback or {attempt=1,history={},phase=phase}
    local w, err = guard()
    if not w then pause(err); return end
    local localOnly=phase=="check-selection"
    local composer,panel=scopedRoots()
    local scopeRoot
    if localOnly then scopeRoot=composer else scopeRoot=panel end
    local requiresCurrentScope=phase=="preflight" or phase=="preflight-manual"
        or phase=="submit-check" or phase=="saved"
    local shouldRetryScope=running and not localOnly and requiresCurrentScope
    local maxReads=math.max(1,math.min(5,math.floor(tonumber(cfg.modelReadbackAttempts) or 3)))
    local function noteRead(sample)
        sample.observedAt=os.date("!%Y-%m-%dT%H:%M:%SZ")
        sample.observedAtEpoch=now()
        sample.attempt=readback.attempt
        sample.maxAttempts=maxReads
        readback.history[#readback.history+1]=sample
        -- Keep snapshots acyclic for JSON encoding.
        lastModelReadback={}
        for k,v in pairs(sample)do lastModelReadback[k]=v end
        lastModelReadback.attempts=readback.history
    end
    local function saveReadReport()
        if job and lastModelReadback then
            atomicWrite(job.folder.."/model-check.json",hs.json.encode(lastModelReadback,true))
        end
    end
    local function retryRead(reason)
        if not shouldRetryScope then return false end
        lastModelReadback.retryReason=reason
        lastModelReadback.retryExhausted=readback.attempt>=maxReads
        saveReadReport()
        if readback.attempt>=maxReads then return false end
        log("Sidebar readback unavailable at "..phase.." (read "..readback.attempt.."/"..maxReads
            .."): "..reason..". Rechecking the current controls; no UI action will be replayed.")
        if menu then menu:setTooltip("Rechecking the chat sidebar ("..(readback.attempt+1).."/"..maxReads..")")end
        local token,expectedPhase=epoch,phase
        -- Hold the main loop while waiting. Epoch cancellation also covers
        -- Stop, manual pause, reload/shutdown and changes to the active job.
        scan,scanPending,scanStarted=nil,true,now()
        defer(math.max(0.25,math.min(5,tonumber(cfg.modelReadbackRetryDelay) or 2)),function()
            if token~=epoch or not running or phase~=expectedPhase then return end
            scanPending=false
            readback.attempt=readback.attempt+1
            scanButtons(done,readback)
        end)
        return true
    end
    if not scopeRoot and shouldRetryScope then
        noteRead({version=M.version,phase=phase,at=os.date("%Y-%m-%d %H:%M:%S"),
            pendingID=job.pending and job.pending.id,controls={},
            scanStatus="missing-scope-root",noticeCheckComplete=false})
        if retryRead("Current sidebar root unavailable")then return end
        scanFailure("Cannot locate the current chat sidebar after "..readback.attempt
            .." fresh reads. No click, paste, send, or page turn was performed by these checks.");return
    end
    local initialRootFrame=scopeRoot and frameOf(scopeRoot)
    local limitHit
    local limitCandidates={}
    local models={}
    local modelControls={}
    local quotaOptions={attr=attr,frame=frameOf,composer=composer,panel=panel,
        bounds={x=cal.panel.x,y=cal.panel.y,
            w=cal.windowFrame.x+cal.windowFrame.w-cal.panel.x,
            h=cal.windowFrame.y+cal.windowFrame.h-cal.panel.y},
        extras=cfg.usageLimitDetection and limitPhrases() or {}}
    startScopedScan(scopeRoot,localOnly and "composer" or "sidebar",function(e,scanPath)
        local role=scanPath and scanPath.knownRole or attr(e,"AXRole")
        if cfg.usageLimitDetection then
            local hit=limits.fromElement(e,quotaOptions,role)
            if hit then
                limitCandidates[#limitCandidates+1]={event=hit,element=e}
                limitHit=limitHit or hit
            end
        end
        local m,reason=composerModel(e,composer,panel,scanPath,role);if m then models[m]=true end
        if (role=="AXButton" or role=="AXMenuButton" or role=="AXPopUpButton")
            and reason~="outside-current-composer-footer" and reason~="not-a-compact-control" then
            local observed={}
            for _,k in ipairs({"AXTitle","AXValue","AXDescription","AXHelp"})do
                local v=attr(e,k)
                if type(v)=="string" and #v<=120 and (modelLabel(v)
                    or limits.normalize(v):match("^open mode picker")) then observed[k]=v end
            end
            if next(observed) then
                local f=frameOf(e)
                modelControls[#modelControls+1]={role=role,frame=f and plainFrame(f),
                    labels=observed,acceptedModel=m,reason=reason,scanDepth=scanPath and scanPath.depth}
            end
        end
        return role=="AXButton" or role=="AXMenuButton" or role=="AXPopUpButton"
    end,function(results,stats)
        -- Interpret only this fresh traversal. An earlier model observation is
        -- never substituted for a missing or conflicting current caption.
        local model,modelCount=nil,0
        for name in pairs(models)do model=name;modelCount=modelCount+1 end
        if modelCount~=1 then model=nil end
        local cf,pf=frameOf(composer),frameOf(panel)
        noteRead({version=M.version,phase=phase,at=os.date("%Y-%m-%d %H:%M:%S"),
            pendingID=job and job.pending and job.pending.id,model=model,
            composerFrame=cf and plainFrame(cf),panelFrame=pf and plainFrame(pf),
            rootFrameAtStart=initialRootFrame and plainFrame(initialRootFrame),
            scanStatus="completed",visitedNodes=stats and stats.visited,
            scanElapsed=stats and stats.elapsed,matchedButtons=#results,
            scanPrunedText=stats and stats.prunedText,scanPrunedEditors=stats and stats.prunedEditors,
            scanVisibleChildLists=stats and stats.visibleChildLists,
            controls=modelControls,limitNoticeMatched=limitHit~=nil,noticeCheckComplete=true})
        if running and (phase=="preflight" or phase=="submit-check" or phase=="saved") then
            log("Model readback: phase="..phase.." model="..tostring(model)
                .." compactComposer="..tostring(composer~=nil).." liveControls="..#modelControls
                .." read="..readback.attempt.."/"..maxReads..string.format(" scan=%.2fs nodes=%d",stats and stats.elapsed or 0,stats and stats.visited or 0))
        end
        -- Inspect every matched card: an available fallback must not conceal a
        -- blocking service error elsewhere in the same bounded sidebar scan.
        -- Retire old fallback and synthetic model-guard latches from versions
        -- that required Pro. Preserve the original receipt as inactive history.
        if running and job and (limits.isContinuingFallback(job.deferredUsageLimit)
            or (job.deferredUsageLimit and job.deferredUsageLimit.kind=="model-guard")) then
            job.deferredUsageLimit=nil
        end
        if running and job and (limits.isContinuingFallback(job.usageLimit)
            or (job.usageLimit and job.usageLimit.kind=="model-guard")) then job.usageLimit.active=false end
        if #limitCandidates>0 then
            limitHit=nil
            lastModelReadback.limitNotices={}
            for _,candidate in ipairs(limitCandidates)do
                local event=limits.withResetContext(candidate.event,candidate.element,quotaOptions)
                local historyOptions={manualResume=running and quota.manualResumeEpoch==epoch,
                    bufferSeconds=cfg.usageResumeBufferSeconds}
                local continuing=limits.isContinuingFallback(event)
                local historical,reason
                if not continuing then
                    historical,reason=resetClock.historicalNotice(event,job and job.usageLimit,now(),model,historyOptions)
                end
                lastModelReadback.limitNotices[#lastModelReadback.limitNotices+1]={
                    text=event.text,classification=continuing and 'continuing-fallback'
                        or (historical and 'historical' or 'active'),reason=reason,evidence=historical}
                if continuing then
                    if running and job then job.lastFallbackNotice={text=event.text,model=model,checkedAt=now()} end
                elseif historical then
                    if job.deferredUsageLimit and resetClock.historicalNotice(job.deferredUsageLimit,
                        job.usageLimit,now(),model,historyOptions) then
                        -- A checkpoint can retain an old deferred card from a
                        -- previously interrupted collection. Do not resurrect
                        -- that same expired card after committing its reply.
                        historical.clearedDeferred=true
                        job.deferredUsageLimit=nil
                    end
                    job.historicalUsageLimit=historical
                    if quota.historicalNoticeLoggedEpoch~=epoch then
                        quota.historicalNoticeLoggedEpoch=epoch
                        log('Recorded limit card is past its dated reset; manual resume uses the current model. New notices remain guarded.')
                    end
                else limitHit=limitHit or event end
            end
            lastModelReadback.activeLimitNoticeMatched=limitHit~=nil
            saveReadReport()
        end
        if running and limitHit then
            local p=job.pending
            if phase=="wait" and p and p.sent then
                -- Preserve a complete final response from any selected model.
                -- Do not start another request. Collection is still ID/format checked.
                if not job.deferredUsageLimit then
                    rememberUsageLimit(limitHit,"sidebar-accessibility")
                    job.deferredUsageLimit=limitHit
                    job.deferredUsageLimit.detectedAt=now();checkpoint()
                end
                if now()-job.deferredUsageLimit.detectedAt>cfg.completedReplyAfterLimitSeconds then
                    handleUsageLimit(job.deferredUsageLimit,"pending-reply-limit-timeout");return
                end
            else
                handleUsageLimit(limitHit,"sidebar-accessibility");return
            end
        end
        if readback.attempt>1 then
            lastModelReadback.retryRecovered=true
            saveReadReport()
            log("Fresh model read "..readback.attempt.."/"..maxReads.." returned "..tostring(model)
                .." at "..phase.."; continuing normal validation.")
        end
        local copies, stopped, descriptions, idleControl = {}, false, {}, false
        for _, e in ipairs(results) do
            local f = frameOf(e)
            if f and f.w and f.h and f.w > 0 and f.h > 0 then
                local center = {x=f.x+f.w/2, y=f.y+f.h/2}
                local panel = {x=cal.panel.x, y=cal.panel.y,
                    w=cal.windowFrame.x+cal.windowFrame.w-cal.panel.x,
                    h=cal.windowFrame.y+cal.windowFrame.h-cal.panel.y}
                if inRect(center, panel) and attr(e, "AXHidden") ~= true then
                    local labels = labelsOf(e)
                    descriptions[#descriptions+1] = string.format("%s | x=%.0f y=%.0f | %s",
                        tostring(attr(e,"AXRole")), center.x, center.y, table.concat(labels," | "))
                    if attr(e, "AXEnabled") ~= false then
                        local isCopy = false
                        for _, label in ipairs(labels) do
                            if core.isStopLabel(label) then stopped = true end
                            if core.isIdleComposerLabel(label) then idleControl=true end
                            if core.isCopyLabel(label) then isCopy = true end
                        end
                        if isCopy and center.y < cal.input.y-12 then
                            copies[#copies+1] = {element=e, center=center, label=table.concat(labels," | ")}
                        end
                    end
                end
            end
        end
        table.sort(copies, function(a,b) return a.center.y > b.center.y end)
        -- A missing Stop button alone is insufficient when the UI tree is empty.
        if localOnly and not stopped and not idleControl then
            scanFailure("The composer scan found neither a known idle control nor a generation control.");return
        end
        done(copies, stopped, descriptions, limitHit, model)
    end)
end
-- Capture only short labels matching the configured skill. Baseline snapshots
-- prevent selecting an old ln chip in the conversation as though it were a menu.
local function skillParams()
    local wf=cal.windowFrame
    local f=verifiedInput and frameOf(verifiedInput)
    return {skill=cfg.skill,editorTop=f and f.y or cal.input.y-10,
        panel={x=cal.panel.x,y=cal.panel.y,w=wf.x+wf.w-cal.panel.x,
            h=wf.y+wf.h-cal.panel.y}}
end
scanSkillItems = function(done)
    local w,err=guard();if not w then pause(err);return end
    local _,panel=scopedRoots()
    startScopedScan(panel,"skill-picker sidebar",function(e)
        for _,key in ipairs({"AXTitle","AXDescription","AXHelp","AXValue"})do
            local value=attr(e,key)
            if type(value)=="string" and #value<=120 and skillUI.matchesLabel(value,cfg.skill)then return true end
        end
        return false
    end,function(results)done(skillUI.snapshot(results,skillParams()))end)
end
local function skillMenuFailure(why)
    inputFailure(why.." No request text was pasted or sent. "
        .."Instead of repeating Retry, clear the draft, manually select the ln skill from Gemini's / menu, "
        .."then use BT > Continue with manually selected ln skill.")
end
local function skillDraft()
    -- A popup may temporarily own keyboard focus. Read the originally verified
    -- composer here; do not type or send while a popup has focus.
    if not verifiedInput or not inComposer(verifiedInput)then return nil end
    return core.composerValue(attr(verifiedInput,"AXValue"),
        attr(verifiedInput,"AXPlaceholderValue"),inputHints())
end
local function pointDescription(p)
    local ok, e=pcall(function()
        return hs.axuielement.systemWideElement():elementAtPosition(p.x,p.y)
    end)
    if not ok then return "Hit test failed: "..tostring(e) end
    local lines={}
    for _=1,4 do
        if not e then break end
        local f=frameOf(e)
        local label=table.concat(labelsOf(e)," | "):sub(1,160)
        lines[#lines+1]=string.format("role=%s enabled=%s frame=%s labels=%s",
            tostring(attr(e,"AXRole")),tostring(attr(e,"AXEnabled")),
            f and hs.json.encode(plainFrame(f)) or "none",label)
        e=attr(e,"AXParent")
    end
    return table.concat(lines,"\n")
end
-- Observe interference immediately before committing the one page click.
-- This is not proof that Chrome will handle an event; a failed turn still
-- pauses for reviewed recovery. In particular, no retry is added here.
local function turnInputGuard(p)
    local evidence={checkedAt=now(),allowed=false,pointerTolerance=2}
    local function blocked(why) evidence.error=why;return evidence,why end
    local app=hs.application.frontmostApplication()
    if not app or app:bundleID()~=cfg.chromeBundle then
        return blocked("Chrome is no longer frontmost; no page click was sent.")
    end
    evidence.expectedPID=app:pid()
    local ok,hit=pcall(function()
        return hs.axuielement.systemWideElement():elementAtPosition(p.x,p.y)
    end)
    if not ok or not hit then
        return blocked("Cannot verify the app at the forward target; no page click was sent.")
    end
    evidence.targetPID=pidOf(hit)
    evidence.targetRole=attr(hit,"AXRole")
    evidence.targetEnabled=attr(hit,"AXEnabled")
    if not evidence.targetPID or evidence.targetPID~=evidence.expectedPID then
        return blocked("The forward target is covered by another app or cannot be verified; no page click was sent.")
    end
    if evidence.targetEnabled==false then
        return blocked("The forward target is disabled; no page click was sent.")
    end
    local keysOK,keys=pcall(hs.eventtap.checkKeyboardModifiers)
    local buttonsOK,buttons=pcall(hs.eventtap.checkMouseButtons)
    if not keysOK or type(keys)~="table" or not buttonsOK or type(buttons)~="table" then
        return blocked("Cannot verify held keys/buttons; no page click was sent.")
    end
    evidence.keyboardModifiers={};evidence.mouseButtons={}
    for key,value in pairs(keys)do
        if value==true then evidence.keyboardModifiers[#evidence.keyboardModifiers+1]=tostring(key)end
    end
    for key,value in pairs(buttons)do
        if value==true then evidence.mouseButtons[#evidence.mouseButtons+1]=tostring(key)end
    end
    table.sort(evidence.keyboardModifiers);table.sort(evidence.mouseButtons)
    -- Caps Lock is a toggle, not evidence that the user is holding a shortcut.
    for _,key in ipairs({"cmd","alt","ctrl","shift","fn"})do
        if keys[key] then return blocked("A modifier key is held; no page click was sent.")end
    end
    if #evidence.mouseButtons>0 then
        return blocked("A mouse button is held; no page click was sent.")
    end
    local pointerOK,pointer=pcall(hs.mouse.absolutePosition)
    if not pointerOK or not pointer or type(pointer.x)~="number" or type(pointer.y)~="number" then
        return blocked("Cannot verify the pointer position; no page click was sent.")
    end
    -- hs.geometry points may be userdata; persist only primitive coordinates.
    evidence.pointer={x=pointer.x,y=pointer.y}
    evidence.pointerOffset={x=pointer.x-p.x,y=pointer.y-p.y}
    if math.abs(evidence.pointerOffset.x)>evidence.pointerTolerance
        or math.abs(evidence.pointerOffset.y)>evidence.pointerTolerance then
        return blocked("The pointer moved away from the forward target; no page click was sent.")
    end
    evidence.allowed=true
    return evidence
end
local function startTurnTrace(img,hash)
    job.turnAttemptSerial=(job.turnAttemptSerial or 0)+1
    local name=string.format("%05d-to-%05d-attempt-%03d",#job.records,#job.records+1,job.turnAttemptSerial)
    local folder=job.folder.."/turns/"..name
    mkdir(folder)
    turnTrace={version=M.version,folder=folder,afterScreen=#job.records,
        nextScreen=#job.records+1,startedAt=now(),method="mouseMoved-hover-single-click",
        sourceHash=hash,nextPoint={x=cal.next.x,y=cal.next.y},crop=cal.crop,
        windowFrame=cal.windowFrame,samples={},sameSamples=0,changedSamples=0,
        transitions=0,maxStableSeconds=0,clicks=0,
        pointBeforeHover=pointDescription(cal.next)}
    job.lastTurnFolder=folder
    if cfg.detailedTurnScreenshots or job.navigationReference then
        assert(img:saveToFile(folder.."/before.png",true,"PNG"),"Cannot save before-turn image")
        turnTrace.beforeImage=folder.."/before.png"
    else
        -- advance-ready has just matched this saved source's fingerprint.
        -- Refer to the immutable source instead of recompressing the same art.
        turnTrace.beforeImage=job.folder..string.format("/sources/%05d.png",#job.records)
    end
    atomicWrite(folder.."/trace.json",hs.json.encode(turnTrace,true))
    log(string.format("Preparing forward turn after saved screen %05d; target x=%.1f y=%.1f; one click only.",
        #job.records,cal.next.x,cal.next.y))
end
local function sampleTurn(hash)
    if not turnTrace then return end
    local stable=now()-(pageSince or now())
    local same=hash==job.lastSourceHash
    if same then turnTrace.sameSamples=turnTrace.sameSamples+1
    else turnTrace.changedSamples=turnTrace.changedSamples+1 end
    if turnTrace.lastHash and turnTrace.lastHash~=hash then turnTrace.transitions=turnTrace.transitions+1 end
    turnTrace.lastHash=hash
    turnTrace.maxStableSeconds=math.max(turnTrace.maxStableSeconds,stable)
    turnTrace.samples[#turnTrace.samples+1]={elapsed=now()-pageStarted,hash=hash,
        sameAsSaved=same,stableSeconds=stable}
end
local function finishTurnTrace(outcome,img,hash)
    if not turnTrace then return end
    turnTrace.outcome=outcome
    turnTrace.endedAt=now()
    turnTrace.finalHash=hash
    turnTrace.finalMatchesSaved=hash==job.lastSourceHash
    if img and outcome~="changed-and-settled" then
        assert(img:saveToFile(turnTrace.folder.."/after.png",true,"PNG"),"Cannot save after-turn image")
    end
    atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
    log(string.format("Forward-turn result: %s; %d same / %d changed samples; %d pixel-hash transitions; %d click.",
        outcome,turnTrace.sameSamples,turnTrace.changedSamples,turnTrace.transitions,turnTrace.clicks))
end
local function pageFailure(img,hash)
    local diagnosis
    if not job.expectChange then diagnosis="The initial source image never settled."
    elseif hash==job.lastSourceHash and (not turnTrace or turnTrace.changedSamples==0) then
        diagnosis="The forward click left the saved screen unchanged."
    elseif hash==job.lastSourceHash then
        diagnosis="The reader changed briefly, then returned to the last saved image."
    else
        diagnosis="The source image changed but never became stable long enough."
    end
    finishTurnTrace("failed-to-verify",img,hash)
    assert(img:saveToFile(job.folder.."/turn-failure.png",true,"PNG"),"Cannot save page failure image")
    local report={"Babelbound "..M.version.." page verification failure",os.date("%Y-%m-%d %H:%M:%S"),
        "Phase: "..phase,"Saved screens: "..#job.records,"Remaining: "..job.remaining,
        "Diagnosis: "..diagnosis,"Final hash: "..hash,"Last saved hash: "..tostring(job.lastSourceHash),
        "Final matches saved: "..tostring(hash==job.lastSourceHash),
        "No automatic retry or extra page-turn click was sent.",
        "Current source only: turn-failure.png; no Gemini pane captured."}
    if turnTrace then
        report[#report+1]="Trace folder: "..turnTrace.folder
        report[#report+1]=string.format("Samples same=%d changed=%d transitions=%d clicks=%d",
            turnTrace.sameSamples,turnTrace.changedSamples,turnTrace.transitions,turnTrace.clicks)
        report[#report+1]="Target before click:\n"..(turnTrace.pointAfterHover or "not recorded")
    end
    atomicWrite(job.folder.."/turn-failure.txt",table.concat(report,"\n").."\n")
    pause(diagnosis.." No extra click was sent. Saved translations are retained. "
        .."See turn-failure.txt in BT > Open output folder. Resume will ask you to verify the page position.")
end
local function waitForPage(mustChange)
    job.expectChange = mustChange
    if not mustChange then turnTrace=nil end
    pageCandidate, pageSince, pageStarted = nil, nil, now()
    movePointer(cal.input) -- Actual leave/move event; no click, no focus change.
    setPhase("settle")
end
local function preparePage(img, hash)
    finishTurnTrace("changed-and-settled",nil,hash)
    turnTrace=nil
    local index = #job.records + 1
    job.pending = {id=job.tag .. "-" .. string.format("%05d", index), index=index,
        sourceHash=hash, sent=false, provider=provider}
    local sourcePath = job.folder .. string.format("/sources/%05d.png", index)
    assert(img:saveToFile(sourcePath, true, "PNG"), "Cannot save source screenshot")
    job.needAdvance, job.turnUncertain, job.expectChange = false, false, false
    responseCandidate, responseSince = nil, nil
    verifiedInput=nil
    inputReadback=nil
    pasteInFlight=false
    skillFlow=nil
    inputWaitPhase,inputWaitStarted,inputReclicked=nil,nil,false
    setPhase("preflight")
    checkpoint()
end
-- Collection state is independent of submission and navigation. Resetting it
-- must NEVER clear pending.sent, replace the request ID, or turn a source page.
local function ensureCollection()
    if not collection or collection.id ~= job.pending.id then
        collection={id=job.pending.id,index=job.pending.index,startedAt=now(),
            copies=0,scrolls=0,viewReady=false,rejected={},events={}}
        job.lastCopyProblem=nil
    end
    return collection
end
local function collectionEvent(kind,details)
    local c=ensureCollection()
    local event=details or {}
    event.kind=kind;event.at=now()
    c.events[#c.events+1]=event
    local folder=job.folder.."/collection/"..string.format("%05d",job.pending.index)
    mkdir(folder);job.lastCollectionFolder=folder
    atomicWrite(folder.."/trace.json",hs.json.encode({version=M.version,id=c.id,index=c.index,
        startedAt=c.startedAt,copies=c.copies,scrolls=c.scrolls,events=c.events},true))
    return folder
end
local function stopCollection(reason)
    if job.deferredUsageLimit then
        handleUsageLimit(job.deferredUsageLimit,"pending-reply-unavailable");return
    end
    job.lastCopyProblem=reason
    collectionEvent("paused",{reason=reason})
    pause(reason.." No new translation request or page turn was sent by collection. "
        .."The existing reply is still pending. See the collection folder in BT > Open output folder.")
end
local function scrollResponse(reason)
    local c=ensureCollection()
    if c.scrolls>=cfg.maxResponseScrolls then
        stopCollection("Could not expose the current reply's Copy button after "..c.scrolls.." sidebar scrolls.")
        return
    end
    -- Use the center of the existing response viewport, well away from the
    -- book divider, message box, and floating controls at the bottom/right.
    local right=cal.windowFrame.x+cal.windowFrame.w
    local top=cal.panel.y+100
    local bottom=cal.input.y-140
    if bottom-top<120 or right-cal.panel.x<220 then
        stopCollection("The calibrated Gemini response viewport is too small for safe scrolling.")
        return
    end
    responseScrollPoint={x=cal.panel.x+math.min(120,(right-cal.panel.x)/3),
        y=(top+bottom)/2}
    c.scrolls=c.scrolls+1
    c.viewReady=false
    collectionEvent("prepare-sidebar-scroll",{reason=reason,point=responseScrollPoint})
    movePointer(responseScrollPoint)
    -- Delivery happens on a later tick so Pause can cancel it. Moving the
    -- pointer itself does not click, focus an editor, or turn a page.
    setPhase("response-scroll",0.25)
end
local function copiedHeader(raw)
    local cleaned=core.trim(raw)
    return cleaned:match("^%[%[BEGIN:([^%]]+)%]%]")
        or cleaned:match("^%[%[ERROR:([^%]]+)%]%]")
end
local function evaluationForPending()
    local run,p=job and job.evaluationRun,job and job.pending
    if type(run)~="table" or run.active~=true or not p
        or type(run.id)~="string" or run.id=="" or type(run.modelKey)~="string" or run.modelKey==""
        or type(p.index)~="number" or type(run.startIndex)~="number" or type(run.endIndex)~="number"
        or p.index<run.startIndex or p.index>run.endIndex then return nil end
    return run
end
local function evaluationSourceProblem()
    local run,p=job and job.evaluationRun,job and job.pending
    if not run or not run.active or run.expectedSourceHashes==nil then return nil end
    local expected=type(run.expectedSourceHashes)=="table" and p
        and (run.expectedSourceHashes[tostring(p.index)] or run.expectedSourceHashes[p.index])
    if type(expected)~="string" or #expected~=64 or not expected:match("^[0-9a-f]+$") then
        return "Model comparison has no valid reference screenshot for screen "..tostring(p and p.index)..". Prepared request was not sent."
    end
    if p.sourceHash~=expected then
        return "Model comparison source mismatch at screen "..p.index..". Return to the matching first-pass page. Prepared request was not sent."
    end
end
local function recordCandidate(raw)
    if checkLimitCopy(raw,"copied-response") then return end
    local c=ensureCollection()
    local evaluation=evaluationForPending()
    local answer, err, kind = core.parse(raw, job.pending.id,
        evaluation and {allowUntranslatedForEvaluation=true} or nil)
    local folder=collectionEvent("clipboard-read",{bytes=#raw,observedID=copiedHeader(raw),
        valid=answer~=nil,reason=err,qualityIssue=answer and answer.qualityIssue,
        anchorLineBreaksNormalized=answer and answer.anchorLineBreaksNormalized or false,
        endMarkerSuffixNormalized=answer and answer.endMarkerSuffixNormalized or false})
    log("Copy check for "..job.pending.id..": bytes="..#raw.."; observedID="
        ..tostring(copiedHeader(raw)).."; "..(answer and "valid" or tostring(err)))
    if kind == "error" then
        atomicWrite(job.folder .. "/needs-attention.txt", raw)
        pause(err .. ". See needs-attention.txt.")
        return
    end
    if not answer then
        job.lastCopyProblem = err
        -- Preserve the exact rejected copy, without changing accepted records.
        atomicWrite(folder.."/rejected-copy-"..string.format("%02d",c.copies)..".txt",raw)
        responseCandidate,responseSince=nil,nil
        local key=hs.hash.SHA256(raw)
        c.rejected[key]=(c.rejected[key] or 0)+1
        if kind == "incomplete" then
            atomicWrite(job.folder .. "/partial-response.txt", raw)
            if c.rejected[key]>=3 then
                stopCollection("The same response failed validation three times. Parser reason: "..tostring(err)..".")
            else setPhase("wait",cfg.pollSeconds)end
        elseif c.rejected[key]>=2 then
            stopCollection("The same wrong or unrecognized text was copied twice, including after scrolling. "
                .."Expected "..job.pending.id.."; copied marker "..tostring(copiedHeader(raw))..".")
        else
            scrollResponse("Rejected clipboard text: "..tostring(err))
        end
        return
    end
    job.lastCopyProblem=nil
    -- An exact request ID and complete reply were read from the live Copy
    -- target. A forced scroll adds no evidence before its second checked copy.
    c.viewReady=true
    if responseCandidate ~= answer.raw then
        responseCandidate, responseSince = answer.raw, now()
        -- Revalidate generation/quota/model controls while the duplicate-copy
        -- stability window elapses. copyButton gates the next actual click.
        setPhase("wait")
        return
    end
    if now() - responseSince < cfg.stableResponseSeconds then
        setPhase("wait", cfg.pollSeconds); return
    end
    collectionEvent("validated-two-identical-copies",{bytes=#answer.raw})
    saveAnswer(answer, false)
end
saveAnswer = function(answer, manual)
    if not pendingSourceStillVisible() then
        pause("Source screen changed during translation. Return to the pending page."); return
    end
    local sourceKey = answer.first .. "\n" .. answer.last
    if not manual then
        for _, r in ipairs(job.records) do
            if r.first .. "\n" .. r.last == sourceKey then
                atomicWrite(job.folder .. "/needs-attention.txt", answer.raw)
                pause("Repeated source anchors: possible stale page (or another textless page). Review before accepting.")
                return
            end
        end
    end
    local p = job.pending
    local evaluation=evaluationForPending()
    local model,modelKey,modelProvenance,modelStatus,possibleModelKeys=pageModels.forRecord(p,lastModelReadback)
    local record = {index=p.index, id=p.id, first=answer.first, last=answer.last,provider=provider,
        text=answer.text, sourceHash=p.sourceHash, manual=manual,
        model=model,modelKey=modelKey,modelAtSubmit=p.modelAtSubmit or "unverified",
        modelProvenance=modelProvenance,modelStatus=modelStatus,possibleModelKeys=possibleModelKeys,
        qualityIssue=answer.qualityIssue,evaluationRunID=evaluation and evaluation.id,
        evaluationModelKey=evaluation and evaluation.modelKey,
        savedAt=os.date("!%Y-%m-%dT%H:%M:%SZ")}
    local stem = string.format("%05d", p.index)
    atomicWrite(job.folder .. "/responses/" .. stem .. ".txt", answer.raw .. "\n")
    atomicWrite(job.folder .. "/pages/" .. stem .. ".md", answer.text .. "\n")
    job.records[#job.records+1] = record
    if evaluation and p.index>=evaluation.endIndex then evaluation.active=false end
    job.pending = nil
    job.lastSourceHash, job.needAdvance = p.sourceHash, true
    job.navigationReference=nil -- A reviewed reference belongs only to its saved record.
    job.remaining = math.max(0, job.remaining - 1)
    local pauseAfterOne=job.pauseAfterNext==true
    job.pauseAfterNext=nil
    -- A validated save resolves the previous recovery warning.
    job.pauseKind=nil;job.pauseReason=nil;sessionWarning=nil
    -- Checkpoint the commit BEFORE any possible page turn.
    setPhase("saved", cfg.betweenPages)
    checkpoint()
    atomicWrite(job.folder .. "/translation.md", core.markdown(job.records))
    atomicWrite(job.folder .. "/translation.html", core.html(job.records,illustrationManifest(job.folder)))
    log(string.format("Saved screen %05d (%s)", record.index, record.id))
    if cfg.illustrationsEnabled then rebuildIllustrations(false) end
    if job.remaining == 0 then
        if job.deferredUsageLimit then
            log("Batch finished before applying a deferred service notice; no work remains in this batch.")
            job.completedBatchNotice=job.deferredUsageLimit;job.deferredUsageLimit=nil
        end
        pause("Batch complete. Last page remains visible. Review the saved translation.","finished")
        requestEpub(job)
    elseif job.deferredUsageLimit then
        local event=job.deferredUsageLimit
        log("Saved the complete reply before honoring the usage-limit pause.")
        handleUsageLimit(event,"after-saving-complete-reply")
    elseif pauseAfterOne then pause("One-screen test complete. "..#job.records.." screens saved; "..job.remaining.." remain in this batch. Leave this book page displayed. Start/resume continues the remaining screens.","paused")
    elseif manual then pause("Reviewed response saved. Resume when ready.","paused") end
end
-- Only Copy uses this path. Request submission and book navigation are unchanged.
-- A successful AXPress return did not produce a clipboard change in the uploaded
-- 1.1.8 trace. Use one ordinary mouse click, after verifying what is really there.
local function copyButton(candidate)
    local c=ensureCollection()
    if c.copies>=cfg.maxCopyAttempts then
        stopCollection("The bounded Copy-attempt limit was reached without a validated reply.");return
    end
    copyTarget=candidate
    collectionEvent("prepare-copy-click",{point=candidate.center,label=candidate.label})
    movePointer(candidate.center)
    local delay=cfg.copyHoverSeconds
    if responseCandidate and responseSince then
        delay=math.max(delay,responseSince+cfg.stableResponseSeconds-now())
    end
    setPhase("copy-click",delay)
end
-- The scoped scan already identified a Copy control. Re-read that SAME
-- control before clicking. A system hit test is extra evidence, not a demand
-- that Chrome return another AXButton with the same label. Native wrappers,
-- icon children and hover help can be reported instead. Unknown is not false.
-- This relaxation is ONLY for copying; input and page-turn guards are untouched.
local function visibleCopyAt(candidate)
    local point = candidate.center
    local app=hs.application.frontmostApplication()
    if not app or app:bundleID()~=cfg.chromeBundle then return nil,"Chrome is not frontmost." end
    local wf=cal.windowFrame
    if point.x<=cal.panel.x or point.x>=wf.x+wf.w
        or point.y<cal.panel.y or point.y>=cal.input.y-12 then
        return nil,"Copy target is outside the Gemini reply area."
    end
    local button=candidate.element
    local f=frameOf(button)
    local role=attr(button,"AXRole")
    local labels=labelsOf(button)
    local isCopy=false
    for _,label in ipairs(labels) do if core.isCopyLabel(label) then isCopy=true end end
    local evidence={point=point,candidate={role=role,pid=pidOf(button),
        frame=f and plainFrame(f),labels=labels,enabled=attr(button,"AXEnabled"),
        hidden=attr(button,"AXHidden")},hits={}}
    if (role~="AXButton" and role~="AXMenuButton") or not isCopy
        or pidOf(button)~=app:pid() or attr(button,"AXEnabled")==false
        or attr(button,"AXHidden")==true or not f or not f.w or not f.h
        -- Chrome exposes clipped historical controls as one-pixel slivers.
        -- A matching AX hit on that sliver is not a usable Copy button.
        or f.w<12 or f.h<12 or f.w>200 or f.h>100 or not inRect(point,f)
        or math.abs(point.x-(f.x+f.w/2))>2 or math.abs(point.y-(f.y+f.h/2))>2 then
        evidence.result="live-candidate-rejected"
        collectionEvent("copy-target-check",evidence)
        return nil,"The discovered Copy control changed, moved, or is unavailable."
    end
    local ok,e,hitErr=pcall(function()
        return hs.axuielement.systemWideElement():elementAtPosition(point.x,point.y)
    end)
    if not ok then evidence.hitError=tostring(e);e=nil
    elseif hitErr then evidence.hitError=tostring(hitErr) end
    local seen={}
    for _=1,12 do
        if not e or seen[e] then break end
        seen[e]=true
        local pid=pidOf(e)
        local r=attr(e,"AXRole")
        local ef=frameOf(e)
        local ls=labelsOf(e)
        evidence.hits[#evidence.hits+1]={role=r,pid=pid,frame=ef and plainFrame(ef),
            labels=ls,enabled=attr(e,"AXEnabled"),hidden=attr(e,"AXHidden")}
        if pid and pid~=app:pid() then
            evidence.result="other-process-over-target";collectionEvent("copy-target-check",evidence)
            return nil,"The Copy-point accessibility lookup reports another application over the target."
        end
        if r=="AXApplication" or r=="AXWindow" then break end
        if r=="AXButton" or r=="AXMenuButton" then
            local hitCopy=false
            for _,label in ipairs(ls) do if core.isCopyLabel(label) then hitCopy=true end end
            if hitCopy and attr(e,"AXEnabled")~=false and attr(e,"AXHidden")~=true
                and ef and sameFrame(ef,f) then
                evidence.result="live-candidate-and-hit-agree";collectionEvent("copy-target-check",evidence)
                return button
            end
            -- A distinct actionable control is a contradiction; a generic
            -- container or missing hit result is merely inconclusive.
            evidence.result="different-button-at-target";collectionEvent("copy-target-check",evidence)
            return nil,"The Copy-point lookup reports a different or disabled button; no click was attempted."
        end
        if r=="AXTextArea" or r=="AXTextField" or r=="AXComboBox"
            or r=="AXMenuItem" or r=="AXLink" or attr(e,"AXEditable")==true then
            evidence.result="other-interactive-control-at-target";collectionEvent("copy-target-check",evidence)
            return nil,"The Copy-point lookup reports another interactive control; no click was attempted."
        end
        -- Parent traversal remains bounded; no broad tree scan or label
        -- inference from the contents of the conversation is performed here.
        e=attr(e,"AXParent")
    end
    evidence.result="live-candidate-verified-hit-inconclusive"
    collectionEvent("copy-target-check",evidence)
    return button
end
local function clipboardState()
    local count=hs.pasteboard.changeCount()
    local raw=hs.pasteboard.getContents()
    local types
    if hs.pasteboard.contentTypes then
        local ok,value=pcall(hs.pasteboard.contentTypes)
        if ok then types=value end
    end
    return count,raw,types
end

tick = function()
    if scanPending and now()-scanStarted > (scanKind=="sidebar" and (cfg.axControlTimeout+1) or cfg.axSearchTimeout) then
        scanFailure("The "..tostring(scanKind).." scan exceeded its deadline.",scan); return
    end
    if not running or now() < due then return end
    -- Scans are read-only and have their own deadline/cancellation checks.
    -- Validate the window on the next actionable tick, not every 250ms while
    -- waiting for the same asynchronous traversal to finish.
    if scanPending then return end
    local w, err = guard()
    if not w then pause(err); return end

    if phase == "settle" then
        local checkedAt=now()
        local img, hash = capture()
        if hash ~= pageCandidate then pageCandidate, pageSince = hash, now() end
        sampleTurn(hash)
        local changed = not job.expectChange or hash ~= job.lastSourceHash
        if changed and now()-pageStarted >= cfg.pageMinimumWait
           and now()-pageSince >= cfg.pageStableSeconds then
            preparePage(img, hash)
        elseif job.expectChange and turnTrace and turnTrace.changedSamples==0
            and hash==job.lastSourceHash and now()-pageStarted>=cfg.pageUnchangedTimeout then
            pageFailure(img,hash)
        elseif now()-pageStarted > cfg.pageChangeTimeout then
            pageFailure(img,hash)
        else scheduleReadinessCheck("settle",checkedAt) end
    elseif phase == "preflight" then
        scanButtons(function(_, stopped, _, _, model)
            if not running then return end
            if stopped then pause("The chat is already generating. Wait/stop it before retrying this screen.")
            else setPhase("focus") end
        end)
    elseif phase == "preflight-manual" then
        scanButtons(function(_,stopped,_,_,model)
            if not running then return end
            if stopped then pause("The chat is already generating. Wait for it before continuing.")
            else setPhase("focus-manual")end
        end)
    elseif phase == "focus-manual" then
        hs.mouse.absolutePosition(cal.input)
        hs.eventtap.leftClick(cal.input,50000)
        setPhase("manual-skill-ready",1.0)
    elseif phase == "manual-skill-ready" then
        local e,value=awaitInputContent(function(v)return core.selectedSkillValue(v,cfg.skill)end,
            "The manually selected skill is not ready: remove draft text and select the blue ln skill chip in the CURRENT input.")
        if not e then return end
        job.pending.composerPrefix=value
        job.pending.selectionVerified=true
        job.pending.selectionEvidence="explicit-user-confirmation-of-current-ln-chip"
        setPhase("add-id");checkpoint()
    elseif phase == "focus" then
        hs.mouse.absolutePosition(cal.input)
        hs.eventtap.leftClick(cal.input, 50000)
        local inline=provider=="chatgpt" or (job.requestMode or cfg.defaultRequestMode)=="inline"
        local p=job.pending
        local prepared=p and p.sent==false and p.inputMode=="inline"
            and type(p.requestText)=="string" and type(p.pasteAttemptedAt)=="number"
            and core.isPreparedInlineRequest(p.requestText,p.id)
        -- A pause/reload can leave our complete unsent request in the editor.
        -- Revalidate it through submit, including the existing source/model/
        -- generation checks; never append another copy or clear a foreign draft.
        if prepared then
            log("Resuming prepared inline request "..p.id.."; checking the existing editor before any paste or send.")
            setPhase("resume-inline",cfg.inputReadbackPollSeconds)
        else
            -- Initial requests still require a focused, empty editor to paste.
            setPhase(inline and "paste-inline" or "type-skill",inline and cfg.focusPollSeconds or 1.0)
        end
    elseif phase == "resume-inline" then
        local e,_,value=readyInput(false);if not e then return end
        if type(value)=="string" and core.trim(value)=="" then
            -- The old paste may not have arrived, or the user cleared it.
            -- paste-inline independently rechecks emptiness before pasting.
            setPhase("paste-inline")
        else
            -- Full draft equality is required by submit, even after a reload.
            setPhase("submit")
        end
    elseif phase == "paste-inline" then
        local e=readyInput(true);if not e then return end
        local instructions=readFile(cfg.promptFile)
        if not instructions or #core.trim(instructions)<100 then
            inputFailure("The local translation-instruction file is missing or empty. No request was pasted.");return
        end
        job.pending.inputMode="inline"
        job.pending.composerPrefix=""
        job.pending.selectionVerified=nil
        job.pending.selectionEvidence=nil
        job.pending.requestText=core.inlineRequestText(job.pending.id,providers.instructions(provider,instructions))
        job.pending.pasteAttemptedAt=now()
        checkpoint()
        log("Pasting full local translation instructions once; no slash or skill-picker action.")
        if not pasteRequestOnce(job.pending.requestText)then return end
        setPhase("submit",cfg.inputReadbackPollSeconds)
    elseif phase == "type-skill" then
        if provider=="chatgpt" then pause("ChatGPT jobs use direct prompts. No skill command was sent.");return end
        local e = readyInput(true)
        if not e then return end
        skillFlow={baseline={}}
        setPhase("skill-baseline")
    elseif phase == "skill-baseline" then
        scanSkillItems(function(items)
            if not running then return end
            skillFlow.baseline=items
            setPhase("open-skill")
        end)
    elseif phase == "open-skill" then
        local e=readyInput(true); if not e then return end
        -- keyStrokes('/ln') uses Unicode-injection events, which are not the
        -- same as the slash key event used to open this browser UI. Send ONE
        -- ordinary slash key and select the exact visible ln menu option.
        hs.eventtap.keyStroke({},"/",50000)
        skillFlow.openedAt=now()
        log("Sent one native slash key; waiting for a NEW visible ln skill option. No selection Return will be sent.")
        setPhase("skill-menu",cfg.skillMenuDelay)
    elseif phase == "skill-menu" then
        if now()-skillFlow.openedAt>cfg.skillMenuTimeout then
            skillMenuFailure("The skill picker did not expose one new selectable ln entry.");return
        end
        local value=core.normalizedDraft(skillDraft())
        if value~="/" then
            if value and value~=""then
                skillMenuFailure("The draft changed unexpectedly while opening the skill picker.");return
            end
            due=now()+0.3;return
        end
        scanSkillItems(function(items)
            if not running then return end
            local choices=skillUI.newCandidates(items,skillFlow.baseline)
            skillFlow.lastCandidates=skillUI.summary(items)
            skillFlow.lastNewCandidates=skillUI.summary(choices)
            if #choices>1 then
                skillMenuFailure("More than one new ln option is exposed; refusing to choose an ambiguous target.")
            elseif #choices==1 then
                local c=choices[1]
                if not skillFlow.candidate or skillFlow.candidate.signature~=c.signature then
                    skillFlow.candidate=c;skillFlow.candidateSince=now();due=now()+0.5
                elseif now()-skillFlow.candidateSince>=0.5 then
                    skillFlow.candidate=c;setPhase("press-skill")
                else due=now()+0.5 end
            else
                skillFlow.candidate=nil;skillFlow.candidateSince=nil;due=now()+0.6
            end
        end)
    elseif phase == "press-skill" then
        if core.normalizedDraft(skillDraft())~="/"
            or not skillUI.stillPressable(skillFlow.candidate,skillParams())then
            skillMenuFailure("The verified ln option changed before it could be selected.");return
        end
        skillFlow.pressed=true
        job.pending.skillSelectionAttemptedAt=now()
        checkpoint()
        -- Exactly one action. Even if AX reports an error, do not blindly
        -- click again or press Enter; first observe the resulting editor.
        local ok,result=pcall(function()return skillFlow.candidate.element:performAction("AXPress")end)
        skillFlow.pressResult=ok and (result and "returned-success" or "returned-nil") or "raised-error"
        log("Selected new visible ln option via ONE AXPress ("..skillFlow.pressResult.."); verifying editor.")
        setPhase("check-selection",cfg.skillSelectDelay)
    elseif phase == "check-selection" then
        scanButtons(function(_, stopped)
            if not running then return end
            if stopped then
                pause("Selecting the skill sent it immediately. Do not continue; the invocation sequence needs adjustment.")
            else setPhase("verify-selection") end
        end)
    elseif phase == "verify-selection" then
        local e,value=awaitInputContent(function(v)
            return core.selectedSkillValue(v,cfg.skill)
        end,"The clicked ln skill did not become a selected chip. No request was pasted or sent. Manually select ln, then use BT > Continue with manually selected ln skill.")
        if not e then return end
        job.pending.composerPrefix=value
        job.pending.selectionVerified=true
        job.pending.selectionEvidence="new-visible-ln-menu-option-AXPress-and-editor-transition"
        setPhase("add-id")
        checkpoint()
    elseif phase == "add-id" then
        local e,_,value = readyInput(false)
        if not e then return end
        if not job.pending.selectionVerified
            or not core.selectedSkillValue(value,cfg.skill) then
            inputFailure("Gemini's input changed before pasting the request. Nothing was pasted or sent.",
                "editor: "..focusDescription(e)); return
        end
        job.pending.composerPrefix=value
        job.pending.requestText=core.requestText(job.pending.id)
        job.pending.pasteAttemptedAt=now()
        checkpoint() -- Recovery never blindly appends to a surviving draft.
        if not pasteRequestOnce(" "..job.pending.requestText) then return end
        setPhase("submit",cfg.inputReadbackPollSeconds)
    elseif phase == "submit" then
        local request=job.pending.requestText
        if not request or (not job.pending.selectionVerified and job.pending.inputMode~="inline") then
            inputFailure("No verified request-preparation state. Clear the draft and use BT > Retry pending screen.");return
        end
        local e = awaitInputContent(function(value)
            return core.requestDraftMatches(value,request,job.pending.composerPrefix)
        end,"Cannot verify the COMPLETE request in Gemini's input after waiting. No Send/Return was issued. Clear the draft and use BT > Retry pending screen.",request)
        if not e then return end
        pasteInFlight=false
        setPhase("submit-check")
    elseif phase=="submit-check" then
        scanButtons(function(_,stopped,_,_,model)
            if not running then return end
            if stopped then pause("Gemini began generating before submission; the prepared draft was not sent.");return end
            local sourceProblem=evaluationSourceProblem()
            if sourceProblem then pause(sourceProblem);return end
            if job.evaluationRun and job.evaluationRun.active then
                local _,key=pageModels.identity(model)
                if key~=job.evaluationRun.modelKey then
                    pause("Model comparison requires "..job.evaluationRun.modelKey.."; current selection is "..key..". Prepared request was not sent.");return
                end
                if key=="flash" then
                    for _,notice in ipairs(lastModelReadback and lastModelReadback.limitNotices or {})do
                        if notice.classification=="continuing-fallback" then
                            pause("Gemini reports a fallback model. Paused the Flash comparison before sending so the runs stay separate.");return
                        end
                    end
                end
            end
            pageModels.atSubmit(job.pending,model,lastModelReadback)
            setPhase("send")
        end)
    elseif phase=="send" then
        local sourceProblem=evaluationSourceProblem()
        if sourceProblem then pause(sourceProblem);return end
        local e,_,value=readyInput(false);if not e then return end
        if not core.requestDraftMatches(value,job.pending.requestText,job.pending.composerPrefix) then
            inputFailure("The prepared request changed before Send. Nothing was submitted.");return
        end
        if not pendingSourceStillVisible() then pause("Book page changed before submission."); return end
        -- Write-ahead flag: recovery will wait, NOT submit a duplicate after a crash.
        job.pending.sent = true
        job.pending.sentAt = now()
        checkpoint()
        hs.eventtap.keyStroke({}, "return", 50000)
        responseCandidate, responseSince = nil, nil
        setPhase("wait", cfg.pollSeconds)
    elseif phase == "wait" then
        -- Fast generation probes must not extend an already-detected service
        -- limit's shorter collection window while Stop remains visible.
        local deferredLimit=job.deferredUsageLimit
        if deferredLimit and not limits.isContinuingFallback(deferredLimit)
            and deferredLimit.kind~="model-guard" and type(deferredLimit.detectedAt)=="number"
            and now()-deferredLimit.detectedAt>cfg.completedReplyAfterLimitSeconds then
            handleUsageLimit(deferredLimit,"pending-reply-limit-timeout");return
        end
        if now() - job.pending.sentAt > cfg.responseTimeout then
            pause("No validated reply within 5 minutes. " .. (job.lastCopyProblem or "Check the chat panel and run diagnostics.")); return
        end
        local checkStarted=now()
        probeComposerReadiness(function(state,probe)
        if not running or phase~="wait" then return end
        if state=="generating" then
            scheduleReadinessCheck("wait",probe.startedAt);return
        end
        readinessStats.fullScans=readinessStats.fullScans+1
        scanButtons(function(copies, stopped, descriptions)
            if not running then return end
            if stopped then scheduleReadinessCheck("wait",checkStarted); return end
            local c=ensureCollection()
            if not c.readinessLogged then
                c.readinessLogged=true
                collectionEvent("readiness-summary",pageModels.copy(readinessStats))
                local average=readinessStats.intervals>0 and readinessStats.intervalTotal/readinessStats.intervals or 0
                log(string.format("Readiness: %d compact checks, %d generating, %d full scans; mean generation check interval %.3fs.",
                    readinessStats.checks,readinessStats.generating,readinessStats.fullScans,average))
            end
            -- Try an already-visible live Copy target before scrolling. The
            -- hit test rejects clipped/overlaid controls; response parsing then
            -- requires the exact pending ID. An old reply is discarded and
            -- follows the existing bounded scroll/retry path.
            if #copies==0 then
                collectionEvent("no-visible-copy",{buttons=descriptions})
                scrollResponse("Expose the current reply's Copy button.")
            else
                if not c.viewReady then
                    local visible=visibleCopyAt(copies[1])
                    if not visible then
                        scrollResponse("Expose a live Copy target before collecting the current reply.");return
                    end
                end
                collectionEvent("candidate-list",{buttons=descriptions,selected=copies[1].center})
                copyButton(copies[1])
            end
        end)
        end)
    elseif phase == "response-scroll" then
        local c=ensureCollection()
        if not job.pending.sent then stopCollection("The pending request is not marked sent.");return end
        if not pendingSourceStillVisible() then
            stopCollection("The book image changed before sidebar scrolling.");return
        end
        local app=hs.application.frontmostApplication()
        local ok,hit=pcall(function()
            return hs.axuielement.systemWideElement():elementAtPosition(responseScrollPoint.x,responseScrollPoint.y)
        end)
        local pidOK=false
        if ok and hit and app then
            local good,pid=pcall(function()return hit:pid()end)
            pidOK=good and pid==app:pid()
        end
        if not pidOK then
            stopCollection("Another application or inaccessible overlay covers the sidebar scroll point.");return
        end
        -- Negative vertical pixel offsets scroll down (Hammerspoon API).
        -- This is a wheel event in the response pane, NOT a book-page click.
        local pixels=math.floor(math.max(1200,(cal.input.y-cal.panel.y-160)*4))
        hs.eventtap.scrollWheel({0,-pixels},{},"pixel")
        collectionEvent("sidebar-scroll-delivered",{pixels=pixels,point=responseScrollPoint})
        setPhase("response-scroll-settle",cfg.responseScrollSettle)
    elseif phase == "response-scroll-settle" then
        if not pendingSourceStillVisible() then
            stopCollection("The book image changed while scrolling the chat pane.");return
        end
        ensureCollection().viewReady=true
        setPhase("wait",0.25)
    elseif phase == "copy-source-check" then
        local c=ensureCollection()
        if not job.pending.sent or not c.sourceWaitStarted then
            stopCollection("No sent request is awaiting its original source image.");return
        end
        if now()-c.sourceWaitStarted>=30 then
            stopCollection("The original book image did not return unchanged before copying the reply.");return
        end
        if pendingSourceStillVisible() then
            c.sourceWaitMatchedAt=c.sourceWaitMatchedAt or now()
            if now()-c.sourceWaitMatchedAt>=1 then
                collectionEvent("original-source-restored",{waitSeconds=now()-c.sourceWaitStarted})
                c.sourceWaitStarted,c.sourceWaitMatchedAt=nil,nil
                copyTarget=nil
                -- Reacquire generation/model/copy controls after the wait.
                -- Never click the old target or adopt a changed source hash.
                setPhase("wait");return
            end
        else c.sourceWaitMatchedAt=nil end
        scheduleReadinessCheck("copy-source-check",now())
    elseif phase == "copy-click" then
        if not copyTarget or not job.pending.sent then
            stopCollection("There is no verified Copy target for this sent request.");return
        end
        local sameSource,sourceImage,observedHash=pendingSourceStillVisible()
        if not sameSource then
            local folder=collectionEvent("source-mismatch-before-copy",{
                expectedHash=job.pending.sourceHash,observedHash=observedHash})
            -- Keep the actual mismatch, before a pause alert can cover the
            -- source. This is diagnostic evidence, never a new reference.
            if sourceImage and sourceImage.saveToFile then
                pcall(function()sourceImage:saveToFile(folder.."/source-mismatch.png",true,"PNG")end)
            end
            if provider=="chatgpt" then
                local c=ensureCollection()
                c.sourceWaitStarted=now();c.sourceWaitMatchedAt=nil
                copyTarget=nil
                -- Chrome's tab-reading debugger banner can remain briefly
                -- after generation and resize the reader. Poll for the exact
                -- original image; no blind sleep and no changed-page adoption.
                collectionEvent("waiting-for-original-source",{timeoutSeconds=30,stableSeconds=1})
                setPhase("copy-source-check",cfg.pollSeconds);return
            end
            stopCollection("The book image changed before copying the reply.");return
        end
        local button,why=visibleCopyAt(copyTarget)
        if not button then
            collectionEvent("copy-hit-test-failed",{point=copyTarget.center,reason=why})
            -- A reply can reflow between a completed scan and this tick. Drop
            -- the stale target and reacquire through the existing bounded
            -- sidebar scroll/scan path. Never click it or resend the request.
            copyTarget=nil
            ensureCollection().viewReady=false
            scrollResponse(why.." No Copy click was sent; reacquiring the current reply.");return
        end
        local c=ensureCollection()
        c.copies=c.copies+1
        copyBefore,copyStarted=hs.pasteboard.changeCount(),now()
        copyClipboardState=nil
        collectionEvent("mouse-copy-click",{attempt=c.copies,point=copyTarget.center,
            label=table.concat(labelsOf(button)," | "),beforeCount=copyBefore})
        -- Never pair this with AXPress. One mouse-down/up per copy attempt.
        local ok,err=pcall(hs.eventtap.leftClick,copyTarget.center,cfg.copyClickHoldUS)
        if not ok then
            collectionEvent("copy-click-delivery-error",{error=tostring(err)})
            -- Delivery can be ambiguous; wait for the clipboard, not another click.
        end
        copyTarget=nil
        setPhase("clipboard",0.25)
    elseif phase == "clipboard" then
        local count,raw,types=clipboardState()
        local changed=count~=copyBefore
        local state=tostring(count)..":"..type(raw)..":"..(type(raw)=="string" and #raw or "nil")
        if state~=copyClipboardState then
            copyClipboardState=state
            collectionEvent("clipboard-observation",{beforeCount=copyBefore,currentCount=count,
                changed=changed,textType=type(raw),bytes=type(raw)=="string" and #raw or nil,
                contentTypes=types,elapsed=now()-copyStarted})
        end
        if changed and type(raw)=="string" and #raw>0 then
            clipboardOwnedCount=count
            recordCandidate(raw)
        elseif now()-copyStarted > (changed and cfg.copyTimeout or cfg.copyNoChangeTimeout) then
            local c=ensureCollection()
            c.clipboardTimeouts=(c.clipboardTimeouts or 0)+1
            job.lastCopyProblem=changed
                and "Copy changed the clipboard, but readable text did not arrive within the wait."
                or "No clipboard change was observed after the verified Copy click."
            collectionEvent("clipboard-timeout",{attempt=c.copies,beforeCount=copyBefore,
                currentCount=count,textType=type(raw),bytes=type(raw)=="string" and #raw or nil,
                contentTypes=types,elapsed=now()-copyStarted})
            if c.clipboardTimeouts>=2 then
                stopCollection(job.lastCopyProblem.." You can dismiss this message, click the reply's Copy button yourself, "
                    .."then use BT > Accept reviewed clipboard (Ctrl-Option-Cmd-M).")
            else scrollResponse(job.lastCopyProblem)end
        else
            -- A clipboard ownership change can precede delivery of its text.
            -- Keep polling without another click until data or the deadline.
            due=now()+0.25
        end
    elseif phase == "saved" then
        -- A final answer can finish even as its model's allowance is exhausted.
        -- Check the notice/model before turning away from its saved source.
        scanButtons(function(_,stopped,_,_,model)
            if not running then return end
            if stopped then pause("The chat is generating unexpectedly; no page turn was sent.")
            else setPhase("advance-ready") end
        end)
    elseif phase == "advance-ready" then
        -- Confirm the saved source is still visible before ONE forward click.
        local img, hash = capture()
        if hash ~= job.lastSourceHash then
            pause("Displayed page changed after saving. Do not auto-advance an uncertain position."); return
        end
        local wf=cal.windowFrame
        if cal.next.x<wf.x or cal.next.x>=cal.panel.x
            or cal.next.y<cal.panel.y or cal.next.y>wf.y+wf.h then
            pause("Forward target is outside the book pane. Use BT > Set forward click only."); return
        end
        startTurnTrace(img,hash)
        local focusError,focusEvidence
        turnFocus,focusError,focusEvidence=bookFocus.prepare(hs,cal,cfg.chromeBundle,now())
        turnTrace.bookFocus=focusEvidence
        if focusError then
            turnTrace.outcome="blocked-before-click";turnTrace.endedAt=now()
            atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
            pause(focusError.." No page click was sent.");return
        end
        setPhase("turn-focus",cfg.turnFocusPollSeconds)
    elseif phase == "turn-focus" then
        local focused,focusError=bookFocus.check(hs,cal,turnFocus,now())
        if not focused and (focusError or not turnFocus or now()-turnFocus.startedAt>=cfg.turnFocusTimeout) then
            turnTrace.outcome="blocked-before-click";turnTrace.endedAt=now()
            turnTrace.bookFocus.error=focusError or "Book focus did not become verifiable before its deadline."
            atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
            pause(turnTrace.bookFocus.error.." No page click was sent.");return
        end
        if not focused then setPhase("turn-focus",cfg.turnFocusPollSeconds);return end
        -- Focusing is not a page action. Verify that assumption before moving
        -- to the one forward click, even if a reader reacts to focus itself.
        local _,hash=capture()
        turnTrace.bookFocus.sourceHashAfterFocus=hash
        if hash~=job.lastSourceHash then
            turnTrace.outcome="blocked-before-click";turnTrace.endedAt=now()
            atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
            pause("The book image changed while focusing. No page click was sent.");return
        end
        -- Small, genuine movement near the target, then onto it. Never a
        -- speculative wake-up click: one extra click could skip a page.
        local wf=cal.windowFrame
        local dx=cal.next.x<(wf.x+cal.panel.x)/2 and 4 or -4
        movePointer({x=cal.next.x+dx,y=cal.next.y})
        setPhase("turn-hover")
    elseif phase == "turn-hover" then
        movePointer(cal.next)
        setPhase("turn",cfg.turnHoverSeconds)
    elseif phase == "turn" then
        if not turnTrace then pause("Missing turn state. Resume after checking the page."); return end
        local focused,focusError=bookFocus.check(hs,cal,turnFocus,now())
        if not focused then
            turnTrace.outcome="blocked-before-click";turnTrace.endedAt=now()
            turnTrace.bookFocus.error=focusError or "Focus moved away from the book before the click."
            atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
            pause(turnTrace.bookFocus.error.." No page click was sent.");return
        end
        if cfg.detailedTurnScreenshots then
            local hoverImage=capture()
            assert(hoverImage:saveToFile(turnTrace.folder.."/hover.png",true,"PNG"),"Cannot save hover image")
        end
        turnTrace.pointAfterHover=pointDescription(cal.next)
        local inputEvidence,inputError=turnInputGuard(cal.next)
        turnTrace.preClickGuard=inputEvidence
        if inputError then
            turnTrace.outcome="blocked-before-click"
            turnTrace.endedAt=now()
            atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
            pause(inputError);return
        end
        turnTrace.clicks=1
        turnTrace.clickIssuedAt=now()
        job.turnUncertain = true
        checkpoint() -- Write-ahead: recovery NEVER blindly issues another click.
        atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
        log("Sending ONE forward click after explicit mouse movement/hover.")
        turnTrace.clickCallStartedAt=now()
        hs.eventtap.leftClick(cal.next, cfg.turnClickHoldUS)
        -- Wrapper return is not a delivery acknowledgment from Chrome.
        turnTrace.clickCallReturnedAt=now()
        local pointer=hs.mouse.absolutePosition()
        turnTrace.pointerAfterClick={x=pointer.x,y=pointer.y}
        atomicWrite(turnTrace.folder.."/trace.json",hs.json.encode(turnTrace,true))
        turnFocus=nil
        setPhase("turn-release",cfg.postTurnDelay)
    elseif phase == "turn-release" then
        waitForPage(true)
    end
end

function M.selectProvider(id)
    local selected=providers.id(id)
    if not selected then return nil,"Unknown provider." end
    if selected==provider then return true end
    if running or recoveryActive or resumeCaptureEpoch==epoch or illustrationTask then
        warningNotice("Pause the job and wait for its active operation before changing providers.");return false
    end
    if quota.cancel then quota.cancel("Provider changed",false) end
    if job then checkpoint() end
    cancelScan();releaseOwnership();dismissNotice()
    -- Retain the old checkpoint and its provider-specific latest-job pointer.
    -- Switching providers never converts an existing pending request.
    provider=selected;hs.settings.set(settingKey..".provider",provider)
    cal=hs.settings.get(providerKey(".calibration"))
    job=nil;phase="idle";sessionWarning=nil;verifiedInput=nil
    calibrationStep,calibrationDraft,nextCalibration=nil,nil,nil
    refreshMenu()
    alert(providerName().." selected. Open its sidebar, calibrate, then create or restore a job.")
    return true
end
function M.currentProvider() return provider end
function M.calibrate()
    if running then pause("Paused for calibration.","paused") end
    if not hs.accessibilityState(true) then warningNotice("Enable Hammerspoon Accessibility permission first."); return end
    local w, err = chromeWindow()
    if not w then warningNotice(err); return end
    local prompts = {
        "Hover over the middle of "..providerName().."'s EMPTY input field; press this shortcut again.",
        "Hover over BOOKWALKER's FORWARD page-turn click target; press again. Verify the direction yourself.",
        "Hover at the TOP-LEFT of the book-content rectangle (no browser controls); press again.",
        "Hover at the BOTTOM-RIGHT of that rectangle (all page text, no chat pane); press again.",
        "Hover just INSIDE the TOP-LEFT of the "..providerName().." sidebar, below Chrome's toolbar; press again."
    }
    if not calibrationStep then
        calibrationStep = 1
        calibrationDraft = {provider=provider,windowID=w:id(), windowTitle=w:title(), windowFrame=plainFrame(w:frame()),
            screenID=w:screen():id()}
        alert(prompts[1]); return
    end
    if w:id() ~= calibrationDraft.windowID or not sameFrame(w:frame(), calibrationDraft.windowFrame) then
        calibrationStep = nil; warningNotice("Window changed during calibration. Start again."); return
    end
    local p = hs.mouse.absolutePosition()
    p = {x=p.x,y=p.y}
    if calibrationStep == 1 then calibrationDraft.input=p
    elseif calibrationStep == 2 then calibrationDraft.next=p
    elseif calibrationStep == 3 then calibrationDraft.topLeft=p
    elseif calibrationStep == 4 then
        local t = calibrationDraft.topLeft
        if p.x <= t.x+100 or p.y <= t.y+100 then warningNotice("Select a larger rectangle; bottom-right must be below/right."); return end
        calibrationDraft.crop={x=t.x,y=t.y,w=p.x-t.x,h=p.y-t.y}
    elseif calibrationStep == 5 then calibrationDraft.panel=p end
    calibrationStep = calibrationStep+1
    if calibrationStep <= 5 then alert(prompts[calibrationStep]); return end
    local draft = calibrationDraft
    calibrationStep, calibrationDraft = nil, nil
    local sf = hs.screen.find(draft.screenID):fullFrame()
    local r = draft.crop
    if not inRect({x=r.x,y=r.y},sf) or not inRect({x=r.x+r.w,y=r.y+r.h},sf)
       or draft.input.x <= draft.panel.x or r.x+r.w > draft.panel.x then
        warningNotice("Invalid geometry: crop must be on one display and entirely left of the chat pane. Recalibrate."); return
    end
    draft.topLeft=nil
    cal=draft
    hs.settings.set(providerKey(".calibration"), cal)
    hs.screenRecordingState(true)
    sessionWarning=nil;refreshMenu()
    alert("Calibrated. Allow screen capture if asked. Use BT > Preview source crop before starting.")
end
function M.calibrateNext()
    if running then pause("Paused to change the forward-click target.","paused") end
    dismissNotice()
    local w,err=guard(); if not w then warningNotice(err); return end
    if not nextCalibration then
        nextCalibration=true
        alert("Move the pointer over the book's actual FORWARD click target, then press Control-Option-Command-N. Do NOT click. Only this one target will change.")
        return
    end
    local p=hs.mouse.absolutePosition()
    local f=cal.windowFrame
    if p.x<f.x or p.x>=cal.panel.x or p.y<cal.panel.y or p.y>f.y+f.h then
        warningNotice("That point is outside the book pane. Hover over its forward target and press Control-Option-Command-N again.")
        return
    end
    cal.next={x=p.x,y=p.y}
    hs.settings.set(providerKey(".calibration"),cal)
    nextCalibration=nil
    log(string.format("Forward click updated to x=%.1f y=%.1f. Source crop and input calibration unchanged.",p.x,p.y))
    sessionWarning=nil;refreshMenu()
    alert("Forward target updated. No page was turned. Crop/input calibration and saved translations are unchanged.")
end
function M.dismissMessage() dismissNotice() end
function M.showLastMessage()
    if running or recoveryActive then pause(nil) end
    local reason=job and job.pauseReason
    local newest=type(lastNotice)=="table" and lastNotice
    if newest and (not job or not newest.folder or newest.folder==job.folder)
        and (not reason or (newest.atEpoch or 0)>=(job.pauseReasonAt or 0)) then
        reason="Recorded at "..tostring(newest.at).."\n"..newest.text
    end
    if not reason then alert("No saved pause message."); return end
    persistentNotice(reason,false)
end
function M.preview()
    if running then pause("Paused for source crop preview.","paused") end
    local w, err = guard(); if not w then warningNotice(err); return end
    if not hs.screenRecordingState(true) then return end
    mkdir(cfg.outputRoot)
    hs.alert.closeAll(0)
    defer(0.5,function()
        local current,why=guard(); if not current then warningNotice(why); return end
        local img = capture()
        local path=cfg.outputRoot .. "/calibration-preview.png"
        assert(img:saveToFile(path,true,"PNG"))
        openPath(path)
    end)
end
-- The book title comes from the guarded reader window. User-chosen titles are
-- remembered by exact source title, so a renamed book keeps its chosen name.
function M.defaultJobTitle(windowTitle)
    local source,err=jobNames.titleFromWindow(windowTitle)
    if not source then return nil,err end
    local aliases=hs.settings.get(settingKey..".bookTitles") or {}
    return jobNames.cleanTitle(type(aliases[source])=="string" and aliases[source] or source)
end
function M.newJob(batchSize,requestedTitle)
    if recoveryActive then pause("Recovery cancelled before New job.","paused") end
    if running then pause("Paused before creating another job.","paused") end
    local w, err = guard(); if not w then warningNotice(err); return end
    if not hs.screenRecordingState(true) then warningNotice("Allow screen capture, then try again."); return end
    local n=type(batchSize)=="number" and batchSize or nil
    if not n then
        local button, value = hs.dialog.textPrompt("New book-translation job",
            "CREATE A SEPARATE JOB starting at screen 00001, not a continuation. To continue an existing book, Cancel and use Restore latest saved job. New batch size (screens/spreads):",
            tostring(cfg.defaultBatch), "Create", "Cancel")
        if button ~= "Create" then return end
        n=tonumber(value)
    end
    if not n or n<1 or n>1000 or n~=math.floor(n) then warningNotice("Enter a whole number from 1 to 1000."); return end
    mkdir(cfg.outputRoot)
    local createdAt=os.time()
    local title=type(requestedTitle)=="string" and requestedTitle or M.defaultJobTitle(w:title())
    if not title then
        local button,value=hs.dialog.textPrompt("Book title","Name this book for its saved folder:","","Create","Cancel")
        if button~="Create" then return end
        title=value
    end
    local folder,cleanTitle=jobNames.folderFor(cfg.outputRoot,title,exists)
    if not folder then warningNotice(cleanTitle);return end
    -- mkdir itself must succeed: never reuse a folder created after planning.
    local made,makeError=hs.fs.mkdir(folder)
    if not made then warningNotice("Cannot create the book folder: "..tostring(makeError));return end
    mkdir(folder.."/sources"); mkdir(folder.."/pages"); mkdir(folder.."/responses")
    -- IDs do not depend on the editable folder name. UUID disambiguates jobs
    -- created in the same second with different titles.
    local tag=string.format("B%X",createdAt).."-"..hs.host.uuid():gsub("-",""):sub(1,8)
    job={folder=folder,folderName=folder:match("([^/]+)$"),bookTitle=cleanTitle,
        sourceWindowTitle=w:title(),createdAt=os.date("!%Y-%m-%dT%H:%M:%SZ",createdAt),
        tag=tag,records={},remaining=n,needAdvance=false,provider=provider,requestMode=provider=="chatgpt" and "inline" or cfg.defaultRequestMode}
    hs.settings.set(providerKey(".latest"),folder)
    phase="idle";sessionWarning=nil;checkpoint()
    w:focus()
    -- Delay gives the textPrompt window time to disappear before guard/capture.
    defer(0.6, M.resume)
end
function M.resume(origin)
    if quota.cancel then quota.cancel("Manual Start/resume",false) end
    if recoveryActive then pause("Recovery cancelled by Start/resume. Prepare a fresh source review before approving it.","paused"); return end
    if running then return end
    if resumeCaptureEpoch==epoch then return end
    nextCalibration=nil
    dismissNotice()
    hs.alert.closeAll(0)
    local manualResume=origin~="scheduled"
    defer(0.05, function() resumeNow(manualResume) end)
end
resumeNow = function(manualResume)
    if running then return end
    if resumeCaptureEpoch==epoch then return end
    if not job then
        -- Start/resume must never create a separate book after a reload or
        -- missing checkpoint. Restore and stay paused for position review.
        M.restoreLatest()
        return
    end
    local w, err=guard(); if not w then pause(err); return end
    if not hs.screenRecordingState(true) then pause("Screen Recording permission is required to resume this book.");return end
    if job.remaining == 0 then
        local b,s=hs.dialog.textPrompt("Continue this book","Additional screens/spreads in the next batch:",tostring(cfg.defaultBatch),"Continue","Cancel")
        if b~="Continue" then return end
        local n=tonumber(s)
        if not n or n<1 or n>1000 or n~=math.floor(n) then pause("Enter 1–1000."); return end
        job.remaining=n; w:focus(); checkpoint()
        defer(0.6, M.resume); return
    end
    resumeCaptureEpoch=epoch;refreshMenu()
    local expectedHash=job.pending and job.pending.sourceHash
        or (job.needAdvance and not job.turnUncertain and job.lastSourceHash)
    stableSourceCapture("Resume source check",function() return not running end,function(_,hash)
    resumeCaptureEpoch=nil;refreshMenu()
    if job.pending and hash~=job.pending.sourceHash then
        pause("Return to the pending source page shown in the job's sources folder before resuming."); return
    end
    if job.turnUncertain and not job.pending then
        if hash==job.lastSourceHash then
            local b=hs.dialog.blockAlert("Retry one forward click?",
                "The image still matches saved screen "..string.format("%05d",#job.records)..". "
                .."Confirm the reader is idle and this is the SAME last saved screen, not a later page. "
                .."Retry once authorizes ONE new forward click. Cancel makes no change.",
                "Cancel","Retry once")
            w:focus()
            if b~="Retry once" then return end
            job.turnUncertain,job.needAdvance=false,true
            log("User approved one retry from the matching last saved screen.")
            checkpoint()
            -- Do not capture while the confirmation dialog is disappearing.
            defer(0.7,M.resume)
            return
        end
        local b=hs.dialog.blockAlert("Verify the page position",
            "A page turn was interrupted. Is the displayed screen exactly the next screen after the last saved source? "
            .."Use current screen will translate it WITHOUT clicking forward again.",
            "Cancel","Use current screen")
        w:focus()
        if b~="Use current screen" then return end
        job.turnUncertain,job.needAdvance=false,false
        log("User confirmed current screen is the next source; no recovery click will be sent.")
        checkpoint()
        defer(0.7,M.resume)
        return
    elseif job.needAdvance and hash~=job.lastSourceHash then
        pause("The current image differs from the last saved source. If this is the same page, use BT > Review last saved source. No page turn was sent."); return
    end
    quota.manualResumeEpoch=manualResume and epoch or nil
    running=true; job.pauseReason=nil;job.pauseKind=nil;sessionWarning=nil;beginOwnership()
    responseCandidate,responseSince=nil,nil
    collection,responseScrollPoint,copyTarget,copyClipboardState=nil,nil,nil,nil
    verifiedInput=nil
    inputReadback=nil
    pasteInFlight=false
    skillFlow=nil
    inputWaitPhase,inputWaitStarted,inputReclicked=nil,nil,false
    if job.pending then
        if job.pending.sent then
            job.pending.sentAt=now() -- Fresh wait budget; never resend automatically.
            setPhase("wait")
        else setPhase("preflight") end
    elseif job.needAdvance then setPhase("saved")
    else waitForPage(false) end
    checkpoint()
    log("Resumed; remaining screens in batch: " .. job.remaining)
    end,function(reason)
        resumeCaptureEpoch=nil
        pause(reason)
    end,expectedHash)
end
-- Explicit batch count for authorized programmatic continuations. The regular
-- Start/resume menu keeps its prompt; neither path changes the source guards.
function M.configureEvaluationRun(config)
    if provider~="gemini" then return nil,"This saved comparison mode is for Gemini Flash and Flash-Lite." end
    if running or recoveryActive or resumeCaptureEpoch==epoch or not job or job.pending then
        return nil,"Load and pause a job with no pending response before configuring a comparison."
    end
    if type(config)~="table" or type(config.id)~="string" or not config.id:match("^[%w_-]+$")
        or (config.modelKey~="flash-lite" and config.modelKey~="flash")
        or config.startIndex~=#job.records+1 or config.endIndex~=config.startIndex+19 then
        return nil,"Provide a comparison ID, Flash/Flash-Lite model key, and exactly the next twenty indices."
    end
    local expected
    if config.expectedSourceHashes~=nil then
        if type(config.expectedSourceHashes)~="table" then return nil,"Expected source hashes must map all twenty indices to screenshot fingerprints." end
        expected={}
        for key,hash in pairs(config.expectedSourceHashes)do
            local index=tonumber(key)
            if not index or index~=math.floor(index) or index<config.startIndex or index>config.endIndex
                or (type(key)~="number" and key~=tostring(index))
                or type(hash)~="string" or #hash~=64 or not hash:match("^[0-9a-fA-F]+$") then
                return nil,"Expected source hashes contain an invalid index or fingerprint."
            end
            local slot=tostring(index)
            hash=hash:lower()
            if expected[slot] and expected[slot]~=hash then return nil,"Expected source hashes conflict for screen "..slot.."." end
            expected[slot]=hash
        end
        for index=config.startIndex,config.endIndex do
            if not expected[tostring(index)] then return nil,"Missing expected source hash for screen "..index.."." end
        end
    end
    job.evaluationRun={active=true,id=config.id,modelKey=config.modelKey,
        startIndex=config.startIndex,endIndex=config.endIndex,configuredAt=now(),
        expectedSourceHashes=expected}
    checkpoint()
    return pageModels.copy(job.evaluationRun)
end
function M.continueBatch(count)
    if type(count)~="number" or count<1 or count>1000 or count~=math.floor(count) then
        return nil,"Enter a whole number from 1 to 1000."
    end
    if not job then return nil,"Restore the book before continuing." end
    if running or recoveryActive or resumeCaptureEpoch==epoch then return nil,"A run or review is already in progress." end
    if job.remaining~=0 or job.pending or job.turnUncertain then return nil,"Finish or review the current batch first." end
    local w,err=guard();if not w then return nil,err end
    job.remaining=count;checkpoint()
    M.resume()
    return {folder=job.folder,remaining=count,savedCount=#job.records}
end

function M.togglePause()
    if running then pause("Paused. Gemini itself may still finish its reply.","paused") else M.resume() end
end
function M.stop() pause("Automation stopped. Saved files retained; resume is available.","paused") end
local function retryNow()
    if running then pause("Paused for retry.","paused") end
    if not job then alert("No job is loaded. Choose BT > Restore latest saved job, then retry.");return end
    if not job.pending then alert("This loaded job has no pending screen. Use BT > Status to inspect it."); return end
    local w,err=guard(); if not w then warningNotice(err); return end
    if not pendingSourceStillVisible() then warningNotice("Return to the pending source page first."); return end
    local b=hs.dialog.blockAlert("Retry this screen?",
        "First stop/wait for any Gemini generation and empty its input. This creates a NEW request ID without turning the page.",
        "Cancel","Retry")
    w:focus()
    if b~="Retry" then return end
    if job.pending.sent then
        job.priorSentReply={id=job.pending.id,index=job.pending.index,
            sourceHash=job.pending.sourceHash,provider=provider,modelAtSubmit=job.pending.modelAtSubmit,
            modelProvenance=pageModels.copy(job.pending.modelProvenance),
            sentAt=job.pending.sentAt}
    end
    job.pending.id=job.tag.."-"..string.format("%05d",job.pending.index).."-r"..os.time()
    job.pending.sent=false
    job.pending.sentAt=nil
    job.pending.modelAtSubmit=nil;job.pending.modelProvenance=nil
    job.pending.composerPrefix=nil
    job.pending.selectionVerified=nil
    job.pending.selectionEvidence=nil
    job.pending.skillSelectionAttemptedAt=nil
    job.pending.requestText=nil
    job.pending.pasteAttemptedAt=nil
    job.pending.inputMode=nil
    inputReadback=nil
    pasteInFlight=false
    checkpoint()
    defer(0.6, M.resume)
end
function M.retry()
    if recoveryActive then pause("Recovery cancelled before retry.","paused") end
    if running then pause("Paused for retry.","paused") end
    dismissNotice(); hs.alert.closeAll(0)
    defer(0.5,retryNow)
end
-- Human-selected fallback: the user explicitly confirms the blue ln chip in
-- the CURRENT composer. No slash, selection Enter, or automatic deletion is
-- sent. Focus, empty/chip-only draft, source image, full-request readback and
-- response validation are still required. Only unsent pending work is eligible.
-- Explicit optional recovery: use a local copy of the same book instructions as
-- a normal Gemini message. This is NOT a /ln skill invocation or an API call.
-- Recovery is a human-authorized replacement of ONLY an UNSENT pending
-- source reference. It is not an automatic fuzzy match or disabled guard.
-- Everything needed to reverse the source/checkpoint edit is backed up first.
stableSourceCapture = function(label, active, done, failed, expectedHash)
    local started=now()
    local candidate,since,samples,lastImage=nil,nil,0,nil
    local w,err=guard()
    if not w then failed(label..": "..err);return end
    movePointer(cal.input) -- Move only; remove book hover controls without clicking.
    local function poll()
        if not active() then return end
        local w,err=guard()
        if not w then failed(label..": "..err,lastImage,candidate);return end
        local img,hash=capture()
        lastImage=img
        -- Only resuming a known source gets this shortcut. Unfamiliar pages,
        -- uncertain turns and all source-reference reviews still stabilize.
        -- Advance and Send each take another fresh source capture before acting.
        if expectedHash and hash==expectedHash then done(img,hash,1);return end
        if hash~=candidate then candidate,since,samples=hash,now(),1
        else samples=samples+1 end
        if samples>=3 and now()-since>=1.2 then done(img,hash,samples);return end
        if now()-started>=12 then
            failed(label..": source did not stay still; nothing was sent or advanced.",img,hash)
            return
        end
        defer(0.4,poll)
    end
    defer(expectedHash and 0.05 or 0.4,poll)
end
local function recoveryStableCapture(label,done,failed)
    return stableSourceCapture(label,function() return recoveryActive end,done,failed)
end
-- An explicit reviewed repair, never an automatic retry policy. It accepts
-- only a failed ONE-click trace that continuously retained the exact saved
-- source, then rechecks that source before authorizing one new normal turn.
local unchangedTurnRetry
local function unchangedTurnRetryProblem(evidence,trace)
    if not job or type(job.records)~="table" or #job.records<1 then return "Load a saved book first." end
    if running or recoveryActive or resumeCaptureEpoch==epoch then return "Pause the current operation before reviewing a failed turn." end
    if job.turnUncertain~=true or job.needAdvance~=true or job.pending then
        return "This repair requires one uncertain forward turn with no pending response."
    end
    if type(job.remaining)~="number" or job.remaining<1 then return "There are no remaining screens in this batch." end
    if type(evidence)~="table" or type(evidence.reviewedBy)~="string" or not evidence.reviewedBy:match("%S")
        or type(evidence.notes)~="string" or not evidence.notes:match("%S") then
        return "Provide explicit reviewed-turn evidence and who reviewed it."
    end
    local last=job.records[#job.records]
    if type(last)~="table" or type(last.id)~="string" or last.id==""
        or type(evidence.sourceHash)~="string" or evidence.sourceHash==""
        or evidence.expectedRecordID~=last.id or evidence.sourceHash~=job.lastSourceHash
        or type(evidence.turnFolder)~="string" or evidence.turnFolder~=job.lastTurnFolder then
        return "The reviewed record, source hash or failed turn does not match this job."
    end
    if type(trace)~="table" or trace.folder~=evidence.turnFolder or trace.afterScreen~=#job.records
        or trace.nextScreen~=#job.records+1 or trace.clicks~=1 or trace.outcome~="failed-to-verify"
        or trace.sourceHash~=evidence.sourceHash or trace.finalHash~=evidence.sourceHash
        or trace.finalMatchesSaved~=true or trace.changedSamples~=0 or trace.transitions~=0
        or type(trace.sameSamples)~="number" or trace.sameSamples<2
        or type(trace.samples)~="table" or #trace.samples~=trace.sameSamples then
        return "The trace does not prove one failed click with an unchanged saved source."
    end
    for _,sample in ipairs(trace.samples)do
        if sample.hash~=evidence.sourceHash or sample.sameAsSaved~=true then
            return "The failed-turn trace contains a changed or unverified source sample."
        end
    end
end
function M.turnRetryState()
    if not unchangedTurnRetry then return nil end
    local state=hs.json.decode(hs.json.encode(unchangedTurnRetry))
    if state.status=="checking" and state.epoch~=epoch then state.status="cancelled" end
    return state
end
function M.retryUnchangedTurn(evidence)
    local tracePath=job and job.lastTurnFolder and (job.lastTurnFolder.."/trace.json")
    local rawTrace=tracePath and readFile(tracePath)
    local decoded,trace=pcall(hs.json.decode,rawTrace or "")
    local problem=unchangedTurnRetryProblem(evidence,decoded and trace or nil)
    if problem then return nil,problem end
    local w,err=guard();if not w then return nil,err end
    local checkpointBefore=readFile(job.folder.."/checkpoint.json")
    if not checkpointBefore then return nil,"Cannot back up the checkpoint before reviewed retry." end
    evidence=hs.json.decode(hs.json.encode(evidence))
    local reviewedJob,snapshot=job,sourcePolicy.snapshot(job)
    cancelScan();dismissNotice();hs.alert.closeAll(0)
    local base=job.folder.."/recovery/unchanged-turn-"..string.format("%05d-",#job.records)
        ..os.date("%Y%m%d-%H%M%S")
    local folder,suffix=base,0
    while exists(folder)do suffix=suffix+1;folder=base.."-"..suffix end
    mkdir(folder)
    atomicWrite(folder.."/checkpoint-before.json",checkpointBefore)
    atomicWrite(folder.."/failed-turn-before.json",rawTrace)
    unchangedTurnRetry={status="checking",folder=folder,epoch=epoch,evidence=evidence,
        createdAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),savedCount=#job.records,
        remaining=job.remaining,originalTurnFolder=job.lastTurnFolder,version=M.version}
    local receipt=unchangedTurnRetry
    local function writeReceipt()atomicWrite(folder.."/review.json",hs.json.encode(receipt,true))end
    local function failed(reason,img,hash)
        receipt.status="stopped";receipt.error=reason;receipt.finalHash=hash
        if img then img:saveToFile(folder.."/stopped-source.png",true,"PNG")end
        writeReceipt();pause("Reviewed turn retry stopped: "..reason)
    end
    writeReceipt();recoveryActive=true;setPhase("reviewed-turn-retry")
    recoveryStableCapture("Reviewed unchanged source",function(img,hash,samples)
        if job~=reviewedJob or sourcePolicy.snapshot(job)~=snapshot or readFile(tracePath)~=rawTrace
            or job.lastTurnFolder~=evidence.turnFolder then
            failed("The job or failed-turn evidence changed during review.",img,hash);return
        end
        if hash~=evidence.sourceHash then
            failed("The current source does not exactly match the reviewed saved page. No retry was authorized.",img,hash);return
        end
        assert(img:saveToFile(folder.."/reviewed-source.png",true,"PNG"),"Cannot preserve reviewed retry source")
        receipt.status="approved";receipt.stableHash=hash;receipt.stableSamples=samples
        receipt.approvedAt=os.date("!%Y-%m-%dT%H:%M:%SZ")
        writeReceipt() -- Persist the explicit authorization before state changes.
        local oldPauseAfterNext,oldRetryFolder=job.pauseAfterNext,job.lastTurnRetryFolder
        job.turnUncertain=false;job.needAdvance=true;job.pauseAfterNext=true
        job.lastTurnRetryFolder=folder
        setPhase("reviewed-turn-retry-approved")
        local saved,saveError=pcall(checkpoint)
        if not saved then
            job.turnUncertain=true;job.pauseAfterNext=oldPauseAfterNext;job.lastTurnRetryFolder=oldRetryFolder
            failed("Could not persist retry authorization: "..tostring(saveError),img,hash);return
        end
        recoveryActive=false
        log("Explicit review authorized ONE forward retry from unchanged saved screen "..#job.records
            .."; the original failed trace is retained. Pause after the next saved screen.")
        M.resume("manual")
    end,failed)
    return {status="checking",folder=folder,savedCount=#job.records,targetCount=#job.records+1}
end
-- Inspect and refresh the navigation reference for an ALREADY SAVED page.
-- The archived source image, translation, record hash and batch size are never
-- rewritten. Programmatic approval requires the exact prepared review plus
-- explicit visual-review evidence; merely capturing the page is not approval.
local savedSourceReviewCommit
local function prepareSavedSourceReview(onReady)
    if running or recoveryActive then return nil,"Pause the current operation before reviewing a saved source." end
    local problem=sourcePolicy.problem(job)
    if problem then return nil,problem end
    cancelScan()
    dismissNotice();hs.alert.closeAll(0)
    savedSourceReviewCommit=nil
    local reviewedJob=job
    local review={status="preparing",epoch=epoch,snapshot=sourcePolicy.snapshot(job),
        savedCount=#job.records,recordID=job.records[#job.records].id,
        originalSourceHash=job.records[#job.records].sourceHash,oldHash=job.lastSourceHash,
        createdAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),version=M.version}
    savedSourceReview=review
    recoveryActive=true
    local sourcePath=job.folder..string.format("/sources/%05d.png",#job.records)
    local sourceBefore,checkpointBefore=readFile(sourcePath),readFile(job.folder.."/checkpoint.json")
    local function report()
        if review.folder then atomicWrite(review.folder.."/review.json",hs.json.encode(review,true)) end
    end
    local function fail(reason,img,hash)
        review.status="stopped";review.error=reason;review.finalHash=hash
        if img and review.folder then img:saveToFile(review.folder.."/stopped-source.png",true,"PNG") end
        report();pause("Saved-source review stopped: "..reason)
    end
    if not sourceBefore or not checkpointBefore then
        fail("The archived source or checkpoint could not be backed up.")
        return nil,review.error
    end
    local base=job.folder.."/recovery/saved-"..string.format("%05d-",#job.records)..os.date("%Y%m%d-%H%M%S")
    review.folder=base
    local suffix=0
    while exists(review.folder) do suffix=suffix+1;review.folder=base.."-"..suffix end
    mkdir(review.folder)
    atomicWrite(review.folder.."/source-original.png",sourceBefore)
    atomicWrite(review.folder.."/checkpoint-before.json",checkpointBefore)
    setPhase("saved-source-review");report()
    recoveryStableCapture("Saved source before review",function(img,hash,samples)
        if job~=reviewedJob or sourcePolicy.snapshot(job)~=review.snapshot then
            fail("The job changed while the review was being prepared.",img,hash);return
        end
        assert(img:saveToFile(review.folder.."/current-source.png",true,"PNG"),"Cannot save current source review")
        review.candidateHash=hash;review.beforeSamples=samples;review.status="ready"
        review.originalPath=review.folder.."/source-original.png"
        review.currentPath=review.folder.."/current-source.png"
        atomicWrite(review.folder.."/compare.html",[[<!doctype html><meta charset="utf-8">
<title>Saved book source review</title><style>body{font:18px system-ui;margin:24px}main{display:flex;gap:20px}figure{margin:0;flex:1}img{width:100%;border:1px solid #888}</style>
<h1>Verify the same saved book page</h1><p>Compare every visible text column and page number. No page turn or translation request has been sent.</p>
<main><figure><figcaption>Original archived source (preserved)</figcaption><img src="source-original.png"></figure>
<figure><figcaption>Current source to review</figcaption><img src="current-source.png"></figure></main>]])
        report();recoveryActive=false;setPhase("saved-source-review-ready")
        log("Saved-source comparison ready: "..review.folder.."; no reference changed or page turned.")
        savedSourceReviewCommit=function(evidence)
            if running or recoveryActive then return nil,"Another operation is active." end
            if review~=savedSourceReview or review.epoch~=epoch or job~=reviewedJob then
                return nil,"The prepared review was cancelled or superseded; prepare another review."
            end
            local why=sourcePolicy.approvalProblem(review,job,evidence)
            if why then return nil,why end
            -- Freeze caller-supplied evidence before the asynchronous check.
            evidence=hs.json.decode(hs.json.encode(evidence))
            local w,err=guard();if not w then return nil,err end
            dismissNotice();hs.alert.closeAll(0);recoveryActive=true
            setPhase("saved-source-review-verify")
            recoveryStableCapture("Saved source after review",function(current,currentHash,count)
                if job~=reviewedJob or readFile(sourcePath)~=sourceBefore then
                    fail("The archived source or loaded job changed after review.",current,currentHash);return
                end
                local invalid=sourcePolicy.approvalProblem(review,job,evidence)
                if invalid then fail(invalid,current,currentHash);return end
                if currentHash~=review.candidateHash then
                    fail("The visible source changed after review; no navigation reference was replaced.",current,currentHash);return
                end
                assert(current:saveToFile(review.folder.."/approved-source.png",true,"PNG"),"Cannot save approved navigation source")
                local at=os.date("!%Y-%m-%dT%H:%M:%SZ")
                -- Persist reviewed evidence before changing navigation state.
                atomicWrite(review.folder.."/approval.json",hs.json.encode({evidence=evidence,
                    approvedAt=at,stableHash=currentHash,afterSamples=count},true))
                local oldNavigation=job.navigationReference
                local ok,applyError=sourcePolicy.apply(review,job,evidence,currentHash,at)
                if not ok then fail(applyError,current,currentHash);return end
                setPhase("saved-source-reviewed")
                local written,writeError=pcall(checkpoint)
                if not written then
                    job.lastSourceHash=review.oldHash;job.navigationReference=oldNavigation
                    fail("Cannot save the refreshed navigation checkpoint: "..tostring(writeError),current,currentHash);return
                end
                review.status="approved";review.afterSamples=count;review.approvedAt=at
                review.reviewedBy=evidence.reviewedBy;review.notes=evidence.notes
                report();recoveryActive=false;setPhase("saved-source-reviewed")
                log("Reviewed saved screen "..review.savedCount.."; navigation reference refreshed. Archived source and translation retained; no page turn sent.")
            end,fail)
            return {status="verifying",folder=review.folder}
        end
        if onReady then onReady(review) end
    end,fail)
    return {status="preparing",folder=review.folder}
end
function M.prepareSavedSourceReview() return prepareSavedSourceReview() end
function M.approveSavedSourceReview(evidence)
    if not savedSourceReviewCommit then return nil,"Prepare and visually inspect a saved-source review first." end
    return savedSourceReviewCommit(evidence)
end
function M.reviewLastSavedSource()
    local result,why=prepareSavedSourceReview(function(review)
        local w,err=guard();if not w then pause(err);return end
        local button=hs.dialog.blockAlert("Review last saved source",
            "Saved screen "..review.savedCount.." has already been translated. The original and current images are in:\n"
            ..review.folder.."\n\nConfirm ONLY after visually checking that the reader shows the SAME saved page, with all text visible. "
            .."If unsure, Cancel and open compare.html in that folder. This changes only the navigation reference. "
            .."The original source and translation remain preserved, and no page turn is sent.","Cancel","Same saved page")
        w:focus()
        if button~="Same saved page" then
            review.status="cancelled";atomicWrite(review.folder.."/review.json",hs.json.encode(review,true))
            pause("Saved-source review cancelled. No navigation reference or page was changed.","paused");return
        end
        local accepted,problem=M.approveSavedSourceReview({savedCount=review.savedCount,
            recordID=review.recordID,oldHash=review.oldHash,candidateHash=review.candidateHash,
            reviewedBy="User",notes="Confirmed the current reader shows the same last saved page with all text visible."})
        if not accepted then pause(problem) end
    end)
    if not result then warningNotice(why) end
end
function M.uiState()return uiState()end
function M.sourceState()
    local last=job and job.records[#job.records]
    local state={version=M.version,phase=phase,running=running,recoveryActive=recoveryActive,
        uiStatus=uiState().kind,progress=jobStatus.progress(job),epub=epubManager:state(job and job.folder),pauseKind=job and job.pauseKind,
        readiness=readinessStats,
        folder=job and job.folder,bookTitle=job and job.bookTitle,folderName=job and job.folderName,
        sourceWindowTitle=job and job.sourceWindowTitle,savedCount=job and #job.records,remaining=job and job.remaining,
        needAdvance=job and job.needAdvance,turnUncertain=job and job.turnUncertain,
        pauseAfterNext=job and job.pauseAfterNext,pauseReason=job and job.pauseReason,
        lastSourceHash=job and job.lastSourceHash,lastRecordID=last and last.id,
        originalSourceHash=last and last.sourceHash,review=savedSourceReview,
        navigationReference=job and job.navigationReference,pending=job and job.pending}
    return hs.json.decode(hs.json.encode(state)) -- Detached, read-only diagnostics.
end
function M.runNextOne()
    if running or recoveryActive then return nil,"Pause the current operation first." end
    local problem=sourcePolicy.problem(job);if problem then return nil,problem end
    if not job.remaining or job.remaining<1 then return nil,"This batch has no remaining screens. Add a batch through Start/resume first." end
    job.pauseAfterNext=true;checkpoint()
    M.resume("manual")
    return {status="starting",savedCount=#job.records,targetCount=#job.records+1,remaining=job.remaining}
end
function M.retryInlineOne()
    if running then pause("Paused before direct-prompt recovery.","paused") end
    if not job and not M.restoreLatest() then return end
    cancelScan()
    dismissNotice();hs.alert.closeAll(0)
    recoveryActive=true
    local reviewedJob,reviewedID,recoveryFolder,report
    local function fail(reason,img,hash)
        if report and recoveryFolder then
            report.result="stopped";report.error=reason;report.finalHash=hash
            if img then img:saveToFile(recoveryFolder.."/stopped-source.png",true,"PNG") end
            atomicWrite(recoveryFolder.."/review.json",hs.json.encode(report,true))
        end
        -- Unlike the old alert-only branch, this updates the checkpoint, log,
        -- last-pause.json and Show last pause/error, even before a run starts.
        pause("Recovery stopped: "..reason)
    end
    local function unchangedPending()
        return job==reviewedJob and job.pending and job.pending.id==reviewedID
            and job.pending.sent==false and job.pending.index==#job.records+1
    end
    defer(0.7,function()
        if not job then fail("No saved job loaded. Nothing was created or sent.");return end
        local problem=core.pendingRecoveryProblem(job)
        if problem then fail(problem);return end
        local w,err=guard();if not w then fail(err);return end
        local instructions=readFile(cfg.promptFile)
        if not instructions or #core.trim(instructions)<100 then
            fail("Missing translation instructions: "..cfg.promptFile);return
        end
        local sourcePath=job.folder..string.format("/sources/%05d.png",job.pending.index)
        local sourceBefore=readFile(sourcePath)
        local checkpointBefore=readFile(job.folder.."/checkpoint.json")
        if not sourceBefore or not checkpointBefore then
            fail("Cannot back up the existing pending source/checkpoint. No changes made.");return
        end
        reviewedJob,reviewedID=job,job.pending.id
        local base=job.folder.."/recovery/"..string.format("%05d-",job.pending.index)
            ..os.date("%Y%m%d-%H%M%S")
        recoveryFolder=base
        local suffix=0
        while exists(recoveryFolder) do suffix=suffix+1;recoveryFolder=base.."-"..suffix end
        mkdir(recoveryFolder)
        atomicWrite(recoveryFolder.."/source-before.png",sourceBefore)
        atomicWrite(recoveryFolder.."/checkpoint-before.json",checkpointBefore)
        report={version=M.version,createdAt=os.date("%Y-%m-%d %H:%M:%S"),
            pendingIndex=job.pending.index,oldRequestID=reviewedID,
            oldHash=job.pending.sourceHash,saved=#job.records,remaining=job.remaining,
            originalCalibration=cal,result="checking",initialPageTurns=0}
        job.lastRecoveryFolder=recoveryFolder
        setPhase("recovery-source-review")
        -- Do not overwrite the pending image or reference hash at this point.
        log("Recovery source review started; backup: "..recoveryFolder)
        recoveryStableCapture("Before confirmation",function(img,hash,samples)
            if not unchangedPending() then fail("Pending job changed during recovery.",img,hash);return end
            assert(img:saveToFile(recoveryFolder.."/current-before-confirmation.png",true,"PNG"),
                "Cannot save current source for recovery review")
            report.candidateHash=hash;report.beforeSamples=samples
            report.exactMatch=(hash==report.oldHash)
            report.result="awaiting-confirmation"
            atomicWrite(recoveryFolder.."/review.json",hs.json.encode(report,true))
            atomicWrite(recoveryFolder.."/compare.html",[[<!doctype html><meta charset="utf-8">
<title>Pending-source recovery comparison</title><style>body{font:18px system-ui;margin:24px}
main{display:flex;gap:20px}figure{margin:0;flex:1}img{width:100%;border:1px solid #888}</style>
<h1>Compare the book content, not just whitespace</h1>
<p>No request or page turn occurs merely by opening this file. Return to the original book tab.</p>
<main><figure><figcaption>Saved reference before recovery</figcaption><img src="source-before.png"></figure>
<figure><figcaption>Current capture before confirmation</figcaption><img src="current-before-confirmation.png"></figure></main>]])
            log("Recovery source reference: exact-match="..tostring(report.exactMatch)
                .."; old="..report.oldHash.."; current="..hash)
            local explanation=report.exactMatch
                and "The current capture exactly matches the saved reference. "
                or "The current capture differs from the old image fingerprint. That alone does NOT prove a page turn. "
            local button=hs.dialog.blockAlert("Confirm pending book page",
                "This job has "..#job.records.." saved screens and "..job.remaining.." remaining. "
                .."Pending screen: "..string.format("%05d",job.pending.index).." (UNSENT).\n\n"
                ..explanation.."Continue ONLY if the reader is still on the SAME book page as the pending reference, "
                .."with all its text visible and no popup covering it. Do not approve a later or previous page. "
                .."If unsure, Cancel and compare the two images in the job's latest recovery folder.\n\n"
                .."Confirm the chat is idle and its input contains no draft or skill chip. "
                .."This backs up the old source, refreshes ONLY this pending screen's reference, "
                .."and tests ONE direct-prompt translation. Previously saved translations are untouched. "
                .."No initial page turn or API call. The rest of the batch stays paused.",
                "Cancel","Same page - test one")
            w:focus()
            if button~="Same page - test one" then
                report.result="cancelled";atomicWrite(recoveryFolder.."/review.json",hs.json.encode(report,true))
                pause("Recovery cancelled. No reference, request, or book page was changed.","paused");return
            end
            dismissNotice();hs.alert.closeAll(0)
            -- Recheck AFTER the confirmation dialog closes. It must still be
            -- the reviewed current capture, not an arbitrarily recaptured page.
            defer(0.8,function()
                recoveryStableCapture("After confirmation",function(current,currentHash,count)
                    if not unchangedPending() then fail("Pending job changed before approval was applied.",current,currentHash);return end
                    if currentHash~=hash then
                        fail("The source changed after your confirmation. No reference was replaced and no request was sent. See the recovery images.",current,currentHash)
                        return
                    end
                    assert(current:saveToFile(recoveryFolder.."/approved-source.png",true,"PNG"),
                        "Cannot save approved source")
                    local sourceTemp=sourcePath..".recovery.tmp"
                    assert(current:saveToFile(sourceTemp,true,"PNG"),"Cannot stage approved source")
                    assert(os.rename(sourceTemp,sourcePath),"Cannot replace pending source")
                    local p=job.pending
                    p.id=job.tag.."-"..string.format("%05d",p.index).."-r"..os.time().."-"..suffix
                    p.sourceHash=currentHash
                    p.sent=false;p.sentAt=nil;p.composerPrefix=nil;p.selectionVerified=nil
                    p.modelAtSubmit=nil;p.modelProvenance=nil
                    p.selectionEvidence=nil;p.skillSelectionAttemptedAt=nil
                    p.requestText=nil;p.pasteAttemptedAt=nil;p.inputMode=nil
                    job.requestMode="inline";job.pauseAfterNext=true
                    job.needAdvance=false;job.expectChange=false;job.turnUncertain=false
                    job.pauseReason=nil;job.pauseReasonAt=nil
                    verifiedInput=nil;inputReadback=nil;pasteInFlight=false;skillFlow=nil
                    report.result="approved";report.afterSamples=count;report.newHash=currentHash
                    report.newRequestID=p.id;report.userConfirmedSamePage=true
                    atomicWrite(recoveryFolder.."/review.json",hs.json.encode(report,true))
                    setPhase("recovery-approved");checkpoint()
                    log("User confirmed same pending page; reference refreshed with backup. "
                        .."Testing ONE direct-prompt translation; no initial page turn.")
                    recoveryActive=false
                    M.resume()
                end,fail)
            end)
        end,fail)
    end)
end
function M.continueSelectedSkill()
    if provider=="chatgpt" then warningNotice("ChatGPT uses direct prompts; no skill selection is needed.");return end
    if recoveryActive then pause("Recovery cancelled before manual-skill recovery.","paused") end
    if running then pause("Paused for manual skill selection.","paused")end
    dismissNotice();hs.alert.closeAll(0)
    defer(0.5,function()
        if not job then alert("No job is loaded. Choose BT > Restore latest saved job first.");return end
        if not job.pending then alert("The loaded job has no pending screen. Use BT > Status.");return end
        if job.pending.sent then alert("This pending request was already marked sent. Use Start/resume to collect it, not manual selection.");return end
        local w,err=guard();if not w then warningNotice(err);return end
        if not pendingSourceStillVisible()then warningNotice("Return to the pending source page before continuing.");return end
        local b=hs.dialog.blockAlert("Continue with selected ln skill?",
            "Confirm that the blue ln skill chip is selected in the CURRENT Gemini message box (not just an earlier chat message), "
            .."that there is no draft text, and that Gemini is idle. This will paste and submit ONE request for the current pending screen, "
            .."then continue the remaining batch. No initial page turn is sent.","Cancel","Continue")
        w:focus();if b~="Continue"then return end
        defer(0.7,function()
            local win,why=guard();if not win then warningNotice(why);return end
            if not pendingSourceStillVisible()then warningNotice("Source page changed; no request sent.");return end
            job.pending.composerPrefix=nil;job.pending.selectionVerified=nil
            job.requestMode="skill"
            job.pending.inputMode=nil
            job.pending.requestText=nil;job.pending.pasteAttemptedAt=nil
            job.pauseReason=nil
            running=true;beginOwnership()
            verifiedInput=nil;inputReadback=nil;pasteInFlight=false;skillFlow=nil
            responseCandidate,responseSince=nil,nil
            inputWaitPhase,inputWaitStarted,inputReclicked=nil,nil,false
            setPhase("preflight-manual",0.5);checkpoint()
            log("User explicitly confirmed the ln chip in the current composer; continuing UNSENT screen without a page turn.")
        end)
    end)
end
function M.acceptClipboard()
    local raw=hs.pasteboard.getContents()
    if running then pause("Paused for manual review.","paused") end
    if not job or not job.pending then alert("There is no pending screen."); return end
    if checkLimitCopy(raw,"manually-copied-response") then return end
    local answer,err=core.parse(raw,job.pending.id)
    if not answer then warningNotice(err..". Copy ONLY the latest complete answer, including its markers."); return end
    local w,why=guard(); if not w then warningNotice(why); return end
    local b=hs.dialog.blockAlert("Save this reviewed response?",
        "Confirm that this is a COMPLETE translation of the currently displayed page. This manually overrides the repeated-anchor check, but not the request ID/source-image checks.",
        "Cancel","Save")
    w:focus()
    if b=="Save" then
        hs.alert.closeAll(0)
        defer(0.5,function() saveAnswer(answer,true) end)
    end
end
-- File discovery is read-only. Selecting a checkpoint never creates a book,
-- rewrites saved responses, resets its mode/counts or rearms an old timer.
local jobChooser
local function readSavedJob(folder)
    return savedJobs.read(folder, hs.json.decode, readFile)
end
local function availableSavedJobs()
    return savedJobs.discover(cfg.outputRoot, hs.fs, hs.json.decode, readFile)
end
function M.restoreFolder(folder)
    local candidate,err=readSavedJob(folder)
    if not candidate then
        warningNotice("Cannot restore this job: "..tostring(err)..". No new job was created.")
        return false
    end
    local selected=providers.id(candidate.job.provider)
    if not selected then warningNotice("Cannot restore a job with an unknown provider.");return false end
    local problem=providers.problem(selected,candidate.job,nil)
    if problem then warningNotice(problem);return false end
    if quota.cancel then quota.cancel("Restore/reload",false) end
    if recoveryActive then pause("Recovery cancelled before restoring a job.","paused") end
    if running then pause("Paused before restoring a job.","paused") end
    cancelScan();releaseOwnership();dismissNotice();hs.alert.closeAll(0)
    calibrationStep,calibrationDraft,nextCalibration=nil,nil,nil
    provider=selected;hs.settings.set(settingKey..".provider",provider)
    cal=hs.settings.get(providerKey(".calibration"))
    job=candidate.job;job.folder=folder;job.provider=provider;phase="restored";running=false
    if not job.requestMode then job.requestMode=provider=="chatgpt" and "inline" or cfg.defaultRequestMode end
    if job.autoResume and job.autoResume.active then
        job.autoResume.active=false;job.autoResume.status="Cancelled on restore; not rearmed."
    end
    -- Repair the remembered pointer only AFTER successful decoding/validation.
    hs.settings.set(providerKey(".latest"),folder)
    sessionWarning=nil;refreshMenu()
    log("Restored existing job "..candidate.name..": "..#job.records.." saved, "
        ..job.remaining.." remaining; mode="..job.requestMode..". No request or turn sent.")
    persistentNotice("Loaded "..#job.records.." saved screens; "..job.remaining.." remaining.\n"
        ..candidate.name.."\nProvider: "..providerName().."\nMode: "..(job.requestMode=="inline" and "direct prompt (no skill picker)" or "skill")
        .."\nReturn to its saved/pending source page, close any menus, then Start / resume. No new job was created.",true)
    return true
end
-- Renaming is file-only. It never sends a request, turns the reader, changes
-- request IDs, or converts a sent pending reply into an unsent one.
local function shellArgument(value)
    return "'"..tostring(value):gsub("'", "'\"'\"'").."'"
end
local function moveJobNoReplace(source,destination)
    if not exists(cfg.illustrationPython) or not exists(cfg.jobMoveScript) then
        return nil,"The local job-move helper or Python runtime is missing."
    end
    local output,ok=hs.execute(shellArgument(cfg.illustrationPython).." "..shellArgument(cfg.jobMoveScript)
        .." "..shellArgument(source).." "..shellArgument(destination),false)
    local decoded,result=pcall(hs.json.decode,output or "")
    if ok and decoded and result and result.ok==true then return true end
    return nil,decoded and type(result)=="table" and result.error or tostring(output)
end
function M.renameJob(title,folder)
    local interactive=type(title)~="string"
    local function fail(reason)sessionWarning=reason;refreshMenu();if interactive then alert(reason)end;return nil,reason end
    if running or recoveryActive or illustrationTask or resumeCaptureEpoch==epoch
        or epubManager:busy(folder or (job and job.folder)) then
        return fail("Pause translation and wait for the current save/illustration update before renaming.")
    end
    if quota.timer or (job and job.autoResume and job.autoResume.active) then
        return fail("Cancel the scheduled auto-resume before renaming this job.")
    end
    folder=type(folder)=="string" and folder or job and job.folder
    if not folder then return fail("Restore or choose a saved job first, then rename it.")end
    local saved,why=savedJobs.read(folder,hs.json.decode,readFile)
    if not saved then return fail(why)end
    if job and job.folder==folder then
        local a,b=job.pending or {},saved.job.pending or {}
        if job.tag~=saved.job.tag or #job.records~=#saved.job.records or job.remaining~=saved.job.remaining
            or job.lastSourceHash~=saved.job.lastSourceHash or job.needAdvance~=saved.job.needAdvance
            or job.turnUncertain~=saved.job.turnUncertain or a.id~=b.id or a.sent~=b.sent then
            return fail("The saved checkpoint changed. Restore this job before renaming it.")
        end
    end
    local sourceTitle=saved.job.sourceWindowTitle
    if not sourceTitle and saved.job.lastTurnFolder then
        local raw=readFile(saved.job.lastTurnFolder.."/trace.json")
        local ok,trace=pcall(hs.json.decode,raw or "")
        if ok and type(trace)=="table" and trace.bookFocus and trace.bookFocus.book then
            sourceTitle=trace.bookFocus.book.title
        end
    end
    if interactive then
        local initial=saved.job.bookTitle or (sourceTitle and M.defaultJobTitle(sourceTitle))
            or saved.name:gsub("^Book%-","")
        local button,value=hs.dialog.textPrompt("Rename book-translation job",
            "Book title for the folder (Book- is added automatically). Saved pages and pending replies stay with this job:",
            initial,"Rename","Cancel")
        if button~="Rename" then return nil,"cancelled"end
        title=value
    end
    -- Synchronous transaction runs while the engine is idle. Deferred recovery
    -- callbacks must not retain paths from before the rename.
    cancelScan();resumeCaptureEpoch=nil
    savedSourceReview=nil;savedSourceReviewCommit=nil;unchangedTurnRetry=nil
    local result,problem,receipt=jobRename.rename(folder,title,{root=cfg.outputRoot,fs=hs.fs,
        decode=hs.json.decode,encode=function(value)return hs.json.encode(value,true)end,
        transactionId=os.date("%Y%m%d-%H%M%S").."-"..hs.host.uuid(),
        timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ"),moveNoReplace=moveJobNoReplace})
    if not result then
        if receipt and receipt.status=="recovery-required" then
            -- A failed rollback must not leave an in-memory writer pointed at
            -- either uncertain location. Preserve the journal for recovery.
            if job and job.folder==folder then job=nil;phase="rename-recovery-required"end
            warningNotice("Job rename needs recovery. No translation will run.\n"..tostring(problem)
                .."\nJournal: "..tostring(receipt.journal))
        end
        return fail(problem)
    end
    local current=job and job.folder==folder
    if current then
        job=result.job
        responseCandidate,responseSince,collection,copyTarget=nil,nil,nil,nil
        illustrationBuild=jobNames.rewritePaths(illustrationBuild,folder,result.folder)
    end
    local renamedProvider=providers.id(result.job.provider)
    if renamedProvider then
        local pointer=settingKey..".latest"..(renamedProvider=="gemini" and "" or "."..renamedProvider)
        if hs.settings.get(pointer)==folder then hs.settings.set(pointer,result.folder)end
    end
    if lastNotice and lastNotice.folder==folder then
        lastNotice=jobNames.rewritePaths(lastNotice,folder,result.folder)
        hs.settings.set(settingKey..".lastNotice",lastNotice)
    end
    local source=sourceTitle and jobNames.titleFromWindow(sourceTitle)
    if source then
        local aliases=hs.settings.get(settingKey..".bookTitles") or {}
        aliases[source]=result.title;hs.settings.set(settingKey..".bookTitles",aliases)
    end
    sessionWarning=nil;refreshMenu()
    if interactive then persistentNotice("Renamed job to:\n"..result.folder.."\nSaved progress is preserved. Current status: "..uiState().label..".",true)end
    return result
end
function M.renameCurrentJob()return M.renameJob(nil,nil)end

local function chooseSavedJobEntries(entries)
    if recoveryActive then pause("Recovery cancelled before choosing a saved job.","paused")end
    if running then pause("Paused before choosing a saved job.","paused")end
    if #entries==0 then
        warningNotice("No valid saved checkpoints were found in "..cfg.outputRoot
            ..". Nothing was created or deleted. Use New job only to intentionally start another book.")
        return false
    end
    if not hs.chooser or not hs.chooser.new then
        persistentNotice("Multiple saved jobs require selection. Use GeminiBook.restoreFolder(fullFolderPath) in Console. Nothing was created.",true)
        return false
    end
    dismissNotice();hs.alert.closeAll(0)
    local choices={}
    for _,c in ipairs(entries)do
        choices[#choices+1]={text=c.name.." — "..c.saved.." saved / "..c.job.remaining.." remaining",
            subText=(c.saved==0 and "No completed translations. " or "")
                ..(c.job.requestMode=="inline" and "Direct prompt. " or "")
                ..(c.job.pending and ("Pending screen "..c.job.pending.index..(c.job.pending.sent and " (sent). " or " (unsent). ")) or "No pending request. ")
                ..c.folder,folder=c.folder}
    end
    jobChooser=hs.chooser.new(safe(function(choice)
        if choice then M.restoreFolder(choice.folder) end
        -- Keep the chooser referenced; it is safely replaced on the next open.
    end))
    jobChooser:choices(choices):placeholderText("Choose the book to restore — no new job or request"):show()
    return false -- Selection is asynchronous; callers MUST NOT start work yet.
end
function M.chooseSavedJob()
    -- Menu callbacks may pass a modifier-key table: do not interpret it as jobs.
    return chooseSavedJobEntries(availableSavedJobs())
end
function M.restoreLatest()
    if quota.cancel then quota.cancel("Restore/reload",false) end
    if recoveryActive then pause("Recovery cancelled before restoring a job.","paused")end
    if running then pause("Paused before restoring a job.","paused")end
    local folder=hs.settings.get(providerKey(".latest"))
    local current=folder and readSavedJob(folder)
    -- A recorded, populated job is an explicit prior choice; honor it.
    if current and current.saved>0 and providers.id(current.job.provider)==provider then return M.restoreFolder(folder)end
    local entries,scanErrors=availableSavedJobs()
    local matching={}
    for _,entry in ipairs(entries)do
        if providers.id(entry.job.provider)==provider then matching[#matching+1]=entry end
    end
    entries=matching
    local candidate,why=savedJobs.select(entries,folder)
    if candidate then return M.restoreFolder(candidate.folder)end
    if #entries>0 then return chooseSavedJobEntries(entries)end
    warningNotice("No valid saved checkpoint was found. The remembered folder may have been removed: "
        ..tostring(folder or "(none)")..".\nNo new job was created. "..tostring(scanErrors or ""))
    return false
end
-- A sent reply needs COLLECTION, not Retry/recovery of an unsent request.
function M.collectPendingOne()
    if running then pause("Paused before collecting the existing reply.","paused")end
    if not job then M.restoreLatest()end
    if not job or not job.pending then
        persistentNotice("There is no pending reply to collect. Use Start/resume for a completed batch.",true);return
    end
    local p=job.pending
    if p.sent~=true or p.index~=#job.records+1 or job.needAdvance or job.turnUncertain
        or type(job.remaining)~="number" or job.remaining<1 then
        persistentNotice("This option only collects an already-sent pending request. No request, file replacement, or page turn was made.",true);return
    end
    dismissNotice();hs.alert.closeAll(0)
    local w,err=guard();if not w then warningNotice(err);return end
    local button=hs.dialog.blockAlert("Collect the existing reply only?",
        #job.records.." saved screens; "..job.remaining.." remaining.\nPending: "..p.id
        .."\nLeave its source page/spread displayed and the existing Gemini reply in this conversation. "
        .."This test will scroll/copy the reply, validate it, save ONE screen and pause. "
        .."It will not type a request, send one, or turn the book page.","Cancel","Collect reply")
    w:focus()
    if button~="Collect reply"then return end
    job.pauseAfterNext=true
    p.collectDespiteLimit=true
    checkpoint()
    log("User authorized collection-only test of already-sent "..p.id.."; no re-submission or page turn.")
    defer(0.7,M.resume)
end
-- Deliberate recovery after Retry changed an already-generated request ID.
-- No wildcard parser acceptance and no automatic ID substitution. The user
-- confirms the exact previously-sent ID and current source, the old checkpoint
-- is backed up, and collection still requires that exact BEGIN/END pair.
function M.collectPriorReply()
    if running then pause("Paused before recovering an earlier reply.","paused")end
    if not job and not M.restoreLatest()then return end
    if job and job.pending and job.pending.sent then M.collectPendingOne();return end
    dismissNotice();hs.alert.closeAll(0)
    defer(0.5,function()
        local w,err=guard();if not w then warningNotice(err);return end
        local oldID,why=priorReply.find(job,readFile(job.folder.."/run.log"))
        if not oldID then persistentNotice(why.." No request was sent and no file changed.",true);return end
        if not pendingSourceStillVisible()then
            warningNotice("Return to the pending book page before collecting its earlier reply. No request was sent.");return
        end
        local expectedID=job.pending.id
        local b=hs.dialog.blockAlert("Recover the existing reply from before Retry?",
            #job.records.." saved screens; "..job.remaining.." remaining.\n"
            .."Earlier sent request: "..oldID.."\n"
            .."Current unsent retry: "..expectedID.."\n\n"
            .."Confirm the visible answer is for that earlier ID and the CURRENT book spread. "
            .."This backs up the checkpoint and restores only the pending request identity, "
            .."then copies/validates ONE existing reply and pauses. "
            .."No translation request or page turn will be sent.","Cancel","Collect earlier reply")
        w:focus()
        if b~="Collect earlier reply"then return end
        defer(0.7,function()
            local valid,msg=guard();if not valid then warningNotice(msg);return end
            local again=priorReply.find(job,readFile(job.folder.."/run.log"))
            if not job.pending or job.pending.id~=expectedID or again~=oldID
                or not pendingSourceStillVisible() then
                warningNotice("Pending state or source changed during confirmation; nothing was modified.");return
            end
            local dir=job.folder.."/recovery/prior-reply-"..string.format("%05d",job.pending.index)
                .."-"..os.date("%Y%m%d-%H%M%S")
            mkdir(dir)
            atomicWrite(dir.."/checkpoint-before.json",hs.json.encode(job,true))
            local p=job.pending
            local prior=job.priorSentReply
            p.modelAtSubmit=prior and prior.id==oldID and prior.modelAtSubmit or nil
            p.modelProvenance=prior and prior.id==oldID and pageModels.copy(prior.modelProvenance) or nil
            p.id=oldID;p.sent=true;p.sentAt=now();p.requestText=nil
            p.pasteAttemptedAt=nil;p.composerPrefix=nil;p.selectionVerified=nil
            p.recoveredFromRetryID=expectedID;p.collectDespiteLimit=true
            job.pauseAfterNext=true
            checkpoint()
            log("User confirmed recovery of earlier sent reply "..oldID.." from unsent retry "..expectedID
                ..". Checkpoint backed up; collection only, no resubmission or page turn.")
            M.resume()
        end)
    end)
end
function M.openOutput()
    local path=job and job.folder or cfg.outputRoot
    mkdir(path)
    openPath(path)
end
function M.diagnostics()
    if recoveryActive then pause("Recovery paused for diagnostics.","paused") end
    if running then pause("Paused for diagnostics.","paused") end
    local w,err=guard(); if not w then warningNotice(err); return end
    mkdir(cfg.outputRoot)
    scanButtons(function(copies,stopped,lines,limitHit,model)
        local out={"Babelbound accessibility diagnostics", "Current composer model: "..tostring(model),
            "Matched limit notice: "..tostring(limitHit and limitHit.text or "none"), "Chrome title: "..w:title(),
            "Visible Copy candidates: "..#copies, "Generation/Stop control: "..tostring(stopped),
            "Pending ID: "..(job and job.pending and job.pending.id or "none"),
            "", "Sidebar button labels (not response text):"}
        for _,s in ipairs(lines) do out[#out+1]=s end
        local input=hs.axuielement.systemElementAtPosition(cal.input.x,cal.input.y)
        out[#out+1]="\nElements at/above calibrated input point:"
        for _=1,7 do
            if not input then break end
            local f=frameOf(input)
            local v=attr(input,"AXValue")
            out[#out+1]=string.format("role=%s frame=%s valueType=%s valueLength=%s",
                tostring(attr(input,"AXRole")),f and hs.json.encode(f) or "nil",
                type(v),type(v)=="string" and #v or "n/a")
            input=attr(input,"AXParent")
        end
        local path=cfg.outputRoot.."/diagnostics-"..os.date("%Y%m%d-%H%M%S")..".txt"
        atomicWrite(path,table.concat(out,"\n").."\n")
        openPath(path)
    end)
end
function M.status()
    if running then pause("Paused to display status.","paused") end
    local s="Status: "..uiState().label.."\nState: "..phase.."; running="..tostring(running)
    if job then s=s.."\nBook: "..(job.bookTitle or job.folder:match("([^/]+)$")).."\nSaved: "..#job.records.."; remaining: "..job.remaining.."\n"..job.folder end
    if job then s=s.."\nRequest mode: "..(job.requestMode or cfg.defaultRequestMode)end
    if not job then s=s.."\nNo job loaded. Use Restore latest saved job." end
    if job and job.pending then s=s.."\nPending ID: "..job.pending.id.."; sent="..tostring(job.pending.sent) end
    if job and job.pauseReason then s=s.."\nLast pause: "..job.pauseReason end
    if job and job.autoResume then s=s.."\nAuto-resume: "..tostring(job.autoResume.status)
        .."; "..os.date("%b %d %I:%M %p %Z",job.autoResume.dueAt) end
    if running then alert(s) else persistentNotice(s,false) end
    log(s)
end

-- One-shot, opt-in LOCAL timer. No ChatGPT task, network request or account
-- interaction happens while waiting. Reload/Stop explicitly cancels consent.
quota.cancel=function(reason,show)
    if quota.timer then quota.timer:stop();quota.timer=nil end
    if job and job.autoResume and job.autoResume.active then
        job.autoResume.active=false
        job.autoResume.status=reason or "Cancelled"
        pcall(checkpoint)
        log("Auto-resume cancelled: "..tostring(reason))
        refreshMenu()
    end
    if show then persistentNotice("Auto-resume cancelled. The job stays paused; no request was sent.",true) end
end
local function sessionUsable()
    if hs.caffeinate.sessionProperties then
        local ok,p=pcall(hs.caffeinate.sessionProperties)
        if not ok or type(p)~="table" then return false,"Cannot verify the macOS session for unattended resume." end
        if p.CGSSessionScreenIsLocked==true or p.kCGSessionOnConsoleKey==false
            or p.kCGSSessionOnConsoleKey==false then
            return false,"Mac is locked or its user session is not active. Resume manually after unlocking."
        end
    else return false,"Session-state API is unavailable; resume manually." end
    return true
end
quota.attempt=function(plan)
    if quota.timer then quota.timer:stop();quota.timer=nil end
    if not job or not plan.active or job.autoResume~=plan then return end
    dismissNotice();hs.alert.closeAll(0)
    defer(0.6,function()
        local ok,why=sessionUsable()
        if not ok then pause("Scheduled auto-resume stopped: "..why);return end
        local w,err=guard()
        if not w then pause("Scheduled auto-resume stopped: "..err.." No window was switched or page advanced.");return end
        local _,hash=capture()
        -- Source/job/lateness check before doing even a sidebar scan.
        local allowed,reason=resetClock.canRun(plan,job,now(),hash)
        if not allowed then pause("Scheduled auto-resume stopped: "..reason);return end
        phase="quota-resume-check" -- running stays false; the scan is read-only.
        scanButtons(function(_,stopped,_,limitHit,model)
            if not job or job.autoResume~=plan or not plan.active then return end
            if stopped then pause("Scheduled auto-resume stopped: Gemini is generating. Collect its reply manually.");return end
            if limitHit then
                rememberUsageLimit(limitHit,"scheduled-reset-check")
                pause("A blocking Gemini notice is still visible after the approved reset time. No request or page turn was sent. Check Gemini and re-arm manually.")
                return
            end
            local _,currentHash=capture()
            local good,whyNot=resetClock.canRun(plan,job,now(),currentHash,model)
            if not good then pause("Scheduled auto-resume stopped: "..whyNot);return end
            -- Empty composer required for unattended actions, even before a turn.
            local composer=scopedRoots()
            local _,_,draft=focusedInput(false)
            if type(draft)~="string" then
                -- Focus need not be in the editor while waiting. Find an editor
                -- through the calibrated point without clicking or changing it.
                local hit=hs.axuielement.systemWideElement():elementAtPosition(cal.input.x,cal.input.y)
                local e=editorAtOrAbove(hit)
                if e and inComposer(e) then
                    draft=core.composerValue(attr(e,"AXValue"),attr(e,"AXPlaceholderValue"),inputHints())
                end
            end
            if type(draft)~="string" or core.trim(draft)~="" then
                pause("Scheduled auto-resume stopped: Gemini has a draft or its empty input cannot be verified. Clear/review it manually. No request or page turn was sent.");return
            end
            plan.active=false;plan.status="Approved one-shot checks passed"
            plan.checkedModel=model or "unverified";plan.firedAt=now()
            if job.usageLimit then job.usageLimit.active=false end
            job.deferredUsageLimit=nil
            checkpoint()
            log("Approved reset-time checks passed using the current Gemini model ("..tostring(model or "unverified").."). Resume the existing checkpoint; a sent request will only be collected, never resubmitted.")
            M.resume('scheduled')
        end)
    end)
end
quota.offer=function(event)
    if not job or running or job.remaining<=0 then return end
    local parsed,why=resetClock.parseReset(event.text,now())
    if not parsed then
        event.resetParseError=why;pcall(checkpoint)
        log("No reset timer offered: "..why)
        persistentNotice("Paused for Gemini's availability check. "..why
            .." Use BT > Schedule auto-resume from reset notice to paste the exact notice or an explicit local date/time. Nothing is scheduled.",true)
        return
    end
    local w,err=guard()
    if not w then warningNotice("Cannot arm automatic resume: "..err);return end
    local sourceHash=job.pending and job.pending.sourceHash or job.lastSourceHash
    if not sourceHash or job.turnUncertain then
        warningNotice("Cannot arm auto-resume until the current book position has a saved/pending source reference and no uncertain turn.");return
    end
    local target=parsed.resetAt+cfg.usageResumeBufferSeconds
    local label=os.date("%b %d, %Y at %I:%M %p %Z",target)
    dismissNotice();hs.alert.closeAll(0)
    local b=hs.dialog.blockAlert("Auto-resume at "..label.."?",
        "Gemini says its limit resets "..parsed.label..". This adds a 60-second buffer.\n\n"
        .."Leave Hammerspoon running, the Mac awake/unlocked, and the ORIGINAL book tab, source page and conversation in front. "
        .."At that time, resume with the currently selected model only if no blocking service or quota notice is visible. "
        .."Gemini's continuing-with-Flash-Lite notice is allowed. Babelbound never changes the model selection.\n\n"
        .."An already-sent request will only be collected, never automatically resent. "
        .."Stop, manual Start/resume, reload or quitting cancels this one-shot timer. No response means no timer.",
        "No, stay paused","Yes, auto-resume")
    w:focus()
    if b~="Yes, auto-resume" then
        persistentNotice("No auto-resume was scheduled. Saved work remains paused.",true);return
    end
    if target<=now() then pause("Reset time passed while the confirmation was open. Check Gemini and resume manually.");return end
    quota.cancel("Replaced by a newly approved timer",false)
    local plan={active=true,resetAt=parsed.resetAt,dueAt=target,
        maxLateSeconds=cfg.usageResumeMaxLateSeconds,sourceHash=sourceHash,
        snapshot=resetClock.snapshot(job),authorizedAt=now(),zone=parsed.zone,
        status="Armed for "..label,notice=event.text}
    job.autoResume=plan;checkpoint()
    refreshMenu()
    log("User approved one-shot auto-resume: "..label.."; no quota polling or prompts during the wait.")
    -- Wall clock, not a relative countdown: sleep cannot extend the deadline
    -- silently. More than ten minutes late cancels rather than typing hours later.
    quota.timer=hs.timer.doEvery(1,safe(function()
        if not plan.active or job.autoResume~=plan then quota.cancel("Job changed",false);return end
        if now()>=plan.dueAt then quota.attempt(plan) end
    end))
    persistentNotice("Auto-resume check scheduled for "..label.." using the currently selected model. No blocking Gemini notice may remain, and the original book page must be in front. "
        .."The Mac must remain awake/unlocked. Stop or BT > Cancel auto-resume cancels the timer.",true)
end
function M.cancelAutoResume() quota.cancel("Cancelled by user",true) end
function M.scheduleLimitResume()
    if running then pause("Paused before scheduling an optional reset-time resume.","paused") end
    if not job then M.restoreLatest() end
    if not job then return end
    local w,err=guard();if not w then warningNotice(err);return end
    dismissNotice();hs.alert.closeAll(0)
    local oldRemaining=job.remaining
    if job.remaining==0 then
        local b,n=hs.dialog.textPrompt("Next batch after reset", "How many additional screens/spreads? No translation starts now.",
            tostring(cfg.defaultBatch),"Continue","Cancel")
        w:focus();n=tonumber(n)
        if b~="Continue"then return end
        if not n or n<1 or n>1000 or n~=math.floor(n) then warningNotice("Enter 1–1000.");return end
        job.remaining=n;checkpoint()
    end
    local default=job.usageLimit and job.usageLimit.text or ""
    local b,text=hs.dialog.textPrompt("Gemini reset notice", "Paste the actual reset notice, or YYYY-MM-DD HH:MM in the Mac's local timezone. You will separately approve the displayed date/time.",
        default,"Review time","Cancel")
    w:focus()
    if b~="Review time"then job.remaining=oldRemaining;checkpoint();return end
    local event={text=text,kind="user-entered-reset",origin="manual-schedule",active=true}
    local parsed,why=resetClock.parseReset(text,now())
    if not parsed then job.remaining=oldRemaining;checkpoint();warningNotice(why.." No timer was armed.");return end
    job.usageLimit=event;checkpoint()
    defer(0.6,function()quota.offer(event)end)
end

function M.menuItems()
        local view=refreshMenu()
        return {
            {title="Babelbound "..M.version.." — "..view.label,disabled=true},
            {title="Provider: "..providerName(),menu={
                {title="Gemini",checked=provider=="gemini",fn=safe(function()M.selectProvider("gemini")end)},
                {title="ChatGPT extension (experimental)",checked=provider=="chatgpt",fn=safe(function()M.selectProvider("chatgpt")end)},
            }},
            {title="Calibrate (Ctrl-Option-Cmd-C)",fn=safe(M.calibrate)},
            {title="Set forward click only (Ctrl-Option-Cmd-N)",fn=safe(M.calibrateNext)},
            {title="Preview source crop",fn=safe(M.preview)},
            {title="Review last saved source",fn=safe(M.reviewLastSavedSource)},
            {title="New job on current screen",fn=safe(M.newJob)},
            {title=view.startLabel,fn=safe(M.resume)},
            {title="Pause / resume (Ctrl-Option-Cmd-P)",fn=safe(M.togglePause)},
            {title="STOP (Ctrl-Option-Cmd-X)",fn=safe(M.stop)},
            {title="-"},
            {title="Retry pending screen (clear "..providerName().." input first)",fn=safe(M.retry)},
            {title="Continue with manually selected ln skill",fn=safe(M.continueSelectedSkill),disabled=provider~="gemini"},
            {title="Recover pending screen with direct prompt (test one)",fn=safe(M.retryInlineOne)},
            {title="Collect existing pending reply only (test one)",fn=safe(M.collectPendingOne)},
            {title="Collect earlier reply from before Retry (test one)",fn=safe(M.collectPriorReply)},
            {title="Accept reviewed clipboard (Ctrl-Option-Cmd-M)",fn=safe(M.acceptClipboard)},
            {title="Restore latest saved job",fn=safe(M.restoreLatest)},
            {title="Choose saved job…",fn=safe(M.chooseSavedJob)},
            {title="Rename current job…",fn=safe(M.renameCurrentJob),disabled=not job or running or recoveryActive or illustrationTask~=nil or epubManager:busy(job.folder)},
            {title="Schedule auto-resume from reset notice",fn=safe(M.scheduleLimitResume)},
            {title="Cancel auto-resume",fn=safe(M.cancelAutoResume)},
            {title="Rebuild illustrated reading copy (all saved screens)",fn=safe(M.rebuildIllustrations)},
            {title="Open illustrated reading copy",fn=safe(M.openReadingCopy)},
            {title="Open EPUB in Books",fn=safe(M.openEpub)},
            {title="Open output folder",fn=safe(M.openOutput)},
            {title="Accessibility diagnostics",fn=safe(M.diagnostics)},
            {title="Show last pause/error",fn=safe(M.showLastMessage)},
            {title="Dismiss message (Ctrl-Option-Cmd-D)",fn=safe(M.dismissMessage)},
            {title="Status",fn=safe(M.status)},
        }
end
if menu then refreshMenu();menu:setMenu(M.menuItems)end
M.hotkeys={}
for key,fn in pairs({c=M.calibrate,s=M.resume,p=M.togglePause,x=M.stop,m=M.acceptClipboard,d=M.dismissMessage,n=M.calibrateNext}) do
    -- Run on key release, so modifier keys are not held during synthetic typing.
    M.hotkeys[#M.hotkeys+1]=hs.hotkey.bind(mods,key,nil,safe(fn))
end
timer=hs.timer.doEvery(0.1,safe(tick))
M.timer=timer
M.menu=menu
local priorShutdown=hs.shutdownCallback
hs.shutdownCallback=function()
    pause(nil)
    dismissNotice()
    if priorShutdown then priorShutdown() end
end
log("Loaded v"..M.version..". Existing calibration retained. Use BT > Restore latest saved job to continue saved work after reload.")
return M
