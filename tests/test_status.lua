local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local S = dofile(paths.source("gemini_book_status.lua"))
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "check") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function has(actual, expected, message)
    checks = checks + 1
    assert(actual:find(expected, 1, true), (message or "text missing") .. ": " .. expected)
end
local function job(overrides)
    local result = {folder="/books/Book-Example Vol. 07", bookTitle="Example Vol. 07", records={{index=1}}, remaining=3}
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end
local completed = "Batch complete. Last page remains visible. Review the saved translation."
local stopped = "Automation stopped. Saved files retained; resume is available."

eq(S.idle(nil), "ready", "no job")
eq(S.idle(job({records={}})), "ready", "new job")
eq(S.idle(job()), "paused", "existing idle job")
eq(S.idle(job({pauseReason=completed, remaining=0})), "finished", "legacy completed checkpoint reload")
eq(S.idle(job({pauseReason=stopped, remaining=0})), "finished", "stop after completion")
eq(S.idle(job({pauseKind="paused", pauseReason=stopped, remaining=0})), "finished", "explicit stop after completion")
eq(S.idle(job({remaining=0})), "finished", "checkpoint committed before completion notice")
eq(S.idle(job({pauseKind="warning", pauseReason="Copy failed", remaining=0})), "warning", "warning not masked by finished counters")
eq(S.idle(job({pauseReason="Copy failed", remaining=0})), "warning", "legacy warning not masked")
eq(S.idle(job({pauseKind="warning", pauseReason=stopped})), "warning", "warning persists across manual stop")
eq(S.idle(job({pauseKind="paused", pauseReason="Intentional pause"})), "paused", "explicit pause")
eq(S.idle(job({pauseKind="finished", remaining=3})), "paused", "stale finished next batch")
eq(S.idle(job({pauseReason=completed, remaining=3})), "paused", "legacy completion cannot finish new batch")
eq(S.idle(job({pauseKind="finished", remaining=0, pending={id="next"}})), "paused", "pending never finished")
eq(S.idle(job({pauseKind="finished", remaining=0, turnUncertain=true})), "warning", "uncertain never finished")
eq(S.idle(job({pauseKind="paused", turnUncertain=true})), "warning", "uncertain defeats intentional pause")
eq(S.idle(job({pauseKind="finished", remaining=0, records={}})), "paused", "empty cannot finish")
eq(S.idle(job({remaining=0, records={}})), "ready", "empty zero counter ready")
eq(S.idle(job({pauseReason="Reviewed response saved. Resume when ready."})), "paused", "review save")
eq(S.idle(job({pauseReason="One-screen test complete. 4 screens saved; 3 remain in this batch."})), "paused", "successful test")
eq(S.idle(job({pauseReason="One-screen test complete. 4 screens saved; 0 remain in this batch.", remaining=0})), "finished", "test completed batch")
eq(S.idle(job({pauseReason="Saved-source review cancelled. No navigation reference or page was changed."})), "paused", "review cancelled")
eq(S.idle(job({pauseReason="Recovery cancelled before New job."})), "paused", "manual recovery cancelled")
eq(S.idle(job({pauseReason="Scheduled auto-resume stopped: source changed"})), "warning", "scheduled failure")
eq(S.idle(job({pauseReason="Paused after an unknown failure"})), "warning", "no broad paused-prefix allowlist")

eq(S.bookTitle(nil), "No book loaded", "empty menu title")
eq(S.bookTitle(job({bookTitle="  Full\nJapanese 日本語 title Vol. 107  "})), "Full Japanese 日本語 title Vol. 107", "full title retained")
eq(S.bookTitle(job({bookTitle="", folderName="Book-Named Vol. 09"})), "Named Vol. 09", "folderName fallback")
eq(S.bookTitle(job({bookTitle=""})), "Example Vol. 07", "folder basename fallback")
eq(S.bookTitle({folder="/books/Book-Trailing Vol. 08/"}), "Trailing Vol. 08", "trailing slash fallback")
eq(S.bookTitle({}), "Untitled book", "missing metadata")
local named = job()
eq(S.view(named).startLabel, "Start / resume — Example Vol. 07 (Ctrl-Option-Cmd-S)", "loaded start label")
named.bookTitle = "Renamed Book Vol. 12"
has(S.view(named).startLabel, "Renamed Book Vol. 12", "renamed title read fresh")
eq(S.view(nil).startLabel, "Start / resume — No book loaded (Ctrl-Option-Cmd-S)", "no loaded book is honest")

