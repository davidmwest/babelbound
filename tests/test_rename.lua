local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local R = require("gemini_book_rename")
local N = require("gemini_book_names")
local count = 0
local function test(value, label) count=count+1; assert(value, label) end
local function encode(v)
    if type(v)=="string" then return string.format("%q",v) end
    if type(v)~="table" then return tostring(v) end
    local keys,out={},{}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    for _,k in ipairs(keys)do out[#out+1]="["..encode(k).."]="..encode(v[k]) end
    return "{"..table.concat(out,",").."}"
end
local function decode(s) return assert(load("return "..s,"fixture","t",{}))() end
local root,old,new="/fixture/books","/fixture/books/Book-123","/fixture/books/Book-Example - Vol. 07"
local function fixture()
    local f={}
    local function add(path,mode,data)f[path]={mode=mode,data=data}end
    add(root,"directory");add(old,"directory")
    for _,rel in ipairs({"turns","turns/one","turns/two","collection","collection/00003","recovery","recovery/review","sources"})do add(old.."/"..rel,"directory")end
    local job={folder=old,tag="unique-tag",remaining=40,needAdvance=false,turnUncertain=false,
        records={{index=1,id="stable-1",text="Book prose "..old,sourceHash="hash1",modelKey="flash"},
            {index=2,id="stable-2",text="Second prose",sourceHash="hash2",modelKey="pro"}},
        pending={index=3,id="stable-3",sent=true,sourceHash="hash3",requestText="Never edit "..old},
        lastTurnFolder=old.."/turns/two",lastCollectionFolder=old.."/collection/00003",lastRecoveryFolder=old.."/recovery/review",
        autoResume={active=false,snapshot=old.."|2|40|stable-3|true",status="Cancelled"},
        benchmarkBaseline={sourceFolder=old.."/historical"}}
    add(old.."/checkpoint.json","file",encode(job))
    add(old.."/turns/one/trace.json","file",encode({folder=old.."/turns/one",beforeImage=old.."/sources/00001.png",sourceHash="hash1",note="historical "..old}))
    add(old.."/turns/two/trace.json","file",encode({folder=old.."/turns/two",beforeImage=old.."/sources/00002.png",sourceHash="hash2"}))
    add(old.."/collection/00003/trace.json","file",encode({id="stable-3",folder=old.."/collection/00003",raw="text "..old}))
    add(old.."/recovery/review/checkpoint-before.json","file",encode(job))
    add(old.."/recovery/review/review.json","file",encode({originalPath=old.."/sources/00002.png",snapshot="evidence"}))
    add(old.."/clone-baseline.json","file",encode({destination=old}))
    add(old.."/sources/00001.png","file","PNG bytes")
    add(old.."/translation.html","file",'<img src="sources/00001.png">Book prose')
    local fs={}
    fs.symlinkAttributes=function(path)return f[path] and {mode=f[path].mode}end
    fs.mkdir=function(path)
        if f[path] then return nil,"Already exists" end
        local parent=path:match("^(.*)/[^/]+$")
        if not f[parent] or f[parent].mode~="directory"then return nil,"No parent"end
        add(path,"directory");return true
    end
    fs.dir=function(path)
        assert(f[path] and f[path].mode=="directory","Not a directory: "..path)
        local children={}
        for p in pairs(f)do
            if p:sub(1,#path+1)==path.."/"and not p:sub(#path+2):find("/",1,true)then children[#children+1]=p:sub(#path+2)end
        end
        table.sort(children); local i=0
        return function()i=i+1;return children[i]end
    end
    local moveCount=0
    local function move(a,b)
        if f[b] then return nil,"Exclusive target collision"end
        if not f[a]then return nil,"Missing source"end
        local changes={}
        for p,item in pairs(f)do if p==a or p:sub(1,#a+1)==a.."/"then changes[p]=item end end
        for p,item in pairs(changes)do f[b..p:sub(#a+1)]=item;f[p]=nil end
        moveCount=moveCount+1;return true
    end
    local o={root=root,fs=fs,encode=encode,decode=decode,transactionId="test-001",timestamp="2026-09-23T18:00:00Z",
        readFile=function(path)return f[path]and f[path].mode=="file"and f[path].data or nil end,
        writeFile=function(path,data)add(path,"file",data);return true end,
        removeFile=function(path)f[path]=nil;return true end,
        replaceFile=function(a,b)
            if not f[a]then return nil,"Missing temporary file"end
            f[b]=f[a];f[a]=nil;return true
        end,moveNoReplace=move}
    return f,o,job,function()return moveCount end,add
end
local function parsed(f,path)return f[path]and decode(f[path].data)end
local function manifest(f)return parsed(f,root.."/.job-renames/test-001/manifest.json")end

do
    local f,o,j,moves=fixture();local before={}
    for p,x in pairs(f)do before[p]=x.data end
    local receipt,err=R.rename(old,"Example : Vol. 07",o)
    test(receipt and not err,"successful rename")
    test(receipt.folder==new and receipt.status=="committed"and receipt.changedFiles==4,"complete receipt")
    test(not f[old]and f[new]and moves()==1,"exactly one folder move")
    local after=parsed(f,new.."/checkpoint.json")
    test(after.bookTitle=="Example - Vol. 07"and after.folderName=="Book-Example - Vol. 07","metadata assigned")
    test(encode(after.records)==encode(j.records),"all saved prose, IDs, hashes, model provenance unchanged")
    test(encode(after.pending)==encode(j.pending)and after.pending.sent,"pending request untouched")
    test(after.remaining==40 and after.tag==j.tag and after.needAdvance==false and after.turnUncertain==false,"counter and turn state untouched")
    test(after.lastTurnFolder==new.."/turns/two"and after.lastCollectionFolder==new.."/collection/00003","operational checkpoint paths moved")
    test(after.autoResume.active==false and after.autoResume.snapshot==new.."|2|40|stable-3|true","inactive snapshot prefix moved without arming")
    test(after.benchmarkBaseline.sourceFolder==j.benchmarkBaseline.sourceFolder,"historical provenance untouched")
    local trace=parsed(f,new.."/turns/one/trace.json")
    test(trace.folder==new.."/turns/one"and trace.beforeImage==new.."/sources/00001.png","turn retry paths moved")
    test(trace.note=="historical "..old,"trace free text unchanged")
    for _,rel in ipairs({"recovery/review/checkpoint-before.json","recovery/review/review.json","clone-baseline.json","sources/00001.png","translation.html"})do
        test(f[new.."/"..rel].data==before[old.."/"..rel],"immutable bytes "..rel)
    end
    local log=manifest(f)
    test(log.status=="committed"and log.oldFolder==old and log.newFolder==new and #log.files==4,"complete crash journal")
    for _,entry in ipairs(log.files)do
        test(f[receipt.journal.."/"..entry.original].data==before[old.."/"..entry.relative],"exact original journal "..entry.relative)
        test(f[receipt.journal.."/"..entry.staged].data==f[new.."/"..entry.relative].data,"exact staged journal "..entry.relative)
    end
end
do
    local f,o=fixture();f[new]={mode="directory"}
    local r=R.rename(old,"Example : Vol. 07",o)
    test(r and r.folder==new.." (2)","collision suffix preserves existing directory")
    test(f[new].mode=="directory","existing directory untouched")
end
do
    local f,o,j,moves=fixture()
    local r=R.rename(old,"123",o)
    test(r and r.folder==old and moves()==0,"same folder metadata update makes no move")
    test(parsed(f,old.."/checkpoint.json").bookTitle=="123","same folder metadata saved")
end
do
    local f,o=fixture();local original=f[old.."/checkpoint.json"].data
    o.moveNoReplace=function(a,b)f[b]={mode="directory",foreign=true};return nil,"Exclusive target collision"end
    local r,why,state=R.rename(old,"Example : Vol. 07",o)
    test(not r and why:find("collision",1,true),"race-created destination rejected")
    test(f[new].foreign and f[old.."/checkpoint.json"].data==original,"race target and original preserved")
    test(state.status=="rolled-back"and manifest(f).status=="rolled-back","race failure journal")
end
for _,failRelative in ipairs({"checkpoint.json","turns/two/trace.json"})do
    local f,o=fixture();local before={}
    for p,x in pairs(f)do before[p]=x.data end
    local replace=o.replaceFile;local failed=false
    o.replaceFile=function(a,b)
        if not failed and b==new.."/"..failRelative then failed=true;return nil,"Injected replacement failure"end
        return replace(a,b)
    end
    local r,why,state=R.rename(old,"Example : Vol. 07",o)
    test(not r and why:find("Injected",1,true)and state.status=="rolled-back","replacement failure rolled back "..failRelative)
    test(f[old]and not f[new],"folder restored "..failRelative)
    for p,bytes in pairs(before)do test(f[p]and f[p].data==bytes,"all original bytes restored "..p)end
    test(manifest(f).status=="rolled-back","rollback recorded "..failRelative)
end
do
    local f,o=fixture();local write=o.writeFile
    o.writeFile=function(p,data)if p:find("/staged/",1,true)then return nil,"Injected staging failure"end return write(p,data)end
    local r,_,state=R.rename(old,"Example : Vol. 07",o)
    test(not r and state.status=="rolled-back"and f[old]and not f[new],"journal failure makes no job change")
end
do
    local f,o=fixture();local replace=o.replaceFile
    o.replaceFile=function(a,b)
        local ok=replace(a,b)
        if b:match("/manifest%.json$") and parsed(f,b).status=="prepared"then
            local updated=parsed(f,old.."/checkpoint.json");updated.remaining=39
            f[old.."/checkpoint.json"].data=encode(updated)
        end
        return ok
    end
    local r,why=R.rename(old,"Example : Vol. 07",o)
    test(not r and why:find("changed before rename",1,true),"concurrent checkpoint update detected")
    test(parsed(f,old.."/checkpoint.json").remaining==39 and not f[new],"concurrent writer preserved")
end
do
    local f,o=fixture();local replace=o.replaceFile
    o.replaceFile=function(a,b)
        if b==new.."/turns/two/trace.json"or a:find("-rollback",1,true)then return nil,"Injected rollback failure"end
        return replace(a,b)
    end
    local r,why,state=R.rename(old,"Example : Vol. 07",o)
    test(not r and state.status=="recovery-required"and why:find("requires attention",1,true),"rollback failure explicit")
    test(f[new]and not f[old]and manifest(f).status=="recovery-required","recovery journal retains moved location and originals")
end
for _,bad in ipairs({"/fixture/books/sub/Book-123","/fixture/else/Book-123","/fixture/books/Book-../x","/fixture/books/../Book-123"})do
    local _,o=fixture();local r=R.rename(bad,"title",o);test(not r,"reject noncanonical/nonchild path "..bad)
end
for _,path in ipairs({root,old,old.."/checkpoint.json",old.."/turns/one/trace.json"})do
    local f,o=fixture();f[path].mode="link";local r=R.rename(old,"title",o)
    test(not r and not f[root.."/Book-title"],"reject operational symlink "..path)
end
do
    local f,o=fixture();local j=parsed(f,old.."/checkpoint.json");j.autoResume.active=true;f[old.."/checkpoint.json"].data=encode(j)
    local r,why=R.rename(old,"title",o);test(not r and why:find("scheduled auto-resume",1,true),"active auto-resume rejected")
end
do
    local f,o=fixture();local j=parsed(f,old.."/checkpoint.json");j.pending.sent=nil;f[old.."/checkpoint.json"].data=encode(j)
    local r,why=R.rename(old,"title",o);test(not r and why:find("Invalid pending",1,true),"canonical checkpoint validation")
end
do
    local f,o=fixture();o.moveNoReplace=nil;local r,why=R.rename(old,"title",o)
    test(not r and why:find("exclusive",1,true)and f[old],"no unsafe os.rename fallback")
end
do
    local f,o=fixture();f[root.."/.job-renames"]={mode="directory"};f[root.."/.job-renames/test-001"]={mode="directory"}
    f[root.."/.job-renames/test-001/manifest.json"]={mode="file",data=encode({oldFolder=old,newFolder=new,status="committed"})}
    local r,why=R.rename(old,"title",o);test(not r and why:find("already exists",1,true)and f[old],"transaction ID cannot overwrite journal")
end
for _,status in ipairs({"staging","prepared","moving","writing","recovery-required"})do
    local f,o=fixture();local path=root.."/.job-renames/previous"
    f[root.."/.job-renames"]={mode="directory"};f[path]={mode="directory"}
    f[path.."/manifest.json"]={mode="file",data=encode({oldFolder=old,newFolder=new,status=status})}
    local r,why=R.rename(old,"title",o)
    test(not r and why:find("unresolved rename",1,true)and f[old],"reject prior interrupted transaction "..status)
end
for _,status in ipairs({"committed","rolled-back"})do
    local f,o=fixture();local path=root.."/.job-renames/previous"
    f[root.."/.job-renames"]={mode="directory"};f[path]={mode="directory"}
    f[path.."/manifest.json"]={mode="file",data=encode({oldFolder=old,newFolder=new,status=status})}
    local r=R.rename(old,"Example : Vol. 07",o)
    test(r and r.status=="committed","resolved prior journal permitted "..status)
end
do
    local f,o=fixture();local path=root.."/.job-renames/previous"
    f[root.."/.job-renames"]={mode="directory"};f[path]={mode="directory"}
    f[path.."/manifest.json"]={mode="file",data=encode({oldFolder=root.."/Book-unrelated",newFolder=root.."/Book-other",status="recovery-required"})}
    local r=R.rename(old,"Example : Vol. 07",o)
    test(r and r.status=="committed","unresolved journal for another job does not block this job")
end
for _,which in ipairs({"root","transaction","manifest"})do
    local f,o=fixture();local path=root.."/.job-renames/previous"
    f[root.."/.job-renames"]={mode="directory"};f[path]={mode="directory"}
    f[path.."/manifest.json"]={mode="file",data=encode({oldFolder=old,newFolder=new,status="committed"})}
    f[which=="root"and root.."/.job-renames"or which=="transaction"and path or path.."/manifest.json"].mode="link"
    local r=R.rename(old,"Example : Vol. 07",o)
    test(not r and f[old]and not f[new],"reject journal symlink "..which)
end
for _,failStatus in ipairs({"staging","prepared","writing","committed"})do
    local f,o=fixture();local write=o.writeFile;local failed=false
    local before=f[old.."/checkpoint.json"].data
    o.writeFile=function(path,data)
        if not failed and path:find("manifest.json.rename-",1,true)and decode(data).status==failStatus then
            failed=true;write(path,"partial bytes");return nil,"Injected manifest failure"
        end
        return write(path,data)
    end
    local r,why,state=R.rename(old,"Example : Vol. 07",o)
    test(not r and state.status=="rolled-back"and why:find("Injected manifest",1,true),"late/early manifest failure rollback "..failStatus)
    test(f[old.."/checkpoint.json"].data==before and not f[new],"manifest failure original preserved "..failStatus)
    test(manifest(f).status=="rolled-back","manifest failure final recovery status "..failStatus)
    local temporary=false
    for path in pairs(f)do if path:find(".rename-",1,true)then temporary=true end end
    test(not temporary,"failed write temporaries removed "..failStatus)
end
print("Job rename transaction: "..count.." assertions passed")
