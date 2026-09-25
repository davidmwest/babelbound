-- Read-only discovery of a previously SENT identity superseded by an unsent
-- retry. This does NOT authorize saving: the UI requires explicit confirmation,
-- matching source fingerprint, exact response markers and two identical copies.
local P={}
local function sameSlot(id,tag,index)
    if type(id)~="string" then return false end
    local stem=tag.."-"..string.format("%05d",index)
    if id==stem then return true end
    return id:sub(1,#stem)==stem and id:sub(#stem+1):match("^%-r%d+[%d%-]*$")~=nil
end
function P.find(job,log)
    if type(job)~="table" or type(job.records)~="table" or type(job.tag)~="string" then
        return nil,"No valid saved job is loaded."
    end
    local p=job.pending
    if not p or p.sent~=false or p.index~=#job.records+1 or job.needAdvance or job.turnUncertain
        or type(job.remaining)~="number" or job.remaining<1 or not sameSlot(p.id,job.tag,p.index) then
        return nil,"This requires one unsent pending retry, with no uncertain page turn."
    end
    if p.requestText~=nil or p.pasteAttemptedAt~=nil then
        return nil,"The current retry already has drafted request text. Review it before changing its identity."
    end
    local prior=job.priorSentReply
    local provider=job.provider or "gemini"
    if (p.provider or "gemini")~=provider then
        return nil,"The pending request belongs to a different provider."
    end
    if prior and (prior.provider or "gemini")~=provider then
        return nil,"The earlier reply belongs to a different provider."
    end
    if type(prior)=="table" and prior.index==p.index and prior.sourceHash==p.sourceHash
        and sameSlot(prior.id,job.tag,p.index) and prior.id~=p.id then
        return prior.id,"saved-before-retry"
    end
    -- Older versions logged sent-state at the failed AX scan but did not retain
    -- the prior identity in the checkpoint. Recognize only this exact adjacent
    -- diagnostic pair, never a generic mention of an ID in text or a prompt.
    if provider~="gemini" then
        return nil,"No earlier sent request with matching provider metadata was found."
    end
    local candidate
    for id in (log or ""):gmatch("Pending ID: ([^\r\n]+)\r?\nPending marked sent: true")do
        if sameSlot(id,job.tag,p.index) and id~=p.id then candidate=id end
    end
    if candidate then return candidate,"prior-sent-scan-diagnostic"end
    return nil,"No earlier sent request for this same screen was found in the checkpoint or scan log."
end
return P