for phase, expected in pairs({
    ["turn-focus"]="turning", ["turn-hover"]="turning", turn="turning", ["turn-release"]="turning",
    settle="turning", ["advance-ready"]="turning", wait="translating", send="translating",
    ["copy-click"]="saving", clipboard="saving", saved="saving", ["response-scroll"]="saving",
    preflight="checking", ["submit-check"]="checking", ["paste-inline"]="checking",
}) do eq(S.view(job({pauseKind="warning"}), {running=true, phase=phase}).kind, expected, "active " .. phase) end
eq(S.view(job(), {recoveryActive=true}).kind, "checking", "recovery")
eq(S.view(job(), {resuming=true}).kind, "checking", "resume preflight")
eq(S.view(job({autoResume={active=true}, pauseKind="warning"})).kind, "scheduled", "armed timer")
eq(S.view(job({autoResume={active=false}, pauseKind="warning"})).kind, "warning", "cancel retains warning")
eq(S.view(job({autoResume={active=true}}), {recoveryActive=true}).kind, "checking", "active preflight beats scheduled")
local currentBuild = {folder=named.folder, status="failed", error="Disk write failed"}
local warning = S.view(named, {running=true, phase="wait", illustrationBuild=currentBuild})
eq(warning.kind, "warning", "renderer failure visible while translation runs")
has(warning.tooltip, "Disk write failed", "renderer reason")
eq(named.pauseKind, nil, "view leaves persisted state untouched")
currentBuild.folder="/books/another-book"
eq(S.view(named, {running=true, phase="wait", illustrationBuild=currentBuild}).kind, "translating", "unrelated output failure ignored")
currentBuild.folder=named.folder; currentBuild.status="running"
eq(S.view(named, {illustrationBuild=currentBuild}).kind, "saving", "idle rendering")
local pausedWarning = job({pauseKind="warning", pauseReason="Page turn failed"})
local warningDuringBuild = S.view(pausedWarning, {illustrationBuild=currentBuild})
eq(warningDuringBuild.kind, "warning", "background rendering cannot hide paused failure")
has(warningDuringBuild.tooltip, "Page turn failed", "paused failure reason retained during rendering")
eq(S.view(job({turnUncertain=true}), {illustrationBuild=currentBuild}).kind, "warning", "background rendering cannot hide uncertain turn")
eq(S.view(named, {running=true, phase="wait", illustrationBuild=currentBuild}).kind, "translating", "translation takes priority over rendering")
eq(S.view(named, {warning="Current action failed", running=true, illustrationBuild=currentBuild}).kind, "warning", "session warning priority")
has(S.view(named, {warning="Current action failed"}).tooltip, "Current action failed", "session warning reason")
local state = S.view(job({pauseKind="warning", pauseReason="Copy failed"}))
eq(state.menuTitle, "BT warning", "warning menu")
eq(state.label, "Warning", "warning label")
has(state.tooltip, "Book: Example Vol. 07", "book tooltip")
has(state.tooltip, "Saved screens: 1", "saved tooltip")
has(state.tooltip, "Remaining in batch: 3", "remaining tooltip")
has(state.tooltip, "Copy failed", "warning tooltip")
eq(S.view(job({remaining=0, pauseReason=completed})).menuTitle, "BT finished", "finished menu")
eq(S.view(job({pauseReason=stopped})).menuTitle, "BT paused", "intentional paused menu")
has(S.view(job({turnUncertain=true})).tooltip, "last page turn needs review", "uncertain reason")
local function records(count)
    local result = {}
    for i=1,count do result[i]={index=i} end
    return result
