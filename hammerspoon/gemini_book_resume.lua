-- Pure reset-time and resume-policy helpers. No UI, timers, files or requests.
local L=require('gemini_book_limits')
local R={}
local months={jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
local function validTime(h,m,ap)
    h,m=tonumber(h),tonumber(m)
    if not h or not m or m<0 or m>59 then return end
    if ap then
        if h<1 or h>12 then return end
        h=h%12+(ap=='pm' and 12 or 0)
    elseif h<0 or h>23 then return end
    return h,m
end
local function dateEpoch(y,mo,d,h,m)
    local t={year=y,month=mo,day=d,hour=h,min=m,sec=0,isdst=nil}
    local requested={year=y,month=mo,day=d,hour=h,min=m}
    local e=os.time(t)
    if not e then return end
    local check=os.date('*t',e)
    for _,k in ipairs({'year','month','day','hour','min'})do
        if check[k]~=requested[k]then return end
    end
    return e
end
-- Supported: observed English "resets on Sep 22 at 1:46 AM", optional year,
-- today/tomorrow, "resets at 1:46 AM", or user-entered YYYY-MM-DD HH:MM.
-- Parsing itself does not authorize a timer or prove quota availability. Keep
-- the future-only scheduling contract in parseReset below. All times use the
-- Mac timezone; only an unambiguous December -> January boundary rolls a year.
local function parseResetTimestamp(text,nowEpoch)
    if type(text)~='string' or #text>6000 then return nil,'No usable reset text.' end
    local s=L.normalize(text)
    nowEpoch=math.floor(nowEpoch)
    local today=os.date('*t',nowEpoch)
    local y,mo,d,h,m=s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d?):(%d%d)$')
    local e,kind
    if y then
        h,m=validTime(h,m)
        if h then e=dateEpoch(tonumber(y),tonumber(mo),tonumber(d),h,m);kind='explicit-local-date' end
    else
        -- Restrict parsing to the reset suffix, not unrelated dates in a message.
        local tail=s:match('resets%s+on%s+(.+)') or s:match('resets%s+at%s+(.+)')
            or s:match('resets%s+(.+)') or s:match('reset%s+at%s+(.+)')
            or s:match('until%s+(.+)')
        if not tail then return nil,'No supported reset timestamp in the notice.' end
        local month,day,year,clock,ampm=tail:match('^(%a+)%s+(%d%d?),?%s+(%d%d%d%d)%s+at%s+(%d%d?:%d%d)%s*([ap]m)')
        if not month then
            month,day,clock,ampm=tail:match('^(%a+)%s+(%d%d?)%s+at%s+(%d%d?:%d%d)%s*([ap]m)')
        end
        if not month then
            month,day,clock,ampm=tail:match('^(%a+)%s+(%d%d?),%s+(%d%d?:%d%d)%s*([ap]m)')
        end
        if month then
            mo=months[month:sub(1,3)];d=tonumber(day);y=tonumber(year) or today.year
            if mo and not year and today.month==12 and mo==1 then y=y+1 end
            if clock then h,m=clock:match('^(%d%d?):(%d%d)$');h,m=validTime(h,m,ampm) end
            if mo and h then e=dateEpoch(y,mo,d,h,m);kind='notice-local-date' end
        else
            local dayword
            dayword,clock,ampm=tail:match('^(%a+)%s+at%s+(%d%d?:%d%d)%s*([ap]m)')
            if dayword~='today' and dayword~='tomorrow' then dayword=nil end
            if not dayword then clock,ampm=tail:match('^(%d%d?:%d%d)%s*([ap]m)') end
            if clock then
                h,m=clock:match('^(%d%d?):(%d%d)$');h,m=validTime(h,m,ampm)
                if h then
                    local dt=os.date('*t',nowEpoch)
                    if dayword=='tomorrow' then
                        dt=os.date('*t',os.time{year=dt.year,month=dt.month,day=dt.day+1,hour=12})
                    end
                    e=dateEpoch(dt.year,dt.month,dt.day,h,m)
                    if e and e<=nowEpoch and not dayword then
                        dt=os.date('*t',os.time{year=dt.year,month=dt.month,day=dt.day+1,hour=12})
                        e=dateEpoch(dt.year,dt.month,dt.day,h,m)
                    end
                    kind=dayword or 'next-local-clock-time'
                end
            end
        end
    end
    if not e then return nil,'Unsupported or invalid reset date/time; no time was guessed.' end
    return {resetAt=e,kind=kind,zone=os.date('%Z',e),label=os.date('%b %d, %Y at %I:%M %p %Z',e)}
end
function R.parseReset(text,nowEpoch)
    local parsed,why=parseResetTimestamp(text,nowEpoch)
    if not parsed then return nil,why end
    if parsed.resetAt<=nowEpoch then return nil,'The displayed reset date/time is already past. Refresh/check Gemini; no timer was armed.' end
    if parsed.resetAt-nowEpoch>8*24*3600 then return nil,'Reset time is more than eight days away; verify the date manually.' end
    return parsed
