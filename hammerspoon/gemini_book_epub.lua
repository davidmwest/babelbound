-- Asynchronous file-only EPUB export queue. No reader/model/UI operations.
-- A caller owns the illustration barrier and explicitly flushes safe folders.
local E={}
local function copy(v)
    if type(v)~='table' then return v end
    local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
local function count(v)return type(v)=='number' and v>=0 and v<math.huge and v==math.floor(v)end
function E.new(hooks)
    assert(type(hooks)=='table','EPUB hooks are required')
    for _,name in ipairs({'exists','taskNew','decode','now'})do
        assert(type(hooks[name])=='function','Missing EPUB hook: '..name)
    end
    local pending,active,states={},{},{}
    local manager={}
    local function log(message)if hooks.log then pcall(hooks.log,message)end end
    local function notify(name,folder)
        if hooks[name] then
            local ok,err=pcall(hooks[name],folder,copy(states[folder]))
            if not ok then log('EPUB '..name..' callback failed: '..tostring(err))end
        end
    end
    local function change(folder,state)
        states[folder]=state;notify('onChange',folder)
    end
    local function failed(folder,reason)
        return {status='failed',folder=folder,error=tostring(reason),completedAt=hooks.now()}
    end
    local function present(folder,result)
        if pending[folder] then
            local next=pending[folder]
            local state={status='queued',folder=folder,savedCount=next.count,queuedAt=next.queuedAt,
                lastResult=copy(result)}
            -- Preserve errors visibly while a newer request waits for its barrier.
            if result.status=='failed' then state.status='failed';state.error=result.error;state.queued=true end
            change(folder,state)
        else change(folder,result)end
    end
    function manager:state(folder)
        return copy(states[folder] or {status='idle',folder=folder})
    end
    function manager:busy(folder)return active[folder]~=nil or pending[folder]~=nil end
    function manager:pendingFolders()
        local folders={};for folder in pairs(pending)do folders[#folders+1]=folder end
        table.sort(folders);return folders
    end
    function manager:request(folder,title,expected)
        assert(type(folder)=='string' and folder~='' and not folder:find('\0',1,true),'Invalid EPUB folder')
        assert(type(title)=='string' and title~='','Invalid EPUB title')
        assert(count(expected),'Invalid EPUB saved-screen count')
        pending[folder]={folder=folder,title=title,count=expected,queuedAt=hooks.now()}
        change(folder,{status='queued',folder=folder,savedCount=expected,queuedAt=pending[folder].queuedAt,
            active=active[folder]~=nil})
        return manager:state(folder)
    end
    function manager:fail(folder,reason)
        pending[folder]=nil
        if active[folder] then active[folder].blockedReason=tostring(reason)end
        change(folder,failed(folder,reason))
        return manager:state(folder)
    end
    function manager:flush(folder)
        if active[folder] or not pending[folder] then return false end
        local request=pending[folder];pending[folder]=nil
        local token={request=request};active[folder]=token
        local output=folder..'/translation.epub'
        change(folder,{status='running',folder=folder,savedCount=request.count,startedAt=hooks.now()})
        local function finish(code,stdout,stderr,forcedError)
            if active[folder]~=token then return end -- Ignore duplicate/stale task callbacks.
            active[folder]=nil
            local result,errorReason
            if token.blockedReason then errorReason=token.blockedReason
            elseif forcedError then errorReason=forcedError
            elseif code~=0 then
                errorReason='EPUB helper exited with code '..tostring(code)..': '..tostring(stderr or ''):sub(1,1600)
            else
                local ok,value=pcall(hooks.decode,stdout or '')
                if not ok or type(value)~='table' then errorReason='EPUB helper returned invalid JSON.'
                elseif value.ok~=true then errorReason='EPUB helper did not report success: '..tostring(value.error or '')
                elseif value.output~=output then errorReason='EPUB helper reported an unexpected output path.'
                elseif not count(value.screens) or value.screens<request.count then
                    errorReason='EPUB helper returned fewer saved screens than requested.'
                else
                    local existsOK,exists=pcall(hooks.exists,output)
                    if not existsOK or not exists then errorReason='EPUB helper reported success but its output file is missing.'
                    else result={status='complete',folder=folder,epub=output,savedCount=value.screens,completedAt=hooks.now()}end
                end
            end
            if errorReason then result=failed(folder,errorReason);log('EPUB export failed: '..result.error)
            else log('EPUB reading copy updated: '..output..' ('..result.savedCount..' screens).')end
            present(folder,result)
            -- Do not start queued work here: the caller must recheck its barrier.
            notify('onReady',folder)
        end
        local ok,exists=pcall(function()
            return type(hooks.python)=='string' and type(hooks.script)=='string'
                and hooks.exists(hooks.python) and hooks.exists(hooks.script)
        end)
        if not ok or not exists then
            finish(nil,nil,nil,'EPUB helper or Python runtime is missing.');return false
        end
        local created,task=pcall(hooks.taskNew,hooks.python,finish,
            {hooks.script,'--html',folder..'/translation.html','--output',output,'--title',request.title})
        if not created or not task then
            finish(nil,nil,nil,'Cannot create EPUB export task: '..tostring(created and 'no task returned' or task));return false
        end
        token.task=task
        if active[folder]~=token then return false end
        local started,value=pcall(function()return task:start()end)
        if not started or not value then
            finish(nil,nil,nil,'Cannot start EPUB export task: '..tostring(started and 'start returned false' or value));return false
        end
        return true
    end
    return manager
end
return E
