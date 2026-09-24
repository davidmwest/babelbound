-- Checkpoint discovery/policy. No UI, network, writes, or job creation here.
local J={}
local function integer(n) return type(n)=="number" and n>=0 and n==math.floor(n) end
function J.problem(j)
    if type(j)~="table" or type(j.records)~="table" then return "Invalid records table"end
    if not integer(j.remaining) then return "Invalid remaining-screen count"end
    if type(j.tag)~="string" or j.tag=="" then return "Missing request tag"end
    local n=0
    for k in pairs(j.records)do
        if not integer(k) or k<1 then return "Invalid saved-screen index"end
        n=n+1
    end
    if n~=#j.records then return "Saved-screen list has gaps"end
    local ids={}
    for i,r in ipairs(j.records)do
        if type(r)~="table" or r.index~=i or type(r.id)~="string" or r.id=="" or ids[r.id] then
            return "Saved-screen sequence or request ID is invalid"
        end
        ids[r.id]=true
    end
    if j.requestMode~=nil and j.requestMode~="inline" and j.requestMode~="skill" then
        return "Unknown request mode"
    end
    if j.pending~=nil then
        local p=j.pending
        if type(p)~="table" or p.index~=#j.records+1 or type(p.id)~="string" or p.id==""
            or type(p.sent)~="boolean" or type(p.sourceHash)~="string" or p.sourceHash=="" then
            return "Invalid pending request (will not guess whether to resend)"
        end
    end
    return nil
end
function J.read(folder,decode,readFile)
    if type(folder)~="string" or folder=="" then return nil,"Missing folder path"end
    local raw=readFile(folder.."/checkpoint.json")
    if not raw then return nil,"Checkpoint file is missing"end
    local ok,j=pcall(decode,raw)
    if not ok then return nil,"Checkpoint JSON could not be decoded"end
    local problem=J.problem(j)
    if problem then return nil,problem end
    return {folder=folder,name=folder:match("([^/]+)/*$") or folder,job=j,saved=#j.records}
end
function J.discover(root,fs,decode,readFile)
    local entries,errors={},{}
    local ok,err=pcall(function()
        for name in fs.dir(root)do
            if name:match("^Book%-.+") and not name:find("/",1,true) then
                local folder=root.."/"..name
                local a=fs.attributes(folder)
                local link=fs.symlinkAttributes and fs.symlinkAttributes(folder)
                if a and a.mode=="directory" and (not link or link.mode~="link") then
                    local c,why=J.read(folder,decode,readFile)
                    if c then entries[#entries+1]=c else errors[#errors+1]=name..": "..tostring(why)end
                end
            end
        end
    end)
    if not ok then errors[#errors+1]=tostring(err)end
    table.sort(entries,function(a,b)
        if (a.saved>0)~=(b.saved>0) then return a.saved>0 end
        local at=type(a.job.updatedAt)=="string" and a.job.updatedAt or ""
        local bt=type(b.job.updatedAt)=="string" and b.job.updatedAt or ""
        if at~=bt then return at>bt end
        return a.name>b.name
    end)
    return entries,table.concat(errors,"; ")
end
function J.select(entries,remembered)
    local recorded,completed
    local count=0
    for _,e in ipairs(entries)do
        if e.folder==remembered then recorded=e end
        if e.saved>0 then count=count+1;completed=e end
    end
    if recorded and recorded.saved>0 then return recorded,"recorded-populated"end
    -- A newer EMPTY attempt cannot silently replace an established book.
    if count==1 then return completed,"only-populated"end
    if count>1 then return nil,"choose-among-populated"end
    if recorded then return recorded,"recorded-empty"end
    if #entries==1 then return entries[1],"only-empty"end
    return nil,#entries==0 and "none" or "choose"
end
return J
