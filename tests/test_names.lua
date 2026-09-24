local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local N = dofile(paths.source("gemini_book_names.lua"))
local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, (label or "check") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function truth(value, label) equal(not not value, true, label) end
local function reject(fn, label)
    local result, reason = fn()
    equal(result, nil, label)
    truth(type(reason) == "string" and #reason > 0, label .. " has reason")
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

equal(N.cleanTitle("  The Glass Harbor — Vol. 6  "),
    "The Glass Harbor — Vol. 6", "readable title")
equal(N.cleanTitle("架空の冒険。６【電子特典付き】"), "架空の冒険。６【電子特典付き】", "Japanese volume preserved")
equal(N.cleanTitle("  The Book: Part 1 / Part 2\\Bonus?  "), "The Book - Part 1 - Part 2 - Bonus", "file separators")
equal(N.cleanTitle(".  My\nBook\tVol. 7... "), "My Book Vol. 7", "trim and collapse")
equal(N.cleanTitle("雪\194\160の\227\128\128女王"), "雪 の 女王", "Unicode whitespace")
equal(N.cleanTitle("Book\226\128\1746\226\128\172"), "Book6", "bidi formatting removed")
equal(N.cleanTitle("Book\0Six"), "Book Six", "control byte made readable")
equal(N.cleanTitle("Book-Title"), "Book-Title", "legitimate title prefix unchanged")
equal(N.cleanTitle("A | B <special> * bonus \"edition\""), "A B special bonus edition", "reserved characters")
for _, bad in ipairs({"", "  ", "...", " / : ", "\0\127", "\255", "\226\130", "\237\160\128", "\192\175"}) do
    reject(function() return N.cleanTitle(bad) end, "invalid or uninformative title")
end
reject(function() return N.cleanTitle({}) end, "nonstring title")
local long = string.rep("漢", 100) .. "終"
local cleaned = assert(N.cleanTitle(long))
equal(#cleaned, 195, "UTF-8 bound exact")
equal(utf8.len(cleaned), 65, "UTF-8 truncation intact")
equal(N.cleanTitle(string.rep("x", 195).."🐈"), string.rep("x",195), "multibyte tail excluded whole")

equal(N.titleFromWindow("架空の冒険。６【電子特典付き】 - You're sharing this tab with Gemini for the duration of this conversation - Google Chrome - Example Profile"),
    "架空の冒険。６【電子特典付き】", "live Chrome suffix")
equal(N.titleFromWindow("A - B - Google Chrome"), "A - B", "bare browser suffix")
equal(N.titleFromWindow("A - You're sharing this tab with Gemini - Google Chrome - Profile 2"), "A", "short sharing suffix")
equal(N.titleFromWindow("A - Google Chrome - B - Google Chrome - Example Profile"), "A - Google Chrome - B", "last browser suffix only")
equal(N.titleFromWindow("A - Something unrelated"), "A - Something unrelated", "unrecognized suffix retained")
equal(N.titleFromWindow("A Google Chrome Inside"), "A Google Chrome Inside", "Chrome title words retained")
equal(N.titleFromWindow("A - You're sharing secrets"), "A - You're sharing secrets", "sharing book prose retained")
reject(function() return N.titleFromWindow(false) end, "missing window title")

local root = "/tmp/Books"
local occupied = {[root.."/Book-Volume 6"]=true,[root.."/Book-Volume 6 (2)"]=true}
local path, title = N.folderFor(root.."/", "Volume 6", function(p) return occupied[p] end)
equal(path, root.."/Book-Volume 6 (3)", "collision keeps every existing folder")
equal(title, "Volume 6", "metadata excludes collision suffix")
equal(N.folderFor(root, "Volume 6", function(p) return occupied[p] end, root.."/Book-Volume 6"),
    root.."/Book-Volume 6", "same current folder allowed")
equal(N.folderFor(root, "Volume 6", function(p) return occupied[p] end, root.."/Book-Volume 6 (2)"),
    root.."/Book-Volume 6 (2)", "same numbered current folder allowed")
equal(N.folderFor(root, "VOLUME 6", function(p) return p:lower() == (root.."/Book-Volume 6"):lower() end),
    root.."/Book-VOLUME 6 (2)", "caller filesystem case policy")
local seen = {}
local bounded = assert(N.folderFor(root, long, function(p) seen[#seen+1]=p;return #seen < 12 end))
equal(#bounded:match("[^/]+$"), 199, "two-digit suffix stays within byte bound")
truth(utf8.len(bounded), "suffixed Unicode path remains valid")
equal(bounded:sub(-5), " (12)", "collision ordinal")
equal(#seen, 12, "tested each candidate")
equal(N.folderFor("/", "Title", function() return false end), "/Book-Title", "root path")
reject(function() return N.folderFor("relative", "Title", function() return false end) end, "relative output root")
reject(function() return N.folderFor("/tmp/../other", "Title", function() return false end) end, "unresolved output root")
reject(function() return N.folderFor(root, "Title", nil) end, "missing existence check")
reject(function() return N.folderFor(root, "Title", function() error("read failed") end) end, "failed existence check")
reject(function() return N.folderFor(root, "Title", function() return true end) end, "bounded collision search")

local old, new = root.."/Book-20260923", root.."/Book-Volume 6"
local job = {
    folder=old, sourceWindowTitle="Window - Google Chrome - Example Profile", bookTitle="Old title", tag="FIXTURE-REQUEST",
    remaining=39, needAdvance=true, turnUncertain=false, requestMode="inline", lastSourceHash="hash-saved",
    records={{index=1,id="FIXTURE-REQUEST-00001",text="Unchanged "..old.."/fiction",sourceHash="hash-original",folder=old.."/records-history"}},
    pending={index=2,id="FIXTURE-REQUEST-00002",sent=true,requestText="Translate "..old.."/reference",sourceHash="hash-pending",folder=old.."/immutable-pending"},
    lastTurnFolder=old.."/turns/00001", lastCollectionFolder=old.."/collection/00001",
    lastRecoveryFolder=old.."/recovery/a", lastTurnRetryFolder=old.."/recovery/b",
    navigationReference={reviewFolder=old.."/recovery/saved",sourceHash="navhash",notes=old.."/prose",reviewedBy="Reviewer"},
    nested={folder=old.."/nested",sourcePath=old.."/sources/1.png",path=old.."-sibling/no.png",html="relative/translation.html"},
    autoResume={active=false,snapshot=old.."|1|39|id|true|hash|true|false",dueAt=123,authorizedAt=100},
    benchmarkBaseline={sourceFolder=old,folder=old}, cloneBaseline={folder=old}, provenance={folder=old},
    history={{folder=old}}, runHistory={{folder=old}}, previousFolders={old}, notes=old.."/notes", requestText=old,
}
local snapshot = assert(N.rewritePaths(job, "/unrelated", "/also-unrelated"))
local moved = assert(N.relocate(job,old,new,"Volume 6"))
truth(moved ~= job and moved.pending ~= job.pending and moved.records ~= job.records, "deep copies state")
truth(same(job,snapshot), "source checkpoint unchanged")
equal(moved.folder,new,"checkpoint folder")
equal(moved.bookTitle,"Volume 6","display title")
equal(moved.folderName,"Book-Volume 6","folder metadata")
equal(moved.sourceWindowTitle,job.sourceWindowTitle,"source browser title retained")
for _, key in ipairs({"tag","remaining","needAdvance","turnUncertain","requestMode","lastSourceHash","records","pending",
    "benchmarkBaseline","cloneBaseline","provenance","history","runHistory","previousFolders","notes","requestText"}) do
    truth(same(moved[key],job[key]), "preserved "..key)
end
for _, key in ipairs({"lastTurnFolder","lastCollectionFolder","lastRecoveryFolder","lastTurnRetryFolder"}) do
    equal(moved[key],new..job[key]:sub(#old+1),"operational "..key)
end
equal(moved.navigationReference.reviewFolder,new.."/recovery/saved","review link rebased")
equal(moved.navigationReference.notes,job.navigationReference.notes,"review prose untouched")
equal(moved.navigationReference.sourceHash,"navhash","review approval hash unchanged")
equal(moved.nested.folder,new.."/nested","nested folder")
equal(moved.nested.sourcePath,new.."/sources/1.png","nested source path")
equal(moved.nested.path,old.."-sibling/no.png","prefix boundary")
equal(moved.nested.html,"relative/translation.html","relative path")
equal(moved.autoResume.snapshot,new.."|1|39|id|true|hash|true|false","snapshot first component only")
equal(moved.autoResume.active,false,"inactive timer remains inactive")
equal(moved.autoResume.dueAt,123,"timer deadline unchanged")
equal(moved.autoResume.authorizedAt,100,"timer authorization unchanged")
job.autoResume.active=true
equal(assert(N.relocate(job,old,new,"Volume 6")).autoResume.active,true,"active timer stays active")
job.autoResume.snapshot=old.."-sibling|1|39"
equal(assert(N.relocate(job,old,new,"Volume 6")).autoResume.snapshot,job.autoResume.snapshot,"snapshot prefix boundary")
job.autoResume.snapshot="prefix|"..old.."|1"
equal(assert(N.relocate(job,old,new,"Volume 6")).autoResume.snapshot,job.autoResume.snapshot,"snapshot exact start")
local trace={folder=old.."/turns/1",beforeImage=old.."/sources/1.png",text=old.."/unaltered",snapshot="70:"..old}
local movedTrace=assert(N.rewritePaths(trace,old,new))
equal(movedTrace.folder,new.."/turns/1","trace folder")
equal(movedTrace.beforeImage,new.."/sources/1.png","trace source")
equal(movedTrace.text,trace.text,"trace prose")
equal(movedTrace.snapshot,trace.snapshot,"length-prefixed review snapshot immutable")
reject(function() return N.relocate(job,"/wrong",new,"Volume 6") end,"wrong checkpoint")
reject(function() return N.relocate(job,old,"/","Volume 6") end,"root relocation")
reject(function() return N.relocate(job,old,new,"...") end,"invalid relocation title")
reject(function() return N.rewritePaths(trace,old,"relative") end,"invalid trace root")
print("Job name and relocation checks passed: "..count)
