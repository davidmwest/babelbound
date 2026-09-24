-- Pure text matcher: no Hammerspoon, I/O, clicks, retries, model changes or timers.
-- UI wording is NOT an API contract. The Flash-Lite rule is transcribed from
-- the user's September 21, 2026 Chrome screenshot. Keep historical and starter
-- rules distinguished from that directly observed wording.
local L = {}
L.maxBytes = 2200

function L.normalize(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("’", "'"):gsub("‘", "'"):gsub(" ", " ")
        :gsub(" ", " "):gsub("–", "-"):gsub("—", "-")
        :gsub("‑", "-"):gsub("​", ""):gsub("\r", "\n")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

local defaults = {
    {"limit reached. continuing with flash-lite", "fallback", "user-screenshot-2026-09-21"},
    {"limit reached. continuing with flash lite", "fallback", "normalization-variant"},
    {"you've reached your limit on", "historical-model-limit", "reported-2025"},
    {"you have reached your limit on", "model-limit", "starter"},
    {"usage limit reached", "usage", "starter"},
    {"you've reached your usage limit", "usage", "starter"},
    {"you have reached your usage limit", "usage", "starter"},
    {"you've reached your weekly limit", "weekly", "starter"},
    {"you have reached your weekly limit", "weekly", "starter"},
    {"weekly usage limit reached", "weekly", "starter"},
    {"you've reached your five-hour limit", "five-hour", "starter"},
    {"you've reached your 5-hour limit", "five-hour", "starter"},
    {"you've reached your daily limit", "daily", "starter"},
    {"you've reached the limit for this feature", "feature", "starter"},
    {"rate limit exceeded", "rate", "starter"},
    {"too many requests", "rate", "starter"},
    {"gemini is temporarily unavailable", "service", "starter"},
    {"something went wrong", "service", "starter"},
}

-- Prefix matching permits a changing model/date suffix, but rejects "limitless".
local function startsWith(s, prefix)
    if s:sub(1, #prefix) ~= prefix then return false end
    local c = s:sub(#prefix+1, #prefix+1)
    return c == "" or c:match("[%s%p]") ~= nil
end

function L.readPhrases(text)
    local out = {}
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local s = L.normalize(line)
        if s ~= "" and s:sub(1,1) ~= "#" and #s <= 500 then
            out[#out+1] = s
            if #out >= 100 then break end
        end
    end
    return out
end

function L.isTranslation(s)
    if type(s) ~= "string" then return false end
    -- Even an incomplete book reply can contain quota-like quoted dialogue.
    return s:find("[[BEGIN:",1,true) ~= nil or s:find("[[TEXT]]",1,true) ~= nil
        or s:find("[[END:",1,true) ~= nil
end

function L.detect(raw, extras)
    if type(raw) ~= "string" or #raw == 0 or #raw > L.maxBytes
        or L.isTranslation(raw) then return nil end
    local s = L.normalize(raw)
    -- A skill may put a genuine service error in the permitted ERROR wrapper.
    s = s:gsub("^%[%[error:[^%]]+%]%]%s*", "")
    -- Historical upgrade-card heading, not a general substring search.
    s = s:gsub("^continue with google ai ultra%s+", "")
    s = s:gsub("^sorry,%s+", "")
    local function result(prefix, kind, provenance)
        if startsWith(s,prefix) then
            return {text=raw, normalized=s, matchedPrefix=prefix,
                kind=kind, ruleProvenance=provenance}
        end
    end
    for _, rule in ipairs(defaults) do
        local hit = result(rule[1],rule[2],rule[3]); if hit then return hit end
    end
    -- Gemini may rename the fallback. The explicit continuing-service heading
    -- says requests remain available; a generic limit message does not.
    local fallback=s:match('^limit reached%. continuing with ([^%.!]+)')
    if fallback and #fallback<=80 then
        return {text=raw,normalized=s,matchedPrefix='limit reached. continuing with',
            kind='fallback',fallbackModel=fallback,ruleProvenance='continuing-service-heading'}
    end
    for _, phrase in ipairs(extras or {}) do
        local p = L.normalize(phrase)
        if p ~= "" then
            local hit = result(p,"custom","user-supplied"); if hit then return hit end
        end
    end
    return nil
end

function L.isContinuingFallback(event)
    return type(event)=='table' and event.kind=='fallback'
        and not L.normalize(event.text):match('^%[%[error:')
end

-- Inspect only quota-shaped short UI text already reached by the existing
-- scoped scan. No extra full-window traversal. The caller supplies its roots.
function L.fromElement(e, opts, knownRole)
    local get, frame = opts.attr, opts.frame
    local role = knownRole or get(e,"AXRole")
    if role ~= "AXStaticText" and role ~= "AXHeading" and role ~= "AXAlert"
        and role ~= "AXDialog" then return nil end
    local event, field
    for _, k in ipairs({"AXValue","AXTitle","AXDescription"}) do
        event = L.detect(get(e,k), opts.extras)
        if event then field=k;break end
    end
    if not event then return nil end
    -- Only a quota-shaped string needs visibility/frame reads. Normal book
    -- text does not add geometry queries to the existing bounded traversal.
    if get(e,"AXHidden") == true then return nil end
    local f, b = frame(e), opts.bounds
    if not f or not f.w or not f.h or f.w<=0 or f.h<=0 then return nil end
    local cx, cy = f.x+f.w/2, f.y+f.h/2
    if cx<b.x or cx>b.x+b.w or cy<b.y or cy>b.y+b.h then return nil end
    -- Do not classify the draft or a marked translation's descendants as UI.
    -- Never follow ancestors beyond the known scope roots.
    local parent = e
    for _=1,6 do
        if not parent or parent==opts.panel then break end
        if parent==opts.composer then break end
        local pr=get(parent,"AXRole")
        if pr=="AXTextArea" or pr=="AXTextField" or pr=="AXComboBox" then return nil end
        for _,k in ipairs({"AXValue","AXTitle","AXDescription"}) do
            if L.isTranslation(get(parent,k)) then return nil end
        end
        parent=get(parent,"AXParent")
    end
    event.element={role=role,field=field,frame={x=f.x,y=f.y,w=f.w,h=f.h}}
    return event
end
-- The observed title and timestamp are separate AXStaticText siblings. Read
-- only a bounded neighbourhood of the matched card, not the whole chat.
function L.withResetContext(event, element, opts)
    if not event or not element then return event end
    local get, frame=opts.attr,opts.frame
    local ef=frame(element)
    if not ef then return event end
    local root=element
    for _=1,5 do
        local parent=get(root,"AXParent")
        if not parent or parent==opts.panel or parent==opts.composer then break end
        local pf=frame(parent)
        if not pf or not pf.w or not pf.h or pf.h>300 or pf.w>opts.bounds.w+10 then break end
        if pf.x<opts.bounds.x-5 or pf.y<opts.bounds.y then break end
        root=parent
    end
    local stack,seen,texts={{root,0}},{},{}
    local count=0
    while #stack>0 and count<80 do
        local item=table.remove(stack);local e,depth=item[1],item[2]
        if not seen[e] then
            seen[e]=true;count=count+1
            local f=frame(e);local r=get(e,"AXRole")
            if f and f.h and f.w and f.h>0 and f.w>0 and get(e,"AXHidden")~=true
                and math.abs(f.y-ef.y)<220 and f.x>=opts.bounds.x-5
                and r~="AXTextArea" and r~="AXTextField" then
                for _,key in ipairs({"AXValue","AXTitle","AXDescription"})do
                    local v=get(e,key)
                    if type(v)=="string" and #v<=1600 and not L.isTranslation(v)
                        and L.normalize(v):find("limit resets",1,true) then
                        texts[#texts+1]=v
                    end
                end
            end
            if depth<5 and r~="AXTextArea" and r~="AXTextField" then
                for _,child in ipairs(get(e,"AXChildren") or {})do stack[#stack+1]={child,depth+1} end
            end
        end
    end
    if #texts>0 then
        event.heading=event.text
        event.resetText=texts[1]
        event.text=event.text.."\n"..texts[1]
    end
    return event
end

return L