end

-- A chat can retain its old fallback card after the stated reset. Exempt only
-- that previously recorded card during an explicitly started manual session,
-- independent of the selected model. This evidence never authorizes a model
-- switch, a timer, or exemption of a new/copied service error.
function R.historicalNoticeCandidate(event,recorded,nowEpoch,opts)
    opts=opts or {}
    if opts.manualResume~=true then return nil,'not-manual-resume' end
    if type(event)~='table' or type(recorded)~='table' or recorded.active~=true then
        return nil,'no-active-recorded-notice'
    end
    if type(recorded.atEpoch)~='number' or recorded.atEpoch<=0 or recorded.atEpoch>=nowEpoch then
        return nil,'invalid-recorded-time'
    end
    local currentHit,recordedHit=L.detect(event.text),L.detect(recorded.text)
    if not currentHit or not recordedHit or currentHit.matchedPrefix~=recordedHit.matchedPrefix
        or L.normalize(event.text)~=L.normalize(recorded.text) then
        return nil,'different-notice'
    end
    local current=parseResetTimestamp(event.text,nowEpoch)
    local previous=parseResetTimestamp(recorded.text,recorded.atEpoch)
    -- Relative dates/time-only notices cannot identify an old card reliably.
    if not current or not previous or current.kind~='notice-local-date'
        or previous.kind~='notice-local-date' then return nil,'not-explicit-dated-notice' end
    if current.resetAt~=previous.resetAt then return nil,'different-reset-time' end
    if recorded.atEpoch>=previous.resetAt then return nil,'not-recorded-before-reset' end
    local buffer=math.max(60,tonumber(opts.bufferSeconds) or 60)
    if nowEpoch<current.resetAt+buffer then return nil,'reset-buffer-not-passed' end
    if nowEpoch-current.resetAt>8*24*3600 then return nil,'recorded-notice-too-old' end
    return {classification='recorded-expired',text=event.text,matchedPrefix=currentHit.matchedPrefix,
        resetAt=current.resetAt,recordedAt=recorded.atEpoch,checkedAt=nowEpoch,
        manualResume=true}
end
function R.historicalNotice(event,recorded,nowEpoch,model,opts)
    if not opts or opts.manualResume~=true then return nil,'not-manual-resume' end
    local candidate,why=R.historicalNoticeCandidate(event,recorded,nowEpoch,opts)
    if not candidate then return nil,why end
    candidate.classification='historical';candidate.model=model or 'unverified'
    return candidate
end
function R.modelLabel(s)
    s=L.normalize(s)
    -- Observed in diagnostics-20260922-024414.txt: Chrome exposes its CURRENT
    -- selected model as AXTitle/AXDescription="Open mode picker, currently Pro".
    -- This is not the bare visual caption. Unwrap only this exact, anchored
    -- accessibility-label form; never search for a model in arbitrary text.
    local selected=s:match('^open mode picker,%s*currently%s+(.+)$')
    if selected then s=selected end
    if s=='pro' or s=='gemini pro' or s:match('^gemini %d[%d%.]* pro$') or s:match('^%d[%d%.]* pro$') then return 'Pro' end
    if s=='flash-lite' or s=='flash lite' or s=='gemini flash-lite'
        or s:match('^%d[%d%.]* flash%-lite$') or s:match('^gemini %d[%d%.]* flash%-lite$') then return 'Flash-Lite' end
    if s=='flash' or s:match('^%d[%d%.]* flash$') or s:match('^gemini %d[%d%.]* flash$') then return 'flash' end
    if s=='fast' or s=='thinking' or s=='auto' then return s end
    -- Future names are useful diagnostics only when the actual live picker
    -- explicitly identifies its current selection. readModelControl separately
    -- verifies role, visibility, process, ancestry and composer position.
    if selected and #selected<=80 and not selected:find('[%c%[%]<>]') then return selected end
end
function R.snapshot(job)
    local p=job.pending or {}
    return table.concat({job.folder or '',#job.records,job.remaining or 0,p.id or '',tostring(p.sent),
        p.sourceHash or job.lastSourceHash or '',tostring(job.needAdvance),tostring(job.turnUncertain)},'|')
end
function R.canRun(plan,job,nowEpoch,sourceHash,model)
    if not plan or not plan.active then return false,'No active timer.' end
    if nowEpoch<plan.dueAt then return false,'The approved time has not arrived.' end
    if nowEpoch-plan.dueAt>(plan.maxLateSeconds or 600) then return false,'Scheduled time was missed by more than ten minutes; re-arm manually.' end
    if plan.snapshot~=R.snapshot(job) then return false,'Job/progress changed after the timer was armed.' end
    if not plan.sourceHash or sourceHash~=plan.sourceHash then return false,'The original book page or layout changed.' end
    if job.turnUncertain then return false,'The book position needs manual review.' end
    return true
end
return R