end
local function progressCheck(value, savedCount, remaining, total, percent, message)
    local progress = S.progress(value)
    eq(progress.saved, savedCount, message .. " saved")
    eq(progress.remaining, remaining, message .. " remaining")
    eq(progress.total, total, message .. " target")
    eq(progress.percent, percent, message .. " percent")
end
progressCheck(nil, 0, 0, 0, 0, "no job")
progressCheck(job({records={}, remaining=0}), 0, 0, 0, 0, "empty zero target")
progressCheck(job({records={}, remaining=20, pending={index=1, sent=true}}), 0, 20, 20, 0, "first reply pending")
progressCheck(job({records=records(3), remaining=7}), 3, 7, 10, 30, "exact fraction")
progressCheck(job({records=records(2), remaining=1}), 2, 1, 3, 66, "fraction floors")
progressCheck(job({records=records(999), remaining=1}), 999, 1, 1000, 99, "near complete")
progressCheck(job({records=records(999), remaining=0.1}), 999, 1, 1000, 99, "positive remaining cannot round to completion")
progressCheck(job({records=records(10), remaining=0}), 10, 0, 10, 100, "completed target")
progressCheck(job({records=records(139), remaining=20}), 139, 20, 159, 87, "previous pages plus new batch")
progressCheck(job({records=records(140), remaining=19, pending={index=141, sent=true}}), 140, 19, 159, 88, "commit increases progress pending ignored")
local extended = job({records=records(139), remaining=0})
eq(S.progress(extended).percent, 100, "completed before extension")
extended.remaining = 139
eq(S.progress(extended).percent, 50, "new target recomputed without stale progress")
for _, row in ipairs({
    {phase="wait", kind="translating", label="Translating"},
    {phase="turn", kind="turning", label="Turning page"},
    {phase="preflight", kind="checking", label="Checking"},
    {phase="clipboard", kind="saving", label="Saving"},
}) do
    local active = S.view(job(), {running=true, phase=row.phase})
    eq(active.kind, row.kind, "kind remains machine readable " .. row.kind)
    eq(active.menuTitle, "BT " .. row.kind .. " (25%)", "menu progress " .. row.kind)
    eq(active.label, row.label .. " (25%)", "label progress " .. row.kind)
    eq(active.progress.total, 4, "view progress target " .. row.kind)
    has(active.tooltip, "Job target: 4 screens (25% saved)", "tooltip job target " .. row.kind)
end
eq(S.view(job(), {resuming=true}).menuTitle, "BT checking (25%)", "resume checking progress")
eq(S.view(job(), {recoveryActive=true}).menuTitle, "BT checking (25%)", "recovery checking progress")
eq(S.view(named, {illustrationBuild=currentBuild}).menuTitle, "BT saving (25%)", "rendering progress")
eq(S.view(job({remaining=0}), {illustrationBuild=currentBuild}).menuTitle, "BT saving (100%)", "final rendering complete progress")
eq(S.view(nil, {resuming=true}).menuTitle, "BT checking (0%)", "no job active safe")
eq(S.view(job({records={}, remaining=0}), {running=true}).menuTitle, "BT checking (0%)", "zero target active safe")
eq(S.view(job({pauseKind="paused"})).menuTitle, "BT paused", "paused menu unchanged")
eq(S.view(job({pauseKind="paused"})).label, "Paused", "paused label unchanged")
eq(S.view(job({pauseKind="warning"})).menuTitle, "BT warning", "warning menu unchanged")
eq(S.view(job({pauseKind="warning"})).label, "Warning", "warning label unchanged")
eq(S.view(job({remaining=0})).menuTitle, "BT finished", "finished menu unchanged")
eq(S.view(job({autoResume={active=true}})).menuTitle, "BT scheduled", "scheduled menu unchanged")
eq(S.view(nil).menuTitle, "BT ready", "ready menu unchanged")
print("Status and progress policy: " .. checks .. " checks passed")
