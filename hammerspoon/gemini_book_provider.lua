-- Pure provider policy. No UI, files, network, or automatic provider conversion.
local resetClock=require("gemini_book_resume")
local P={}
local definitions={
    gemini={id="gemini",name="Gemini",placeholders={"Type @ to add tabs","Type / to use skills"}},
    chatgpt={id="chatgpt",name="ChatGPT",placeholders={"Do anything","\nDo anything"}},
}
function P.id(value)
    if value==nil then return "gemini" end -- Existing checkpoints belong to Gemini.
    if type(value)=="string" and definitions[value] then return value end
    return nil
end
function P.get(value)
    local id=P.id(value)
    local d=id and definitions[id]
    if not d then return nil end
    -- Callers cannot mutate the global placeholder policy through this result.
    local hints={};for i,hint in ipairs(d.placeholders)do hints[i]=hint end
    return {id=d.id,name=d.name,placeholders=hints}
end
local function identityProblem(selected,value,label)
    local actual=P.id(value)
    if not actual then return label.." has an unknown provider." end
    if actual~=selected then return label.." belongs to "..definitions[actual].name..", not "..definitions[selected].name.."." end
end
function P.problem(provider,job,cal)
    local selected=P.id(provider)
    if not selected then return "Unknown selected provider." end
    for _,entry in ipairs({{value=job,label="Job"},{value=cal,label="Calibration"}})do
        if entry.value~=nil then
            if type(entry.value)~="table" then return entry.label.." is invalid." end
            local problem=identityProblem(selected,entry.value.provider,entry.label)
            if problem then return problem end
        end
    end
    if job then
        if selected=="chatgpt" and job.requestMode=="skill" then
            return "ChatGPT requires inline instructions; Gemini skill mode cannot be resumed here."
        end
        if job.pending~=nil then
            if type(job.pending)~="table" then return "Pending request is invalid." end
            local problem=identityProblem(selected,job.pending.provider,"Pending request")
            if problem then return problem end
            if selected=="chatgpt" and (job.pending.inputMode=="skill" or job.pending.selectionVerified==true) then
                return "The pending request contains Gemini skill preparation; it cannot be sent through ChatGPT."
            end
        end
        -- An old sent identity can later be restored by explicit prior-reply
        -- recovery, so it must remain bound to the same provider as this job.
        if job.priorSentReply~=nil then
            if type(job.priorSentReply)~="table" then return "Prior sent reply is invalid." end
            local problem=identityProblem(selected,job.priorSentReply.provider,"Prior sent reply")
            if problem then return problem end
        end
    end
    return nil
end
local families={astra="Astra",sol="Sol",terra="Terra",luna="Luna"}
local efforts={low="Low",medium="Medium",high="High",["very high"]="Very high",
    ["extra high"]="Extra high",max="Max",ultra="Ultra"}
local versions={["5"]=true,["5.6"]=true,["6"]=true}
function P.modelLabel(provider,label)
    local id=P.id(provider)
    if not id or type(label)~="string" then return nil end
    if id=="gemini" then return resetClock.modelLabel(label) end
    -- Only a complete current-picker caption is recognized. The caller must
    -- independently verify live control role, ancestry, process and location.
    if #label>120 or label:find("[%c]") then return nil end
    local s=label:lower():gsub("^%s+",""):gsub("%s+$",""):gsub(" +"," ")
    local prefixed=s:match("^gpt%-") or s:match("^gpt ")
    if prefixed then s=s:sub(5) end
    local version,family,effort=s:match("^(%d[%d%.]*) ([a-z]+) ([a-z ]+)$")
    if versions[version] and families[family] and efforts[effort] then
        return version.." "..families[family].." "..efforts[effort]
    end
    -- Exact legacy GPT captions remain recognizable without inventing a
    -- family or reasoning setting that was not displayed by the control.
    if prefixed then
        local legacy,level=s:match("^(%d[%d%.]*) ([a-z ]+)$")
        if (legacy=="5" or legacy=="5.6") and efforts[level] then return "GPT-"..legacy.." "..efforts[level] end
        if s=="5" or s=="5.6" then return "GPT-"..s end
    end
    return nil
end
local function replaceLiteral(text,old,new)
    return (text:gsub(old:gsub("([^%w])","%%%1"),function()return new end))
end
function P.instructions(provider,text)
    assert(P.id(provider),"Unknown instruction provider")
    assert(type(text)=="string","Translation instructions must be text")
    if P.id(provider)=="gemini" then return text end
    local result=replaceLiteral(text," This skill is named ln.","")
    result=replaceLiteral(result,"This skill is named ln.","")
    result=replaceLiteral(result,"shared BOOKWALKER tab","current browser tab")
    result=replaceLiteral(result,"BOOKWALKER's controls","the book reader's controls")
    result=replaceLiteral(result,"the Gemini conversation","the chat conversation")
    result=replaceLiteral(result,"If I invoke the skill without a Request ID, use MANUAL as the ID. ","")
    return result
end
return P
