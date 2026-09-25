-- Pure menu and action policy. A snapshot is data only: no browser reads,
-- timers, callbacks, filesystem access, or mutation happen while building it.
local status = require("gemini_book_status")
local core = require("gemini_book_core")
local source = require("gemini_book_source")
local M = {}

local function clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function count(s)
    return s.job and type(s.job.records) == "table" and #s.job.records or 0
end

local function warning(s)
    local message = clean(s.warning)
    if message ~= "" then return s.warning end
    if s.job and status.idle(s.job) == "warning" then
        message = clean(s.job.pauseReason)
        return message ~= "" and s.job.pauseReason or "This book needs review before continuing."
    end
end

local function warningLabel(message)
    local label = clean(message)
    local length = utf8.len(label)
    if length and length > 100 then
        return label:sub(1, utf8.offset(label, 100) - 1) .. "…"
    end
    return label
end

local function complete(s)
    return count(s) > 0 and s.job.remaining == 0 and not s.job.pending
        and not s.job.turnUncertain
end

local function busy(s)
    if s.running or s.checking then return "Pause or stop the current operation first." end
    if s.scheduled then return "Cancel the scheduled resume first." end
end

local function pendingProblem(s)
    local job = s.job
    if not job then return "Open a book first." end
    local p = job.pending
    if type(p) ~= "table" then return "This book has no pending screen." end
    if p.index ~= count(s) + 1 then return "The pending screen does not follow the saved screens." end
    if type(job.remaining) ~= "number" or job.remaining < 1
        or job.remaining ~= math.floor(job.remaining) then return "The remaining screen count needs review." end
    if clean(p.id) == "" or clean(p.sourceHash) == "" then
        return "The pending request is missing its ID or source reference."
    end
    if job.needAdvance or job.turnUncertain or job.expectChange then
        return "Review the page position before recovering a reply."
    end
end

local quietActions = {
    newBook=true, chooseSavedJob=true, restoreLatest=true, rename=true,
    providerGemini=true, providerChatgpt=true, calibrate=true, calibrateNext=true,
    preview=true, collectPending=true, resend=true, collectPrior=true, directPrompt=true,
    selectedSkill=true, clipboard=true, reviewSource=true, scheduleResume=true,
    rebuildReadingCopy=true, rebuildEpub=true, reviewPosition=true, reviewProblem=true,
    translateMore=true,
}

-- The runtime rechecks this policy when a command is invoked. A menu item may
-- have been opened before a timer fired or a writer started.
function M.allowed(snapshot, action)
    local s = snapshot or {}
    if action == "stop" or action == "dismiss" or action == "details"
        or action == "diagnostics" or action == "lastMessage" then return true end
    if action == "pause" then
        if s.running or s.checking then return true end
        return false, "No translation or check is running."
    end
    if action == "cancelResume" then
        if s.scheduled then return true end
        return false, "No resume is scheduled."
    end
    local output = ({openReadingCopy="html", openEpub="epub", openOutput="folder"})[action]
    if output then
        if not s.job then return false, "Open a book first." end
        if not (s.outputs and s.outputs[output]) then
            return false, ({html="No reading copy has been saved yet.", epub="No EPUB has been saved yet.",
                folder="The output folder is unavailable."})[output]
        end
        return true
    end
    if quietActions[action] then
        local why = busy(s)
        if why then return false, why end
    elseif action ~= "resume" then
        return false, "Unknown menu action."
    end
    if action == "providerGemini" or action == "providerChatgpt" then
        if s.illustrationBusy then return false, "Wait for the reading copy writer to finish before changing providers." end
        return true
    end
    if action == "calibrate" or action == "chooseSavedJob" or action == "restoreLatest" then return true end
    if action == "rename" then
        if not s.job then return false, "Open a book first." end
        if s.illustrationBusy or s.epubBusy then return false, "Wait for the reading copy and EPUB writers to finish." end
        return true
    end
    if action == "rebuildReadingCopy" or action == "rebuildEpub" then
        if count(s) == 0 then return false, "Save a translated screen first." end
        if s.illustrationBusy or s.epubBusy then return false, "Wait for the reading copy and EPUB writers to finish." end
        return true
    end
    if action == "reviewProblem" then
        if warning(s) then return true end
        return false, "There is no blocking translation problem to review."
    end
    if action == "reviewPosition" then
        if s.job and s.job.turnUncertain then return true end
        return false, "No uncertain page turn needs review."
    end
    if not s.calibrated then return false, "Calibrate the selected provider first." end
    if action == "newBook" or action == "calibrateNext" or action == "preview" then return true end
    if not s.job then return false, "Open a book first." end
    if action == "resume" or action == "translateMore" then
        if s.running or s.checking then return false, "Pause or stop the current operation first." end
        if s.job.turnUncertain then return false, "Review the page position before continuing." end
        -- A scheduled quota retry is already authorized; ordinary Resume must
        -- go through the problem review instead of silently dismissing it.
        if not s.scheduled and warning(s) then return false, "Review the problem before continuing." end
        if action == "translateMore" then
            if complete(s) then return true end
            return false, "Finish or review the current screen target first."
        end
        if complete(s) then return false, "Choose Translate more to start another screen target." end
        return true
    end
    if action == "scheduleResume" then
        if s.provider ~= "gemini" then return false, "Usage-reset scheduling is available for Gemini only." end
        if s.job.turnUncertain then return false, "Review the page position before scheduling a resume." end
        if not (s.job.pending and s.job.pending.sourceHash or s.job.lastSourceHash) then
            return false, "A saved or pending source reference is required."
        end
        return true
    end
    if action == "reviewSource" then
        local why = source.problem(s.job)
        return why == nil, why
    end
    local why = pendingProblem(s)
    if why then return false, why end
    local p = s.job.pending
    if action == "collectPending" then
        if p.sent == true then return true end
        return false, "The pending request has not been sent."
    end
    if action == "resend" or action == "clipboard" then return true end
    if action == "directPrompt" or action == "selectedSkill" then
        if action == "selectedSkill" and s.provider ~= "gemini" then
            return false, "Gemini skills are not used by the ChatGPT extension."
        end
        why = core.pendingRecoveryProblem(s.job)
        return why == nil, why
    end
    if action == "collectPrior" then
        if p.sent ~= false then return false, "Use Collect existing reply for a sent request." end
        if p.requestText ~= nil or p.pasteAttemptedAt ~= nil then return false, "Review the drafted retry before changing its identity." end
        -- Legacy jobs may retain the earlier identity only in their run log.
        -- Keep that explicit lookup available for an unsent retry, never run it
        -- during menu construction or claim that a matching reply was found.
        if s.job.priorSentReply or (type(p.id) == "string" and p.id:match("%-r%d+[%d%-]*$")) then return true end
        return false, "There is no earlier sent request to recover for this screen."
    end
    return false, "Unknown menu action."
