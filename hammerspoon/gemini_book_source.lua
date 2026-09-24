-- Reviewed navigation-reference policy. Pure Lua: no screenshots, UI or writes.
local S={}
local function nonempty(v) return type(v)=="string" and v:match("%S")~=nil end
function S.problem(job)
    if type(job)~="table" or type(job.records)~="table" or #job.records==0 then
        return "Load a job with a saved screen first."
    end
    if job.pending then return "A pending screen exists; use pending-screen recovery." end
    if job.turnUncertain then return "The last page turn is uncertain; verify its position before source review." end
    if job.needAdvance~=true then return "This job is not waiting on its last saved screen." end
    local last=job.records[#job.records]
    if type(last)~="table" or last.index~=#job.records or not nonempty(last.id)
        or not nonempty(last.sourceHash) or not nonempty(job.lastSourceHash) then
        return "The saved source reference is incomplete."
    end
    return nil
end
function S.snapshot(job)
    local last=job.records[#job.records] or {}
    local fields={job.folder,#job.records,job.remaining,job.lastSourceHash,last.id,last.sourceHash,
        tostring(job.needAdvance),tostring(job.turnUncertain),tostring(job.pending~=nil)}
    local out={}
    for i=1,9 do local s=tostring(fields[i]);out[i]=#s..":"..s end
    return table.concat(out)
end
function S.approvalProblem(review,job,evidence)
    local problem=S.problem(job);if problem then return problem end
    if type(review)~="table" or review.status~="ready" then return "Prepare a fresh source review first." end
    if review.snapshot~=S.snapshot(job) then return "The job changed after the source review was prepared." end
    if type(evidence)~="table" then return "Explicit reviewed-source evidence is required." end
    for _,key in ipairs({"savedCount","recordID","oldHash","candidateHash"}) do
        if evidence[key]~=review[key] then return "Reviewed evidence does not match "..key.."." end
    end
    if not nonempty(evidence.reviewedBy) or not nonempty(evidence.notes) then
        return "Record who reviewed the source and which page content they verified."
    end
    return nil
end
function S.apply(review,job,evidence,stableHash,at)
    local problem=S.approvalProblem(review,job,evidence)
    if problem then return nil,problem end
    if stableHash~=review.candidateHash then return nil,"The source changed after review; no reference was replaced." end
    -- Original sources/*.png and records[*].sourceHash remain immutable.
    job.lastSourceHash=stableHash
    job.navigationReference={sourceHash=stableHash,recordID=review.recordID,
        savedCount=review.savedCount,originalSourceHash=review.originalSourceHash,
        previousSourceHash=review.oldHash,reviewFolder=review.folder,
        reviewedBy=evidence.reviewedBy,notes=evidence.notes,reviewedAt=at}
    return true
end
return S
