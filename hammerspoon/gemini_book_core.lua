-- Pure functions, kept separate so the response protocol can be tested without macOS.
local C = {}

function C.trim(s)
    return (tostring(s or ""):gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
end


-- Chrome's Gemini composer may expose its visual hint as AXValue while
-- AXPlaceholderValue is absent. Only exact known hints are normalized, and
-- only by the caller after focus/process/composer verification. This never
-- clears or modifies an editor and never infers emptiness from string length.
function C.composerValue(value, placeholder, knownHints)
    if type(value) ~= "string" then return nil, "unreadable" end
    if value == "" then return "", "empty" end
    if type(placeholder) == "string" and placeholder ~= "" then
        if value == placeholder then return "", "declared-placeholder" end
        -- A contradictory declared placeholder is not overridden by a hint.
        return value, "text"
    end
    if type(knownHints) == "table" then
        for _, hint in ipairs(knownHints) do
            if type(hint) == "string" and hint ~= "" and value == hint then
                return "", "known-hint"
            end
        end
    end
    return value, "text"
end

-- Normalize layout-only differences in Chrome's accessible text. Do NOT
-- remove words, arbitrary punctuation, slash commands, or unknown drafts.
function C.normalizedDraft(value)
    if type(value) ~= "string" then return nil end
    return C.trim(value:gsub("\194\160", " ")  -- NBSP
        :gsub("\239\191\188", "")             -- object replacement (skill chip)
        :gsub("\226\128\139", "")             -- zero-width space
        :gsub("\239\187\191", "")             -- BOM / zero-width no-break space
        :gsub("%s+", " "))
end

-- A raw /ln still in the editor is NOT evidence that the skill was selected.
-- Accepted representations are empty/placeholder-normalized text, its bare
-- chip label, or a label accompanied by an embedded-object marker.
function C.selectedSkillValue(value, skill)
    local s=C.normalizedDraft(value)
    if not s then return false end
    if s=="" or s==skill:gsub("^/", "") then return true end
    return s==skill and value:find("\239\191\188",1,true)~=nil
end

function C.isIdleComposerLabel(label)
    local s=C.trim(label):lower()
    return s=="go live" or s=="send" or s=="send message" or s=="send prompt"
        or s=="submit" or s=="submit prompt" or s=="submit message"
end
-- Strictly restrict reference replacement to the next UNSENT pending screen.
function C.pendingRecoveryProblem(job)
    if type(job)~="table" or type(job.records)~="table" then return "No valid job is loaded." end
    local p=job.pending
    if type(p)~="table" then return "This job has no pending screen. Use Start/resume, not recovery." end
    if p.sent~=false then return "The pending request is already sent or its send state is unknown. Resume to collect it; do not resubmit." end
    if type(p.index)~="number" or p.index~=#job.records+1 then return "Pending index does not follow the saved screens. No changes made." end
    if type(job.remaining)~="number" or job.remaining<1 or job.remaining~=math.floor(job.remaining) then
        return "The batch's remaining-screen count is invalid. No changes made."
    end
    if type(p.id)~="string" or p.id=="" or type(p.sourceHash)~="string" or p.sourceHash=="" then
        return "The pending request is missing its ID or source reference. No changes made."
    end
    if job.needAdvance or job.turnUncertain or job.expectChange then
        return "Navigation is still pending or uncertain; a source-reference replacement is unsafe. No changes made."
    end
    return nil
end
function C.inlineRequestText(id,instructions)
    assert(type(instructions)=="string" and #C.trim(instructions)>=100,"Translation instructions are missing")
    local request=C.requestText(id):gsub("the skill's exact output format", "the exact output format above")
    return C.trim(instructions).."\n\nCURRENT AUTOMATED REQUEST\n"..request
end
function C.requestText(id)
    return "Request ID: " .. id
        .. ". Translate the CURRENT visible book page/spread using the skill's exact output format."
        .. "\nCopy these exact marker lines, preserving every character:\n[[BEGIN:"..id.."]]"
        .. "\nPut the source anchors, [[TEXT]], and complete translation between them."
        .. "\n[[END:"..id.."]]"
end

-- Preserve exact prepared drafts made before the direct-prompt wording change.
-- This only recognizes our suffix; submission still checks the ENTIRE saved
-- request against the current editor immediately before Send.
function C.isPreparedInlineRequest(text,id)
    if type(text)~="string" or type(id)~="string" or id=="" then return false end
    local legacy=C.requestText(id)
    local current=legacy:gsub("the skill's exact output format", "the exact output format above")
    return text:sub(-#legacy)==legacy or text:sub(-#current)==current
end

-- The chip may be included or omitted in AXValue after a paste. Require the
-- ENTIRE request, with at most the prefix observed immediately after skill
-- selection. An ID in an unfinished or unrelated draft is never sufficient.
function C.requestDraftMatches(value, request, prefix)
    local actual=C.normalizedDraft(value)
    local wanted=C.normalizedDraft(request)
    if not actual or not wanted or wanted=="" then return false end
    if actual==wanted then return true end
    local head=C.normalizedDraft(prefix)
    return head~=nil and head~="" and actual==C.normalizedDraft(head.." "..wanted)
end

-- Conservative English-output check, separate from source-language anchors.
-- This detects clearly untranslated prose, not translation accuracy or missing
-- material. Names, short quotations and explicitly labeled notes stay allowed.
function C.translationLanguageIssue(text)
    local function count(s)
        local jp,hira,latin=0,0,0
        for _,code in utf8.codes(s)do
            if code>=0x3041 and code<=0x3096 then jp=jp+1;hira=hira+1
            elseif (code>=0x30A1 and code<=0x30FA) or (code>=0x3400 and code<=0x9FFF)
                or (code>=0xFF66 and code<=0xFF9D) then jp=jp+1
            elseif (code>=65 and code<=90) or (code>=97 and code<=122) then latin=latin+1 end
        end
        return {japanese=jp,hiragana=hira,latin=latin,
            sentence=s:find("。",1,true)~=nil or s:find("！",1,true)~=nil or s:find("？",1,true)~=nil}
    end
    local total={japanese=0,hiragana=0,latin=0,sentence=false}
    for paragraph in (text:gsub("\r\n","\n").."\n\n"):gmatch("(.-)\n%s*\n")do
        local leading=C.trim(paragraph):lower():gsub("’","'"):gsub("%*",""):gsub("^%[","")
        local note=leading:match("^tn%s*:") or leading:match("^translator'?s?%s+note%s*:")
        if not note then
            local ok,counts=pcall(count,paragraph)
            if not ok then return "Cannot validate the English body because its text encoding is invalid." end
            total.japanese=total.japanese+counts.japanese;total.hiragana=total.hiragana+counts.hiragana
            total.latin=total.latin+counts.latin;total.sentence=total.sentence or counts.sentence
            if counts.japanese>=12 and counts.hiragana>=3 and counts.latin<=3 and counts.sentence then
                return "The English translation contains a Japanese prose paragraph; review the untranslated text before saving.",counts
            end
        end
    end
    if total.japanese>=12 and total.hiragana>=3 and total.sentence
        and total.japanese/(total.japanese+total.latin)>=0.6 then
        return "The reply body is predominantly Japanese instead of an English translation; review it before saving.",total
    end
end

function C.parse(raw, id, options)
    local s = C.trim(raw)
    local beginMark = "[[BEGIN:" .. id .. "]]"
    local endMark = "[[END:" .. id .. "]]"
    if s:find("[[ERROR:" .. id .. "]]", 1, true) then
        return nil, "The translator reported a source/translation error", "error"
    end
    if s:sub(1, #beginMark) ~= beginMark then
        return nil, "Not the response for the current request", "other"
    end
    -- A closing prose bracket can land AFTER the bookkeeping marker:
    --     <fragment [continues] [[END:the-exact-request-id]]>
    -- The END token is present; do not mistake this for a truncated response.
    -- Accept only one terminal '>', and below require its unmatched opening
    -- '<' in the last body line. Preserve it in the reading copy. Arbitrary
    -- trailing prose, other markers, or missing/wrong IDs remain failures.
    local endStart = #s - #endMark + 1
    local markerSuffix = ""
    if s:sub(-#endMark) ~= endMark then
        local found, finish = s:find(endMark, #beginMark + 1, true)
        if not found then
            return nil, "Current response has no final completion marker", "incomplete"
        end
        markerSuffix = C.trim(s:sub(finish + 1))
        if markerSuffix ~= ">" then
            return nil, "Completion marker is present but followed by unexpected content", "incomplete"
        end
        endStart = found
    end
    local middle = C.trim(s:sub(#beginMark + 1, endStart - 1))
    local a, b = middle:find("[[TEXT]]", 1, true)
    if not a then return nil, "Missing TEXT delimiter", "incomplete" end
    local header = C.trim(middle:sub(1, a - 1))
    -- Gemini sometimes includes source paragraph breaks INSIDE an anchor.
    -- Accept those only in this delimited metadata header. Never collapse the
    -- translation's paragraph breaks or infer missing markers/anchor labels.
    local first, last = header:match("^FIRST_SOURCE:[ \t]*(.-)\n[ \t]*LAST_SOURCE:[ \t]*(.-)$")
    if not first or not last then
        return nil, "Missing/malformed source anchors: expected FIRST_SOURCE then LAST_SOURCE before TEXT", "incomplete"
    end
    if C.trim(first) == "" or C.trim(last) == "" then
        return nil, "Source anchor is empty", "incomplete"
    end
    for _, anchor in ipairs({first, last}) do
        if anchor:find("FIRST_SOURCE:", 1, true) or anchor:find("LAST_SOURCE:", 1, true)
            or anchor:find("[[", 1, true) then
            return nil, "Duplicate labels or protocol markers in source anchors", "incomplete"
        end
    end
    local anchorLineBreaksNormalized = first:find("\n", 1, true) ~= nil
        or last:find("\n", 1, true) ~= nil
    first = C.trim(first:gsub("[ \t]*\n[ \t]*", " "))
    last = C.trim(last:gsub("[ \t]*\n[ \t]*", " "))
    local text = C.trim(middle:sub(b + 1))
    if text == "" then return nil, "Empty translation", "incomplete" end
    if text:find("[[BEGIN:", 1, true) or text:find("[[END:", 1, true) then
        return nil, "Multiple response blocks; copy only the latest answer", "error"
    end
    if markerSuffix ~= "" then
        local lastLine = text:match("[^\n]*$") or ""
        local balance, crossed = 0, false
        for bracket in lastLine:gmatch("[<>]") do
            balance = balance + (bracket == "<" and 1 or -1)
            if balance < 0 then crossed = true end
        end
        local openTail = lastLine:match("<([^<>]*)$")
        if crossed or balance ~= 1 or not openTail or C.trim(openTail) == "" then
            return nil, "Closing bracket after completion marker has no matching open prose bracket", "incomplete"
        end
        -- Never alter the original copied response or invent missing source
        -- text. Only relocate the existing bracket across the removed token.
        text = text .. markerSuffix
    end
    local languageIssue=C.translationLanguageIssue(text)
    if languageIssue and not (type(options)=="table" and options.allowUntranslatedForEvaluation==true) then
        return nil,languageIssue,"error"
    end
    return {first = C.trim(first), last = C.trim(last), text = text, raw = s,
        anchorLineBreaksNormalized = anchorLineBreaksNormalized,
        endMarkerSuffixNormalized = markerSuffix ~= "",qualityIssue=languageIssue}
end

function C.isCopyLabel(label)
    local s = tostring(label or ""):lower()
    return s:find("copy", 1, true) ~= nil
       and not s:find("link", 1, true)
       and not s:find("code", 1, true)
       and not s:find("table", 1, true)
end

function C.isStopLabel(label)
    local s = C.trim(label):lower()
    return s == "stop" or s:find("stop response", 1, true) ~= nil
        or s:find("stop generating", 1, true) ~= nil
        or s:find("stop generation", 1, true) ~= nil
end

function C.escape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;")
        :gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function imagePath(value)
    return type(value)=="string" and value:match("^illustrations/[%w%._%-/]+$")
        and not value:find("..",1,true) and value or nil
end
local function number(value,low,high)
    return type(value)=="number" and value==value and value>=low and value<=high and value or nil
end
local function color(value,fallback)
    return type(value)=="string" and (value:match("^#%x%x%x%x%x%x$") or value=="transparent") and value or fallback
end
local function positionedPage(entry,index)
    local layout=entry.layout
    local src=imagePath(entry.sourceSrc)
    if type(layout)~="table" or not src or type(layout.pageBox)~="table" or type(layout.blocks)~="table" then return nil end
    local b=layout.pageBox
    local sw,sh=number(entry.sourceWidth,1,30000),number(entry.sourceHeight,1,30000)
    if not sw or not sh or not number(b[1],0,sw) or not number(b[2],0,sh)
        or not number(b[3],0,sw) or not number(b[4],0,sh) or b[3]<=b[1] or b[4]<=b[2] then return nil end
    local w,h=b[3]-b[1],b[4]-b[2]
    local kind=layout.kind=="cover" and "cover" or layout.kind=="character" and "character" or "chapter"
    local out={string.format('<figure class="book-figure %s" id="screen-%d-illustration-1"><div class="original-page" style="aspect-ratio:%.5f/1">',kind,index,w/h),
        string.format('<img class="page-art" src="%s" alt="Original artwork for screen %d" loading="lazy" style="width:%.5f%%;height:%.5f%%;left:%.5f%%;top:%.5f%%">',C.escape(src),index,sw/w*100,sh/h*100,-b[1]/w*100,-b[2]/h*100)}
    for _,mask in ipairs(type(layout.masks)=="table" and layout.masks or {})do
        local x,y,mw,mh=number(mask.x,0,1),number(mask.y,0,1),number(mask.w,0.001,1),number(mask.h,0.001,1)
        if not x or not y or not mw or not mh or x+mw>1.001 or y+mh>1.001 then return nil end
        out[#out+1]=string.format('<span class="text-mask" aria-hidden="true" style="left:%.4f%%;top:%.4f%%;width:%.4f%%;height:%.4f%%;background:%s"></span>',x*100,y*100,mw*100,mh*100,color(mask.background,"#ffffff"))
    end
    for _,block in ipairs(layout.blocks)do
        local x,y,bw,bh=number(block.x,0,1),number(block.y,0,1),number(block.w,0.001,1),number(block.h,0.001,1)
        if not x or not y or not bw or not bh or x+bw>1.001 or y+bh>1.001 or type(block.text)~="string" then return nil end
        local size=number(block.fontSize,0.5,15) or 3
        local leading=number(block.lineHeight,0.8,2) or 1.25
        local family=block.fontFamily=="sans" and "system-ui,sans-serif" or "Georgia,serif"
        local align=block.textAlign=="center" and "center" or block.textAlign=="right" and "right" or "left"
        local weight=block.weight=="bold" and "700" or tostring(number(block.weight,100,900) or 400)
        local role=({title=true,quote=true,profile=true,credit=true,caption=true})[block.role] and block.role or "caption"
        local writingMode=block.writingMode=="vertical-rl" and "vertical-rl" or "horizontal-tb"
        out[#out+1]=string.format('<div class="translated-block %s" style="left:%.4f%%;top:%.4f%%;width:%.4f%%;height:%.4f%%;font-size:%.3fcqw;line-height:%.3f;font-family:%s;font-weight:%s;text-align:%s;color:%s;background:%s;writing-mode:%s;text-orientation:mixed">%s</div>',role,x*100,y*100,bw*100,bh*100,size,leading,family,weight,align,color(block.color,"#17212c"),color(block.background,"#ffffff"),writingMode,C.escape(block.text))
    end
    out[#out+1]=string.format('</div><figcaption>Screen %04d · Illustration 1</figcaption></figure>',index)
    return table.concat(out,"\n")
end
function C.html(records,manifest)
    local illustrations={}
    local models={}
    local function recordModel(r)
        local label=type(r.model)=="string" and C.trim(r.model) or "Unknown"
        if label=="" or label=="unverified" then label="Unknown" end
        local key=type(r.modelKey)=="string" and r.modelKey or label:lower():gsub("%s+","-")
        local keys,labels,seen={key},{[key]=label},{[key]=true}
        local provenance=type(r.modelProvenance)=="table" and r.modelProvenance or {}
        local collection=type(provenance.collectionObservation)=="table" and provenance.collectionObservation or {}
        if type(collection.selectedModelKey)=="string" and type(collection.selectedModel)=="string" then
            labels[collection.selectedModelKey]=collection.selectedModel
        end
        for _,candidate in ipairs(type(r.possibleModelKeys)=="table" and r.possibleModelKeys or {})do
            if type(candidate)=="string" and candidate~="" and not seen[candidate] then
                seen[candidate]=true;keys[#keys+1]=candidate
            end
        end
        if r.modelStatus=="changed-during-generation" and collection.selectedModel then
            label=label.." → "..collection.selectedModel.." (uncertain)"
        end
        return label,key,keys,labels
    end
    for _,r in ipairs(records)do
        local _,_,keys,labels=recordModel(r)
        for _,key in ipairs(keys)do
            models[key]=models[key] or {label=labels[key] or key,count=0}
            models[key].count=models[key].count+1
        end
    end
    if type(manifest)=="table" and type(manifest.records)=="table"then
        for _,entry in ipairs(manifest.records)do
            if type(entry)=="table" and type(entry.screenIndex)=="number"then illustrations[entry.screenIndex]=entry end
        end
    end
    local out = {[[<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Book translation</title><style>
:root{color-scheme:light}*{box-sizing:border-box}body{font:20px/1.65 Georgia,serif;color:#222a32;background:#f6f5f1;
max-width:68rem;margin:2rem auto;padding:0 1.3rem}h1,h2,nav,summary,figcaption{font-family:system-ui,sans-serif}
h1{font-size:1.4rem;font-weight:500}h2{font-size:.8rem;color:#67717b;letter-spacing:.07em;text-transform:uppercase;
margin:3rem auto 1.5rem;border-top:1px solid #d7dbdd;padding-top:1rem;max-width:46rem}
h2{display:flex;justify-content:space-between;flex-wrap:wrap;gap:.25rem 1rem}.model-badge{letter-spacing:0;text-transform:none;font-weight:400;color:#76808a;overflow-wrap:anywhere}.model-controls{font:13px/1.5 system-ui,sans-serif;margin-top:1rem;display:flex;align-items:center;gap:.6rem;flex-wrap:wrap}.model-controls select{font:inherit;padding:.25rem .5rem;color:#384653;background:#fff;border:1px solid #c7ced3;border-radius:4px}section[hidden]{display:none}
.prose{white-space:pre-wrap;overflow-wrap:anywhere;max-width:46rem;margin:0 auto}nav{font-size:.8rem;color:#67717b}
.book-figure{margin:1.5rem auto;max-width:100%}.book-figure img{display:block;width:100%;height:auto}
.book-figure.cover,.book-figure.character{max-width:43rem}.original-page{position:relative;overflow:hidden;background:white;container-type:inline-size;box-shadow:0 6px 28px #17212c14}
.original-page .page-art{position:absolute;max-width:none}.text-mask{position:absolute}.translated-block{position:absolute;white-space:pre-line;overflow:hidden;padding:.45cqw;display:flex;flex-direction:column;justify-content:center}
.translated-block.title{letter-spacing:.015em}.translated-block.quote{font-style:italic}.translated-block.profile{justify-content:flex-start}
figcaption{font-size:.72rem;color:#76808a;text-align:center;padding:.6rem}details.transcript{max-width:46rem;margin:1rem auto 2rem;font-size:1rem}summary{font-size:.8rem;cursor:pointer;color:#67717b}
details .prose{margin-top:1rem}@media(max-width:600px){body{padding:0 .6rem;font-size:18px}.original-page{box-shadow:none}}
@media print{body{background:white;margin:0;max-width:none}.book-figure{break-inside:avoid}.original-page{box-shadow:none}details.transcript{display:none}}
</style><header><h1>Book translation</h1><nav>Screen numbers follow capture order. Illustrations appear with their translated pages.</nav></header>]]}
    out[#out+1]='<div class="model-controls"><label for="model-filter">Show model</label><select id="model-filter"><option value="">All models ('..#records..')</option>'
    local keys={};for key in pairs(models)do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys)do
        local m=models[key]
        out[#out+1]='<option value="'..C.escape(key)..'">'..C.escape(m.label)..' ('..m.count..')</option>'
    end
    out[#out+1]='</select><span id="filter-count" aria-live="polite"></span></div><nav>Model tags combine recorded selections and confirmed history. Uncertain model changes appear under both filters.</nav>'
    for _, r in ipairs(records) do
        local entry=illustrations[r.index]
        -- A manifest from a different source must never decorate this record.
        if entry and entry.sourceHash and entry.sourceHash~=r.sourceHash then entry=nil end
        local page=entry and positionedPage(entry,r.index)
        local model,modelKey,modelKeys=recordModel(r)
        out[#out+1]='<section id="screen-'..r.index..'" data-model="'..C.escape(modelKey)..'" data-models="'..C.escape(table.concat(modelKeys," "))..'"><h2>Screen '..string.format("%04d",r.index)..'<span class="model-badge">Model: '..C.escape(model)..'</span></h2>'
        if page then
            local reviewed=type(entry.layout.transcript)=="string" and C.trim(entry.layout.transcript)~=""
                and entry.layout.transcript or nil
            out[#out+1]=page..'<details class="transcript"><summary>Plain text translation'..(reviewed and ' (reviewed)' or '')..'</summary><div class="prose">'..C.escape(reviewed or r.text)..'</div></details>'
        else
            out[#out+1]='<div class="prose">'..C.escape(r.text)..'</div>'
            if entry and type(entry.illustrations)=="table"then
                for i,item in ipairs(entry.illustrations)do
                    local src=type(item)=="table" and imagePath(item.src)
                    if src then out[#out+1]=string.format('<figure class="book-figure" id="screen-%d-illustration-%d"><img src="%s" alt="Screen %04d, illustration %d" loading="lazy"><figcaption>Screen %04d · Illustration %d</figcaption></figure>',r.index,i,C.escape(src),r.index,i,r.index,i)end
                end
            end
        end
        out[#out+1]='</section>'
    end
    out[#out+1]=[[<script>
document.getElementById('model-filter').addEventListener('change',function(){
  let visible=0;
  document.querySelectorAll('section[data-model]').forEach(page=>{
    page.hidden=Boolean(this.value && !page.dataset.models.split(' ').includes(this.value));
    if(!page.hidden)visible++;
  });
  document.getElementById('filter-count').textContent=visible+' screens shown';
});
</script></html>]]
    return table.concat(out, "\n")
end

function C.markdown(records)
    local out = {"# Book translation\n\nScreen numbers are capture order, not printed page numbers."}
    for _, r in ipairs(records) do
        out[#out + 1] = string.format("## Screen %04d\n\n%s", r.index, r.text)
    end
    return table.concat(out, "\n\n") .. "\n"
end
return C
