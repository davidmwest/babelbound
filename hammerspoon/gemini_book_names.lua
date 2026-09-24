-- Job names and checkpoint relocation policy. Pure Lua: no UI or file writes.
local N = {MAX_FOLDER_BYTES=200}

local function trim(s) return (s:gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")) end
local function validUTF8(s)
    local ok, count = pcall(utf8.len, s)
    return ok and count ~= nil
end
local function bytePrefix(s, limit)
    if #s <= limit then return s end
    local finish = 0
    for position, cp in utf8.codes(s) do
        local width = #utf8.char(cp)
        if position + width - 1 > limit then break end
        finish = position + width - 1
    end
    return s:sub(1, finish)
end
local function whitespace(cp)
    return cp == 0xA0 or cp == 0x1680 or cp >= 0x2000 and cp <= 0x200A
        or cp == 0x2028 or cp == 0x2029 or cp == 0x202F or cp == 0x205F or cp == 0x3000
end
local function invisible(cp)
    return cp == 0xAD or cp == 0x200B or cp == 0x200E or cp == 0x200F
        or cp >= 0x202A and cp <= 0x202E or cp >= 0x2060 and cp <= 0x206F or cp == 0xFEFF
end

function N.cleanTitle(value)
    if type(value) ~= "string" then return nil, "Enter a book title." end
    if not validUTF8(value) then return nil, "The book title contains invalid UTF-8." end
    local parts = {}
    for _, cp in utf8.codes(value) do
        if cp <= 0x20 or cp >= 0x7F and cp <= 0x9F or whitespace(cp) then
            parts[#parts+1] = " "
        elseif not invisible(cp) then
            parts[#parts+1] = utf8.char(cp)
        end
    end
    local title = table.concat(parts):gsub("[/\\:]+", " - "):gsub('[*?"<>|]', "")
    title = trim(title:gsub("%s+", " "))
    -- A title composed only of separators is not an informative folder name.
    if title == "" or not title:find("[^%s%.%-]") then return nil, "Enter a book title." end
    title = trim(bytePrefix(title, N.MAX_FOLDER_BYTES - #"Book-"))
    if title == "" then return nil, "Enter a book title." end
    return title
end

function N.titleFromWindow(value)
    if type(value) ~= "string" then return nil, "The browser window has no book title." end
    -- Strip only recognizable browser-owned suffixes. Other title dashes survive.
    local title = value:match("^(.*) %- Google Chrome %- .+$")
        or value:match("^(.*) %- Google Chrome$") or value
    title = title:gsub(" %- You're sharing this tab with Gemini for the duration of this conversation%.?$", "")
        :gsub(" %- You're sharing this tab with Gemini%.?$", "")
    return N.cleanTitle(title)
end

local function absoluteFolder(value)
    if type(value) ~= "string" or value:sub(1,1) ~= "/" or not validUTF8(value)
        or value:find("[%z\1-\31\127]") then return nil end
    value = value:gsub("/+$", "")
    if value == "" then return "/" end
    for part in value:gmatch("[^/]+") do
        if part == "." or part == ".." then return nil end
    end
    return value
end

function N.folderFor(root, rawTitle, exists, currentFolder)
    root = absoluteFolder(root)
    if not root then return nil, "The output root must be an absolute folder path." end
    if type(exists) ~= "function" then return nil, "A folder-existence check is required." end
    local title, why = N.cleanTitle(rawTitle)
    if not title then return nil, why end
    currentFolder = currentFolder and absoluteFolder(currentFolder)
    local prefix = root == "/" and "/" or root .. "/"
    for number = 1, 10000 do
        local suffix = number == 1 and "" or " (" .. number .. ")"
        local stem = trim(bytePrefix(title, N.MAX_FOLDER_BYTES - #"Book-" - #suffix))
        local candidate = prefix .. "Book-" .. stem .. suffix
        if candidate == currentFolder then return candidate, title end
        -- The caller supplies the real filesystem's collision/case policy.
        local ok, occupied = pcall(exists, candidate)
        if not ok then return nil, "Cannot check the proposed job folder: " .. tostring(occupied) end
        if not occupied then return candidate, title end
    end
    return nil, "Too many jobs already use this title. Choose a more specific title."
end

local pathFields = {
    folder=true, path=true, sourcePath=true, responsePath=true, outputPath=true,
    reviewFolder=true, lastRecoveryFolder=true, lastTurnFolder=true,
    lastCollectionFolder=true, lastTurnRetryFolder=true, originalPath=true,
    currentPath=true, beforeImage=true, afterImage=true, html=true,
}
local frozenTables = {
    records=true, pending=true, history=true, previousFolders=true, benchmarkBaseline=true,
    cloneBaseline=true, provenance=true,
}
local function rebase(value, oldFolder, newFolder)
    if type(value) ~= "string" then return value end
    if value == oldFolder then return newFolder end
    if value:sub(1, #oldFolder+1) == oldFolder .. "/" then
        return newFolder .. value:sub(#oldFolder+1)
    end
    return value
end
local function copy(value, oldFolder, newFolder, frozen, seen)
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        local freezeChild = frozen or frozenTables[key] or type(key) == "string" and key:match("History$")
        if type(child) == "table" then
            out[key] = copy(child, oldFolder, newFolder, freezeChild, seen)
        elseif not frozen and pathFields[key] then
            out[key] = rebase(child, oldFolder, newFolder)
        else
            out[key] = child
        end
    end
    return out
end

function N.rewritePaths(value, oldFolder, newFolder)
    oldFolder, newFolder = absoluteFolder(oldFolder), absoluteFolder(newFolder)
    if not oldFolder or oldFolder == "/" or not newFolder or newFolder == "/" then
        return nil, "Path relocation requires two absolute job folder paths."
    end
    return copy(value, oldFolder, newFolder, false, {})
end

function N.relocate(job, oldFolder, newFolder, rawTitle)
    oldFolder, newFolder = absoluteFolder(oldFolder), absoluteFolder(newFolder)
    if not oldFolder or oldFolder == "/" or not newFolder or newFolder == "/" then
        return nil, "Job relocation requires two absolute job folder paths."
    end
    if type(job) ~= "table" or job.folder ~= oldFolder then
        return nil, "The checkpoint does not belong to the folder being renamed."
    end
    local title, why = N.cleanTitle(rawTitle)
    if not title then return nil, why end
    local out = copy(job, oldFolder, newFolder, false, {})
    out.folder = newFolder
    out.bookTitle = title
    out.folderName = newFolder:match("([^/]+)$")
    -- Preserve the exact approved/stale snapshot contents and active flag.
    -- Only its first folder component changes; this never arms a timer.
    local plan = out.autoResume
    if type(plan) == "table" and type(plan.snapshot) == "string"
        and plan.snapshot:sub(1, #oldFolder+1) == oldFolder .. "|" then
        plan.snapshot = newFolder .. plan.snapshot:sub(#oldFolder+1)
    end
    return out
end

return N