end

local function entry(s, title, action, tooltip)
    local allowed, why = M.allowed(s, action)
    local item = {title=title, action=action, disabled=not allowed}
    if tooltip or why then item.tooltip = tooltip and (why and tooltip .. "\n" .. why or tooltip) or why end
    return item
end

function M.primary(snapshot)
    local s = snapshot or {}
    local book = status.bookTitle(s.job)
    local title, action
    if s.running then title, action = "Pause — " .. book, "pause"
    elseif s.checking then
        return {title="Checking — " .. book .. "…", disabled=true,
            tooltip="Stop automation to cancel the current checks."}
    elseif s.scheduled then title, action = "Resume now — " .. book, "resume"
    elseif s.job and s.job.turnUncertain then title, action = "Review page position — " .. book .. "…", "reviewPosition"
    elseif warning(s) then title, action = "Review problem — " .. book .. "…", "reviewProblem"
    elseif not s.calibrated then title, action = "Set up translator…", "calibrate"
    elseif not s.job then title, action = "Start translating…", "newBook"
    elseif complete(s) then title, action = "Translate more — " .. book .. "…", "translateMore"
    else title, action = "Resume — " .. book, "resume" end
    return entry(s, title, action, "Ctrl-Option-Cmd-S\n" .. book)
end

local function foregroundTitle(s, phrase)
    if s.running or s.checking then return "Pause and " .. phrase end
    if s.scheduled then return "Cancel scheduled resume and " .. phrase end
    return phrase:sub(1, 1):upper() .. phrase:sub(2)
end

local function passive(title, tooltip)
    return {title=title, disabled=true, tooltip=tooltip}
end

