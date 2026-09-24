local paths=dofile((debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or "").."paths.lua")
local C=require('gemini_book_core')
for _,id in ipairs({'B6F123ABC-00001','B6F123ABC-2-00001','BW20000101-120000-0-00001'}) do
 local req=C.requestText(id)
 assert(req:find('[[BEGIN:'..id..']]',1,true) and req:find('[[END:'..id..']]',1,true))
 local body='[[BEGIN:'..id..']]\nFIRST_SOURCE: 日本語\nLAST_SOURCE: 本文\n[[TEXT]]\nTranslation.\n[[END:'..id..']]'
 assert(C.parse(body,id))
 assert(not C.parse(body,'WRONG-ID'))
end
assert(loadfile(paths.source("gemini_book.lua")))
print('PASS compact/legacy request markers; exact mismatches still rejected; main compiles')
