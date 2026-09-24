-- Transactional job-folder rename. No UI, browser access, or timer changes.
-- moveNoReplace must atomically refuse any existing destination (including a
-- directory). macOS os.rename alone does not provide that guarantee.
local R = {}
local names = require("gemini_book_names")
local savedJobs = require("gemini_book_jobs")

local function readFile(path)
    local f, why = io.open(path, "rb")
    if not f then return nil, why end
    local data = f:read("*a")
    f:close()
    return data
end
local function writeFile(path, data)
    local f, why = io.open(path, "wb")
    if not f then return nil, why end
    local ok, err = f:write(data)
    local closed, closeError = f:close()
    if not ok then return nil, err end
    if not closed then return nil, closeError end
    return true
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function cleanAbsolute(path)
    if type(path) ~= "string" or path:sub(1,1) ~= "/"
        or path:find("[%z\1-\31\127]") or path:find("//",1,true) then return nil end
    path = path:gsub("/+$", "")
    if path == "" then return nil end
    for part in path:gmatch("[^/]+") do if part == "." or part == ".." then return nil end end
    return path
end
local function ownPath(value, oldFolder, newFolder)
    if type(value) ~= "string" then return value end
    if value == oldFolder then return newFolder end
    if value:sub(1,#oldFolder+1) == oldFolder.."/" then return newFolder..value:sub(#oldFolder+1) end
    return value
end
local function operational(relative)
    return relative == "checkpoint.json"
        or relative:match("^turns/[^/]+/trace%.json$")
        or relative:match("^collection/[^/]+/trace%.json$")
end

function R.rename(folder, rawTitle, options)
    local o = options or {}
    local fs, root = o.fs, cleanAbsolute(o.root)
    folder = cleanAbsolute(folder)
    if not root or not folder or folder:sub(1,#root+1) ~= root.."/"
        or not folder:sub(#root+2):match("^Book%-[^/]+$") then
        return nil, "Only a Book- job directly inside the output folder can be renamed."
    end
    if not fs or not fs.symlinkAttributes or not fs.dir or not fs.mkdir
        or type(o.decode) ~= "function" or type(o.encode) ~= "function" then
        return nil, "Missing filesystem or JSON dependencies."
    end
    local read, write = o.readFile or readFile, o.writeFile or writeFile
    local replace, remove = o.replaceFile or os.rename, o.removeFile or os.remove
    local function check(ok, why) if not ok then error(tostring(why or "Filesystem operation failed"), 0) end return ok end
    local function attributes(path) return fs.symlinkAttributes(path) end
    local function directory(path)
        local a = attributes(path)
        check(a and a.mode == "directory", "Expected a real directory: "..path)
    end
    local function encode(value)
        local bytes = o.encode(value)
        check(type(bytes) == "string", "JSON encoding failed")
        return bytes
    end
    local function readJSON(path)
        local bytes, why = read(path)
        check(bytes, why or "Cannot read "..path)
        local value = o.decode(bytes)
        check(type(value) == "table", "Invalid JSON in "..path)
        return value, bytes
    end
    local plan, changed, temporary = {}, {}, {}
    local journal, manifest, newFolder, title, original, moved, committed
    local atomicCount = 0
    local function atomic(path, bytes, label)
        atomicCount = atomicCount + 1
        local temp = path..".rename-"..o.transactionId.."-"..label.."-"..atomicCount
        check(not attributes(temp), "A temporary transaction file already exists: "..temp)
        temporary[#temporary+1] = temp
        check(write(temp, bytes))
        check(read(temp) == bytes, "Transaction write verification failed: "..temp)
        check(replace(temp, path))
    end
    local function record(status, problem)
        manifest.status, manifest.error = status, problem
        manifest.moved = moved or false
        manifest.appliedFiles = #changed
        atomic(journal.."/manifest.json", encode(manifest), "manifest")
    end
    local ok, result = pcall(function()
        directory(root); directory(folder)
        local checkpointAttributes = attributes(folder.."/checkpoint.json")
        check(checkpointAttributes and checkpointAttributes.mode == "file", "The canonical checkpoint must be a regular file.")
        original = readJSON(folder.."/checkpoint.json")
        local problem = savedJobs.problem(original)
        check(not problem, problem)
        check(original.folder == folder, "The checkpoint belongs to a different folder.")
        check(not (original.autoResume and original.autoResume.active), "Cancel scheduled auto-resume before renaming this job.")
        newFolder, title = names.folderFor(root, rawTitle, function(path) return attributes(path) ~= nil end, folder)
        check(newFolder, title)
        check(newFolder == folder or type(o.moveNoReplace) == "function", "An exclusive folder-move implementation is required.")
        check(type(o.transactionId) == "string" and #o.transactionId <= 100
            and o.transactionId:match("^[%w_-]+$"), "A unique safe transaction ID is required.")

        -- A previous interrupted transaction must be reviewed first; replaying
        -- a partially rebased checkpoint could hide the original recovery path.
        local journalRoot = root.."/.job-renames"
        if attributes(journalRoot) then
            directory(journalRoot)
            local journalCount = 0
            for name in fs.dir(journalRoot) do
                if name ~= "." and name ~= ".." then
                    journalCount = journalCount + 1
                    check(journalCount <= 10000, "Rename journal inventory exceeds the safety limit.")
                    check(not name:find("/",1,true), "Invalid rename journal entry")
                    local path = journalRoot.."/"..name
                    local a = attributes(path)
                    check(a and a.mode ~= "link", "Rename journals cannot be symbolic links: "..path)
                    if a.mode == "directory" then
                        local receiptPath = path.."/manifest.json"
                        local ra = attributes(receiptPath)
                        check(ra and ra.mode == "file", "An incomplete rename journal needs review: "..path)
                        local previous = readJSON(receiptPath)
                        check(type(previous.oldFolder) == "string" and type(previous.newFolder) == "string",
                            "An invalid rename journal needs review: "..path)
                        if previous.status ~= "committed" and previous.status ~= "rolled-back" then
                            check(previous.oldFolder ~= folder and previous.newFolder ~= folder
                                and previous.oldFolder ~= newFolder and previous.newFolder ~= newFolder,
                                "An unresolved rename transaction needs review before this job can be renamed: "..path)
                        end
                    end
                end
            end
        end

        -- Inventory without following links. Only live checkpoint/trace files
        -- are mutable; recovery snapshots, raw replies, logs and book prose are
        -- historical evidence, even when they contain the old absolute path.
        local inspected = 0
        local function walk(path, relative, depth)
            check(depth <= 32, "Job folder nesting exceeds the inventory limit.")
            for name in fs.dir(path) do
                if name ~= "." and name ~= ".." then
                    inspected = inspected + 1
                    check(inspected <= 50000, "Job inventory exceeds the safety limit.")
                    check(not name:find("/",1,true), "Invalid directory entry")
                    local child = path.."/"..name
                    local rel = relative == "" and name or relative.."/"..name
                    local a = attributes(child)
                    check(a, "A job file disappeared during inventory: "..rel)
                    if a.mode == "directory" then
                        walk(child, rel, depth+1)
                    elseif operational(rel) then
                        check(a.mode == "file", "Operational JSON cannot be a symlink: "..rel)
                        local value, before = readJSON(child)
                        local after
                        if rel == "checkpoint.json" then
                            check(equal(value, original), "The checkpoint changed during inventory.")
                            after, problem = names.relocate(value, folder, newFolder, title)
                            check(after, problem)
                            check(equal(after.records, value.records) and equal(after.pending, value.pending), "Rename policy changed translation records or the pending request.")
                            check(after.remaining == value.remaining and after.tag == value.tag
                                and after.needAdvance == value.needAdvance and after.turnUncertain == value.turnUncertain,
                                "Rename policy changed translation state.")
                        else
                            after = value
                            after.folder = ownPath(after.folder, folder, newFolder)
                            after.beforeImage = ownPath(after.beforeImage, folder, newFolder)
                        end
                        local bytes = encode(after)
                        -- Avoid rewriting operational files whose values did
                        -- not change merely because JSON key order differs.
                        if not equal(o.decode(before), after) then
                            plan[#plan+1] = {relative=rel, before=before, after=bytes}
                        end
                    end
                end
            end
        end
        walk(folder, "", 0)
        table.sort(plan, function(a,b) return a.relative < b.relative end)
        if not attributes(journalRoot) then check(fs.mkdir(journalRoot)) end
        directory(journalRoot)
        journal = journalRoot.."/"..o.transactionId
        check(not attributes(journal), "The rename transaction ID already exists.")
        check(fs.mkdir(journal)); check(fs.mkdir(journal.."/original")); check(fs.mkdir(journal.."/staged"))
        manifest = {version=1, status="staging", timestamp=o.timestamp, oldFolder=folder,
            newFolder=newFolder, title=title, transactionId=o.transactionId, files={}}
        record("staging")
        for i, entry in ipairs(plan) do
            local key = string.format("%05d.json", i)
            local beforePath, afterPath = journal.."/original/"..key, journal.."/staged/"..key
            check(write(beforePath, entry.before)); check(write(afterPath, entry.after))
            check(read(beforePath) == entry.before and read(afterPath) == entry.after,
                "Cannot verify the rename journal backup.")
            manifest.files[i] = {relative=entry.relative, original="original/"..key, staged="staged/"..key}
        end
        record("prepared")
        for _, entry in ipairs(plan) do
            check(read(folder.."/"..entry.relative) == entry.before, "A job file changed before rename: "..entry.relative)
        end
        directory(folder)
        check(newFolder == folder or not attributes(newFolder), "The destination appeared before rename.")
        record("moving")
        if newFolder ~= folder then check(o.moveNoReplace(folder, newFolder)); moved = true end
        record("writing")
        for _, entry in ipairs(plan) do
            local path = newFolder.."/"..entry.relative
            local a = attributes(path)
            check(a and a.mode == "file" and read(path) == entry.before, "A job file changed during rename: "..entry.relative)
            atomic(path, entry.after, "apply")
            changed[#changed+1] = entry
            record("writing")
        end
        local final = readJSON(newFolder.."/checkpoint.json")
        local expected = names.relocate(original, folder, newFolder, title)
        check(not savedJobs.problem(final) and equal(final, expected), "Final checkpoint verification failed.")
        check(equal(final.records, original.records) and equal(final.pending, original.pending), "Translation content changed during rename.")
        record("committed")
        committed = true
        return {folder=newFolder, oldFolder=folder, job=final, title=title, journal=journal,
            status="committed", changedFiles=#plan}
    end)
    if ok then return result end
    local failure = tostring(result)
    if not committed and journal and manifest then
        local rolledBack, rollbackError = pcall(function()
            local activeFolder = moved and newFolder or folder
            for i=#changed,1,-1 do
                local entry = changed[i]
                local path = activeFolder.."/"..entry.relative
                check(read(path) == entry.after, "Cannot roll back an externally modified file: "..entry.relative)
                atomic(path, entry.before, "rollback")
            end
            -- Failed atomic writes can leave a temporary file behind. Remove
            -- ours before relocating the folder back so its path stays known.
            for _, path in ipairs(temporary) do if attributes(path) then check(remove(path)) end end
            if moved then check(o.moveNoReplace(newFolder, folder)); moved = false end
            record("rolled-back", failure)
        end)
        if not rolledBack then
            local reason = failure.."; rollback requires attention: "..tostring(rollbackError)
            pcall(record, "recovery-required", reason)
            return nil, reason, {status="recovery-required", journal=journal, oldFolder=folder, folder=newFolder}
        end
    end
    for _, path in ipairs(temporary) do if attributes(path) then pcall(remove, path) end end
    return nil, failure, {status=journal and "rolled-back" or "unchanged", journal=journal, oldFolder=folder, folder=folder}
end

return R
