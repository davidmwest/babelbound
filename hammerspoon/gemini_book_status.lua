-- Pure presentation policy; reading status never changes the job or starts work.
local S = {}

local function clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function saved(job)
    return job and type(job.records) == "table" and #job.records or 0
end

-- The target is the screens already saved plus the requested remaining work.
-- A pending reply is not committed progress, and a new batch extends the target.
function S.progress(job)
    local count = saved(job)
    local remaining = job and tonumber(job.remaining) or 0
    if not remaining or remaining ~= remaining or remaining == math.huge
        or remaining == -math.huge then remaining = 0 end
    remaining = math.max(0, math.ceil(remaining))
    local total = count + remaining
    local percent = total > 0 and math.floor(count * 100 / total) or 0
    if remaining > 0 then percent = math.min(99, percent) end
    return {saved=count, remaining=remaining, total=total, percent=percent}
end

function S.bookTitle(job)
    if not job then return "No book loaded" end
    local title = clean(job.bookTitle)
    if title ~= "" then return title end
    title = clean(job.folderName)
    if title == "" then title = clean((job.folder or ""):match("([^/]+)/?$")) end
    title = title:gsub("^Book%-", "")
    return title ~= "" and title or "Untitled book"
end

-- Older checkpoints predate pauseKind. Only these known user actions and
-- successful one-screen recoveries are ordinary pauses; unknown reasons warn.
local manualReasons = {}
for _, reason in ipairs({
    "Automation stopped. Saved files retained; resume is available.",
    "Paused. Gemini itself may still finish its reply.",
    "Reviewed response saved. Resume when ready.",
    "Paused for calibration.",
    "Paused to change the forward-click target.",
    "Paused for source crop preview.",
    "Recovery cancelled before New job.",
    "Paused before creating another job.",
    "Recovery cancelled by Start/resume. Prepare a fresh source review before approving it.",
    "Paused for retry.",
    "Recovery cancelled before retry.",
    "Saved-source review cancelled. No navigation reference or page was changed.",
    "Paused before direct-prompt recovery.",
    "Recovery cancelled. No reference, request, or book page was changed.",
    "Recovery cancelled before manual-skill recovery.",
    "Paused for manual skill selection.",
    "Paused for manual review.",
    "Recovery cancelled before restoring a job.",
    "Paused before restoring a job.",
    "Recovery cancelled before choosing a saved job.",
    "Paused before choosing a saved job.",
    "Paused before collecting the existing reply.",
    "Paused before recovering an earlier reply.",
    "Recovery paused for diagnostics.",
    "Paused for diagnostics.",
    "Paused to display status.",
    "Paused before scheduling an optional reset-time resume.",
}) do manualReasons[reason] = true end

local function complete(job)
    return saved(job) > 0 and job.remaining == 0
        and job.pending == nil and job.turnUncertain ~= true
end

function S.idle(job)
    if not job then return "ready" end
    if job.pauseKind == "warning" or job.turnUncertain == true then return "warning" end
    local reason = clean(job.pauseReason)
    local knownPause = manualReasons[reason] or reason:match("^One%-screen test complete%.")
    local knownComplete = reason == "Batch complete. Last page remains visible. Review the saved translation."
    if job.pauseKind ~= "paused" and job.pauseKind ~= "finished"
        and reason ~= "" and not knownPause and not knownComplete then
        return "warning"
    end
    if complete(job) then return "finished" end
    if job.pauseKind == "paused" or job.pauseKind == "finished" or reason ~= ""
        or job.pending ~= nil or saved(job) > 0 then return "paused" end
    return "ready"
end

local labels = {
    ready="Ready", paused="Paused", warning="Warning", finished="Batch complete",
    checking="Checking", turning="Turning page", translating="Translating",
    saving="Saving", scheduled="Scheduled",
}

local function activeKind(phase)
    phase = type(phase) == "string" and phase or ""
    if phase == "settle" or phase:match("^turn") or phase == "advance-ready" then return "turning" end
    if phase == "wait" or phase == "send" then return "translating" end
    if phase:match("^copy") or phase == "clipboard" or phase == "saved"
        or phase:match("^response%-scroll") then return "saving" end
    return "checking"
end

local function warningText(value)
    if type(value) == "string" then return clean(value) end
    if type(value) == "table" then return clean(value.reason or value.message or value.error) end
    return ""
end

function S.view(job, ctx)
    ctx = ctx or {}
    local build = ctx.illustrationBuild
    local currentBuild = job and type(build) == "table" and job.folder ~= nil
        and build.folder == job.folder
    local ebook=ctx.epubBuild
    local currentEbook=job and type(ebook)=="table" and job.folder~=nil and ebook.folder==job.folder
    local kind, reason
    if ctx.running then
        kind = activeKind(ctx.phase)
    elseif ctx.recoveryActive or ctx.resuming then
        kind = "checking"
    elseif job and job.autoResume and job.autoResume.active == true then
        kind = "scheduled"
    elseif ctx.warning then
        kind, reason = "warning", warningText(ctx.warning)
    elseif S.idle(job) == "warning" then
        kind = "warning"
    elseif (currentBuild and build.status == "running")
        or (currentEbook and (ebook.status=="running" or ebook.status=="queued")) then
        kind = "saving"
    else
        kind = S.idle(job)
    end
    local title = S.bookTitle(job)
    local label = labels[kind]
    local progress = S.progress(job)
    local suffix = (kind == "checking" or kind == "turning" or kind == "translating" or kind == "saving")
        and (" (" .. progress.percent .. "%)") or ""
    label = label .. suffix
    local lines = {"Book: " .. title, "Status: " .. label}
    if job then
        lines[#lines + 1] = "Saved screens: " .. progress.saved
        lines[#lines + 1] = "Remaining in batch: " .. progress.remaining
        lines[#lines + 1] = "Job target: " .. progress.total .. " screens (" .. progress.percent .. "% saved)"
    end
    if kind == "warning" then
        reason = reason or (job and clean(job.pauseReason)) or ""
        if reason == "" and job and job.turnUncertain then reason = "The last page turn needs review before continuing." end
        if reason ~= "" then lines[#lines + 1] = reason end
    elseif ctx.warning and warningText(ctx.warning) ~= "" then
        lines[#lines + 1] = "Warning: " .. warningText(ctx.warning)
    end
    -- Export workers run independently of translation. Report their failures
    -- without hiding active work or changing a completed batch into a warning.
    if currentBuild and build.status == "failed" then
        lines[#lines + 1] = "Reading copy could not be rebuilt: " .. clean(build.error)
    end
    if currentEbook and ebook.status == "failed" then
        lines[#lines + 1] = "EPUB export failed: " .. clean(ebook.error)
    end
    return {
        kind=kind, label=label, menuTitle="BT " .. kind .. suffix, bookTitle=title,
        progress=progress,
        startLabel="Start / resume — " .. title .. " (Ctrl-Option-Cmd-S)",
        tooltip=table.concat(lines, "\n"),
    }
end

return S