function M.build(snapshot)
    local s = snapshot or {}
    local book = status.bookTitle(s.job)
    local view = status.view(s.job, {running=s.running, phase=s.phase, recoveryActive=s.checking,
        warning=not s.running and not s.checking and not s.scheduled and warning(s) or nil})
    local state = view.label
    if not s.running and not s.checking then
        if s.scheduled then state = "Resume scheduled"
        elseif warning(s) then state = "Warning"
        elseif complete(s) then state = "Batch complete" end
    end
    local summary = state
    if s.job then
        local p = status.progress(s.job)
        summary = summary .. " · " .. p.saved .. " screens saved · Screen target: " .. p.total .. " (" .. p.percent .. "%)"
    end
    local provider = s.providerName or (s.provider == "chatgpt" and "ChatGPT extension (experimental)" or "Gemini")
    local model = clean(s.model)
    local items = {
        passive(book, book),
        passive(provider .. (model ~= "" and " · " .. model .. " (last observed)" or " · Model not observed")),
        passive(summary, view.tooltip),
    }
    local problem = warning(s)
    if not s.running and not s.checking and problem then
        items[#items+1] = passive(warningLabel(problem), problem)
    end
    if s.job and s.job.pending and s.job.pending.sent == true then
        items[#items+1] = passive("A reply is pending; it will not be sent again.")
    end
    if s.scheduled and s.job and s.job.autoResume and clean(s.job.autoResume.status) ~= "" then
        items[#items+1] = passive(clean(s.job.autoResume.status))
    end
    if s.illustrationError then items[#items+1] = passive("Reading copy needs attention", clean(s.illustrationError))
    elseif s.illustrationBusy then items[#items+1] = passive("Rebuilding reading copy…") end
    local epub = s.epub or {}
    if epub.status == "failed" then items[#items+1] = passive("EPUB needs attention", clean(epub.error))
    elseif s.epubBusy then items[#items+1] = passive("Preparing EPUB…") end
    items[#items+1] = {title="-"}
    items[#items+1] = M.primary(s)
    if s.checking then items[#items+1] = entry(s, "Stop automation", "stop", "Ctrl-Option-Cmd-X") end
    if s.scheduled then items[#items+1] = entry(s, "Cancel scheduled resume", "cancelResume") end
    items[#items+1] = {title="-"}
    items[#items+1] = {title="Read translation", menu={
        entry(s, foregroundTitle(s, "open reading copy"), "openReadingCopy"),
        entry(s, foregroundTitle(s, "open EPUB in Books"), "openEpub"),
        entry(s, foregroundTitle(s, "open output folder"), "openOutput"),
    }}
    items[#items+1] = {title="Books", menu={
        entry(s, "Start a new book…", "newBook"),
        entry(s, "Open saved book…", "chooseSavedJob"),
        entry(s, "Open most recent book", "restoreLatest"),
        entry(s, "Rename this book…", "rename"),
    }}
    local gemini = entry(s, "Gemini", "providerGemini")
    local chatgpt = entry(s, "ChatGPT extension (experimental)", "providerChatgpt")
    gemini.checked, chatgpt.checked = s.provider ~= "chatgpt", s.provider == "chatgpt"
    items[#items+1] = {title="Setup", menu={
        {title="Translation provider", menu={gemini, chatgpt}},
        entry(s, "Calibrate…", "calibrate", "Ctrl-Option-Cmd-C"),
        entry(s, "Adjust forward-click target…", "calibrateNext", "Ctrl-Option-Cmd-N"),
        entry(s, "Preview source crop", "preview"),
    }}
    local advanced = {
        {title="Recovery", menu={
            entry(s, "Collect existing reply and pause", "collectPending"),
            entry(s, "Resend pending request…", "resend", "Creates a new request ID; may send another translation request."),
            entry(s, "Recover earlier reply…", "collectPrior"),
            entry(s, "Use direct prompt for this screen…", "directPrompt"),
            entry(s, "Continue with selected Gemini skill", "selectedSkill"),
            entry(s, "Save reviewed clipboard…", "clipboard", "Ctrl-Option-Cmd-M"),
            entry(s, "Review saved source…", "reviewSource"),
        }},
    }
    if s.provider ~= "chatgpt" then advanced[#advanced+1] = entry(s, "Resume after usage reset…", "scheduleResume") end
    if s.scheduled then advanced[#advanced+1] = entry(s, "Cancel scheduled resume", "cancelResume") end
    advanced[#advanced+1] = entry(s, "Rebuild reading copy", "rebuildReadingCopy")
    advanced[#advanced+1] = entry(s, epub.status == "failed" and "Retry EPUB export" or "Rebuild EPUB", "rebuildEpub")
    advanced[#advanced+1] = {title="Diagnostics", menu={
        entry(s, foregroundTitle(s, "show details…"), "details"),
        entry(s, foregroundTitle(s, "inspect browser controls…"), "diagnostics"),
        entry(s, foregroundTitle(s, "show last message…"), "lastMessage"),
        entry(s, "Dismiss message", "dismiss", "Ctrl-Option-Cmd-D"),
        passive("Babelbound " .. tostring(s.version or "")),
    }}
    advanced[#advanced+1] = entry(s, "Stop automation", "stop", "Ctrl-Option-Cmd-X\nSaved work is retained; a provider response may still finish.")
    items[#items+1] = {title="Advanced", menu=advanced}
    return items
end

return M
