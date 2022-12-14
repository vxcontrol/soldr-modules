require("engine")
local ffi     = require("ffi")
local glue    = require("glue")
local cjson   = require("cjson.safe")
local luapath = require("path")
local process_api = require("process_api")
local lk32
local win_const = {}
if ffi.os == "Windows" then
    lk32 = require("waffi.windows.kernel32")
    win_const.STILL_ALIVE = 259
else
    ffi.cdef[[
        typedef uint32_t pid_t;

        int kill( pid_t proc_id, int sig );

        pid_t getpid();
    ]]
end

-- module config logic variables
local wait_kill_timeout = 2000

local process_excludes = {}
local agent_path = ""
local agent_id = nil
-- table to contain kill handlers that uses to run module business logic
local handlers = {windows = {}, linux = {}, osx = {}}
-- table holding handlers for current os
local dyn_handlers = {}

-- some system processes have no image path, thus we can only identify them by empty path & name
local system_process_excludes_windows = {"system", "registry", "memory compression"}

-- correlator config
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_config = __config.get_current_config()
local module_info = __config.get_module_info()
local action_engine = CActionEngine(
    {},
    __args["debug_correlator"][1] == "true"
)
local event_engine = CEventEngine(
    fields_schema,
    current_event_config,
    module_info,
    prefix_db,
    __args["debug_correlator"][1] == "true"
)

local function update_process_excludes()
    local excl
    local config = cjson.decode(module_config) or {}
    if ffi.os == "Windows" then
        excl = config.process_image_excludes_windows or {}
    elseif ffi.os == "Linux" then
        excl = config.process_image_excludes_linux or {}
    elseif ffi.os == "OSX" then
        excl = config.process_image_excludes_osx or {}
    end

    process_excludes = glue.map(excl, function(tk, image)
        image = image or tk
        return type(image) == "string" and image:lower() or ""
    end)
end

local function push_event(event_name, action_name, action_data)
    local actions = action_data.actions or {}
    if action_name ~= "" then
        local action_full_name = __config.ctx.name .. "." .. action_name
        if not glue.indexof(action_full_name, actions) then
            table.insert(actions, action_full_name)
        end
    end

    -- push some event to the engine
    local info = {
        ["name"] = event_name,
        ["data"] = action_data.data,
        ["actions"] = actions,
    }
    local result, list = event_engine:push_event(info)

    -- check result return variable as marker is there need to execute actions
    if result then
        for action_id, action_result in ipairs(action_engine:exec(__aid, list)) do
            __log.infof("action '%s' was requested with result: %s", action_id, action_result)
        end
    end
end

local function update_agent_info()
    agent_id, agent_path = process_api.update_agent_info()
end

local function collect_process_info(object_type)
    local process_list = {}
    process_api.for_each_process(function(proc_info)
        table.insert(process_list, {
            [object_type .. ".process.id"] = proc_info.pid,
            [object_type .. ".process.name"] = proc_info.name,
            [object_type .. ".process.fullpath"] = proc_info.path,
            [object_type .. ".process.parent.id"] = proc_info.parent_pid,
        })
    end)
    return process_list
end

local function get_process_tree(check_ppid, object_type, full_process_info, depth)
    assert(type(check_ppid) == "number", "check_proc proc_id has invalid type")
    local child_list = {}
    local depth_limit = 50
    if depth > depth_limit then
        return child_list
    end
    if full_process_info == nil then
        full_process_info = collect_process_info(object_type)
    end

    for _, proc_info in ipairs(full_process_info) do
        -- no need to check same proc_id for parents
        if proc_info[object_type .. ".process.id"] ~= check_ppid then
            if (proc_info[object_type .. ".process.parent.id"] == check_ppid) then
                local info = {
                    [object_type .. ".process.name"] = proc_info[object_type .. ".process.name"],
                    [object_type .. ".process.id"] = proc_info[object_type .. ".process.id"]
                }
                -- add current item
                table.insert(child_list, info)
                __log.debugf("for proc_id '%d' found child: '%s' '%d'", check_ppid, info[object_type .. ".process.name"],
                    info[object_type .. ".process.id"])
                -- try to find it's child processes
                glue.extend(child_list, get_process_tree(info[object_type .. ".process.id"], object_type, full_process_info, depth + 1))
            end
        end
    end

    return child_list
end

local function clear_proc_data(action_data, object_type)
    action_data.filename = nil
    for key in pairs(action_data) do
        if type(key) == "string" and key:find("^" .. object_type .. ".process.") then
            action_data[key] = nil
        end
    end
end

local function update_action_data(action_data, object_type, proc_id, proc_path)
    action_data.data.result = nil
    clear_proc_data(action_data.data, object_type)
    action_data.data[object_type .. ".process.fullpath"] = proc_path
    action_data.data[object_type .. ".process.name"] = luapath.file(proc_path or "")
    action_data.data[object_type .. ".process.path"] = luapath.dir(proc_path or "")
    action_data.data[object_type .. ".process.ext"] = luapath.ext(proc_path or "")
    action_data.data[object_type .. ".process.id"] = proc_id
    action_data.data[object_type .. ".fullpath"] = proc_path
    action_data.data[object_type .. ".name"] = luapath.file(proc_path or "")
    action_data.data[object_type .. ".path"] = luapath.dir(proc_path or "")
    action_data.data[object_type .. ".ext"] = luapath.ext(proc_path or "")
    action_data.data[object_type] = "process"
    return action_data.data
end

-- fill data with blank values if they were not passed
local function set_action_data_fields(action_data, object_type)
    action_data.data[object_type] = "process"
    local proc_fullpath = action_data.data[object_type .. ".process.fullpath"]
    action_data.data[object_type .. ".process.fullpath"] = proc_fullpath or ""
    local proc_name = action_data.data[object_type .. ".process.name"]
    action_data.data[object_type .. ".process.name"] = proc_name or luapath.file(proc_fullpath or "") or ""
    local proc_path = action_data.data[object_type .. ".process.path"]
    action_data.data[object_type .. ".process.path"] = proc_path or luapath.dir(proc_fullpath or "") or ""
    local proc_ext = action_data.data[object_type .. ".process.ext"]
    action_data.data[object_type .. ".process.ext"] = proc_ext or luapath.ext(proc_name or "") or ""
    local proc_id = action_data.data[object_type .. ".process.id"]
    action_data.data[object_type .. ".process.id"] = proc_id or 0
    return action_data
end

local function kill_proc_children(action_name, object_type, proc_id)
    local child_process_tree = get_process_tree(proc_id, object_type, nil, 0)
    if #child_process_tree > 0 then
        local child_action_data = {
            data = {},
        }
        for i=1,#child_process_tree do
            local ch_proc_id = child_process_tree[#child_process_tree + 1 - i][object_type .. ".process.id"]
            local ch_proc_name = child_process_tree[#child_process_tree + 1 - i][object_type .. ".process.name"]
            __log.debugf("try to kill proc '%s'", ch_proc_name)
            child_action_data.data = {
                [object_type .. ".process.name"] = ch_proc_name,
                [object_type .. ".process.id"] = ch_proc_id,
                [object_type .. ".process.fullpath"] = process_api.get_process_path(ch_proc_id)
            }
            __log.info("Killing -> " .. ch_proc_id)
            dyn_handlers.kill_process_by_name_and_id(action_name, child_action_data, object_type, false, true)
            clear_proc_data(child_action_data.data, object_type)
        end
        __log.debug("done killing chidren")
    else
        __log.debugf("no children found for proc_id: %d", proc_id)
    end
end

local function is_whitelisted(proc_path, proc_id, ignore_whitelist)
    if proc_id == agent_id and proc_path == agent_path then
        __log.info("is whitelisted (this process) " .. proc_path .. " -> " .. proc_id)
        return true
    elseif glue.indexof(proc_path, process_excludes) and not ignore_whitelist then
        __log.info("is whitelisted -> " .. proc_path)
        return true
    end
    return false
end

local function check_action_structure(action_name, action_data)
    if type(action_data) ~= "table" or type(action_data.data) ~= "table" then
        return false
    end
    -- TODO: fix *.process.id for using this actions in correlator events
    action_data.data["object.process.id"] = tonumber(action_data.data["object.process.id"])
    action_data.data["subject.process.id"] = tonumber(action_data.data["subject.process.id"])

    local actions = {
        pt_kill_object_process_by_file_path = {{"object.fullpath", "string"}},
        pt_kill_object_process_by_image = {{"object.process.fullpath", "string"}},
        pt_kill_object_process_by_name = {{"object.process.name", "string"}},
        pt_kill_object_process_by_name_and_id = {{"object.process.name", "string"}, {"object.process.id", "number"}},
        pt_kill_object_process_by_image_and_id = {{"object.process.fullpath", "string"}, {"object.process.id", "number"}},
        pt_kill_object_process_tree_by_file_path = {{"object.fullpath", "string"}},
        pt_kill_object_process_tree_by_image = {{"object.process.fullpath", "string"}},
        pt_kill_object_process_tree_by_name = {{"object.process.name", "string"}},
        pt_kill_object_process_tree_by_name_and_id = {{"object.process.name", "string"}, {"object.process.id", "number"}},
        pt_kill_object_process_tree_by_image_and_id = {{"object.process.fullpath", "string"}, {"object.process.id", "number"}},
        pt_kill_subject_process_by_image = {{"subject.process.fullpath", "string"}},
        pt_kill_subject_process_by_name = {{"subject.process.name", "string"}},
        pt_kill_subject_process_by_name_and_id = {{"subject.process.name", "string"}, {"subject.process.id", "number"}},
        pt_kill_subject_process_by_image_and_id = {{"subject.process.fullpath", "string"}, {"subject.process.id", "number"}},
        pt_kill_subject_process_tree_by_image = {{"subject.process.fullpath", "string"}},
        pt_kill_subject_process_tree_by_name = {{"subject.process.name", "string"}},
        pt_kill_subject_process_tree_by_name_and_id = {{"subject.process.name", "string"}, {"subject.process.id", "number"}},
        pt_kill_subject_process_tree_by_image_and_id = {{"subject.process.fullpath", "string"}, {"subject.process.id", "number"}}
    }

    -- check action data structure
    for _, value in ipairs(actions[action_name]) do
        local data_name, data_type = unpack(value)
        if type(action_data.data[data_name]) ~= data_type then
            return false
        end
    end
    return true
end

local function exec_action(action_name, action_data)
    local set_failure = function(reason)
        action_data.data.result = false
        action_data.data.reason = reason
        return false
    end

    local set_osx_unsupported = function()
        action_data.data.result = false
        action_data.data.reason = "Current OSX module logic implementation does not support this action"
        return false
    end

    -- set missing fields
    local object_type, object_value
    if string.find(action_name, "_object_") then
        object_type = "object"
    else
        object_type = "subject"
    end

    if not check_action_structure(action_name, action_data) then
        __log.errorf("requested action '%s' cannot matched to the action schema", action_name)
        return set_failure("action_malformed")
    end

    action_data = set_action_data_fields(action_data, object_type)

    if action_name == "pt_kill_object_process_by_file_path" then
        object_value = action_data.data[object_type .. ".fullpath"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, false)
    elseif action_name == "pt_kill_object_process_by_image" or action_name == "pt_kill_subject_process_by_image" then
        object_value = action_data.data[object_type .. ".process.fullpath"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, false)
    elseif action_name == "pt_kill_object_process_by_name" or action_name == "pt_kill_subject_process_by_name" then
        object_value = action_data.data[object_type .. ".process.name"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, false)
    elseif action_name == "pt_kill_object_process_by_name_and_id" or action_name == "pt_kill_subject_process_by_name_and_id" then
        dyn_handlers.kill_process_by_name_and_id(action_name, action_data, object_type, false, false)
    elseif action_name == "pt_kill_object_process_by_image_and_id" or action_name == "pt_kill_subject_process_by_image_and_id" then
        dyn_handlers.kill_process_by_name_and_id(action_name, action_data, object_type, false, false)
    elseif action_name == "pt_kill_object_process_tree_by_file_path" then
        object_value = action_data.data[object_type .. ".fullpath"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, true) -- kill_children = true
    elseif action_name == "pt_kill_object_process_tree_by_image" or action_name == "pt_kill_subject_process_tree_by_image" then
        object_value = action_data.data[object_type .. ".process.fullpath"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, true) -- kill_children = true
    elseif action_name == "pt_kill_object_process_tree_by_name" or action_name == "pt_kill_subject_process_tree_by_name" then
        object_value = action_data.data[object_type .. ".process.name"]
        dyn_handlers.kill_process_by_name(action_name, action_data, object_type, object_value, true) -- kill_children = true
    elseif action_name == "pt_kill_object_process_tree_by_name_and_id" or action_name == "pt_kill_subject_process_tree_by_name_and_id" then
        dyn_handlers.kill_process_by_name_and_id(action_name, action_data, object_type, true, false) -- kill_children = true, ignore_whitelist = false
    elseif action_name == "pt_kill_object_process_tree_by_image_and_id" or action_name == "pt_kill_subject_process_tree_by_image_and_id" then
        dyn_handlers.kill_process_by_name_and_id(action_name, action_data, object_type, true, false) -- kill_children = true, ignore_whitelist = false
    else
        __log.errorf("requested action '%s' cannot applied to the module", action_name)
        return set_failure("action_unknown")
    end

    return action_data.data.result
end

if ffi.os == "Windows" then

    --[[ Windows handlers ]]

    function handlers.windows.kill_proc_common(action_name, action_data, object_type, proc_handle)
        local exitCode = ffi.new("DWORD[1]", 0)
        if lk32.TerminateProcess(proc_handle, 0) ~= 0 then
            lk32.WaitForSingleObject(proc_handle, wait_kill_timeout)
            action_data.data.result = true
            push_event("pt_" .. object_type .. "_process_killed_successful", action_name, action_data)
            return action_data.data
            -- we can fail if the process is already terminating, so check for it
        elseif lk32.GetExitCodeProcess(proc_handle, exitCode) ~= 0 then
            __log.debugf("exit code from requested kill process: %d", tonumber(exitCode[0]))

            if tonumber(exitCode[0]) ~= win_const.STILL_ALIVE then
                action_data.data.result = true
                action_data.data.reason = "already terminating"
                push_event("pt_" .. object_type .. "_process_killed_successful", action_name, action_data)
                return action_data.data
            end
        end

        action_data.data.result = false
        action_data.data.reason = "failed_to_exec_terminate_process"
        push_event("pt_" .. object_type .. "_process_killed_failed", action_name, action_data)
        return action_data.data
    end

    function handlers.windows.kill_process_by_name(action_name, action_data, object_type, name, kill_children)
        assert(type(name) == "string", "input process name or path has invalid type")
        assert(type(kill_children) == "boolean", "kill_children flag has invalid type")
        name = name:lower()
        __log.debug("kill_process_by_name", name, kill_children)

        -- check proc name to ensure we really need to open process
        local s_proc_name = luapath.file(name)
        s_proc_name = s_proc_name:lower()

        local proc_found = false
        local action_data_bak = glue.update({}, action_data.data)
        action_data_bak.result = true
        process_api.for_each_process(function(proc_info)
            if (proc_info.name ~= s_proc_name) then
                return false
            end

            local proc_path, err = process_api.get_process_path(proc_info.pid)
            local proc_path_lower = proc_path:lower()
            if err == nil then
                if proc_path == "" and glue.indexof(proc_info.name, system_process_excludes_windows) then
                    proc_found = true
                    action_data.data = update_action_data(action_data, object_type, proc_info.pid, proc_path)
                    push_event("pt_" .. object_type .. "_process_skipped", action_name, action_data)
                    return false
                elseif proc_path == "" or (proc_path_lower ~= name and luapath.file(proc_path_lower) ~= name) then
                    return false
                end
            else
                return false
            end

            proc_found = true
            action_data.data = update_action_data(action_data, object_type, proc_info.pid, proc_path)

            if is_whitelisted(proc_path_lower, proc_info.pid, false) then
                push_event("pt_" .. object_type .. "_process_skipped", action_name, action_data)
                return false
            end

            if kill_children then
                kill_proc_children(action_name, object_type, proc_info.pid)
            end
            local proc_handle
            proc_handle, action_data.data = handlers.windows.get_termination_handle(
                action_name, action_data, object_type, proc_info.pid)
            if proc_handle == nil then
                action_data_bak.result = false
                return false
            end

            action_data.data = handlers.windows.kill_proc_common(action_name, action_data, object_type, proc_handle)
            action_data_bak.result = action_data.data.result

            lk32.CloseHandle(proc_handle)
        end)

        action_data.data = action_data_bak
        action_data.data.reason = not action_data.data.result and "failed_to_kill_a_part_of_processes" or nil
        if not proc_found then
            action_data.data.result = false
            action_data.data.reason = "Process not found"
            push_event("pt_process_not_found", action_name, action_data)
        end
        return action_data.data.result
    end

    function handlers.windows.kill_process_by_name_and_id(action_name, action_data, object_type, kill_children, ignore_whitelist)
        assert(type(kill_children) == "boolean", "kill_children flag has invalid type")
        assert(type(ignore_whitelist) == "boolean", "ignore_whitelist flag has invalid type")

        local dproc_id = action_data.data[object_type .. ".process.id"]
        assert(type(dproc_id) == "number", "input process id has invalid type")

        local dproc_name, dproc_path
        if string.find(action_name, "_image_") then
            dproc_path = action_data.data[object_type .. ".process.fullpath"]
            assert(type(dproc_path) == "string", "input process path has invalid type")
            dproc_path = dproc_path:lower()
            dproc_name = luapath.file(dproc_path)
        else
            dproc_name = action_data.data[object_type .. ".process.name"]
            assert(type(dproc_name) == "string", "input process name has invalid type")
            dproc_name = dproc_name:lower()
        end
        __log.debug("kill_process_by_name_and_id", dproc_name, dproc_id, kill_children, ignore_whitelist)

        local proc_handle
        local proc_path, err = process_api.get_process_path(dproc_id)
        proc_path = proc_path or ""
        local proc_path_l = proc_path:lower()
        local proc_name_l = luapath.file(proc_path_l)
        if err then
            action_data.data.result = false
            action_data.data.reason = err == 87 and "Process not found" or "Failed to get process path"
            push_event("pt_process_not_found", action_name, action_data)
            return action_data.data.result
        elseif is_whitelisted(proc_path_l, dproc_id, ignore_whitelist) or
            (proc_path_l == "" and glue.indexof(dproc_name, system_process_excludes_windows)) then
            push_event("pt_" .. object_type .. "_process_skipped", action_name, action_data)
            action_data.data.result = true
            return action_data.data.result
        end

        if dproc_name ~= proc_name_l or (dproc_path and dproc_path ~= proc_path_l) then
            action_data.data.result = false
            action_data.data.reason = "Process not found"
            push_event("pt_process_not_found", action_name, action_data)
            return action_data.data.result
        end

        if kill_children then
            kill_proc_children(action_name, object_type, dproc_id)
        end

        proc_handle, action_data.data = handlers.windows.get_termination_handle(
            action_name, action_data, object_type, dproc_id)
        if proc_handle == nil then
            return action_data.data.result
        end

        action_data.data = update_action_data(action_data, object_type, dproc_id, proc_path)
        action_data.data = handlers.windows.kill_proc_common(action_name, action_data, object_type, proc_handle)

        lk32.CloseHandle(proc_handle)
        return action_data.data.result
    end

    function handlers.windows.get_termination_handle(action_name, action_data, object_type, proc_id)
        local proc_handle, err = process_api.get_process_handle(proc_id)
        if proc_handle == nil then
            -- access denied
            if err == 5 then
                action_data.data.result = false
                action_data.data.reason = "failed_to_open_process"
                push_event("pt_" .. object_type .. "_process_killed_failed", action_name, action_data)
            else
                -- 87 for invalid proc_id
                action_data.data.result = false
                action_data.data.reason = "Process not found"
                push_event("pt_process_not_found", action_name, action_data)
            end
            return nil, action_data.data
        end
        return proc_handle, action_data.data
    end

else

    --[[ Linux handlers ]]

    function handlers.linux.kill_proc_common(action_name, action_data, object_type, proc_id)
        assert(type(proc_id) == "number", "input process id has invalid type")
        --       If proc_id is positive, then signal sig is sent to the process with
        -- the ID specified by proc_id.
        --     If proc_id equals 0, then sig is sent to every process in the process
        --    group of the calling process.

        --    If proc_id equals -1, then sig is sent to every process for which the
        --    calling process has permission to send signals, except for
        --    process 1 (init), but see below.

        if proc_id <= 0 then
            action_data.data.result = false
            action_data.data.reason = "Invalid PID specified"
            push_event("pt_" .. object_type .. "process_not_found", action_name, action_data)
            return action_data
        end
        __log.info("call linux.kill_proc_common", action_name, proc_id)
        if ffi.C.kill(proc_id, 9) == 0 then
            action_data.data.result = true
            push_event("pt_" .. object_type .. "_process_killed_successful", action_name, action_data)
            return action_data.data
        end

        local EPERM = 1 -- Operation not permitted
        local ESRCH = 3 -- No such process
        action_data.data.result = false

        local err = ffi.errno()
        if err == ESRCH then
            action_data.data.reason = "Process not found"
            push_event("pt_process_not_found", action_name, action_data)
            return action_data.data
        end

        action_data.data.reason = err == EPERM and "Access denied" or ("errno: %d"):format(err)
        push_event("pt_" .. object_type .. "_process_killed_failed", action_name, action_data)
        return action_data.data, err
    end

    function handlers.linux.kill_process_by_name(action_name, action_data, object_type, name, kill_children, ignore_whitelist)
        assert(type(name) == "string", "input process name or path has invalid type")
        assert(type(kill_children) == "boolean", "kill_children flag has invalid type")
        __log.debug("kill_process_by_name", name, kill_children)

        local proc_found = false
        local action_data_bak = glue.update({}, action_data.data)
        action_data_bak.result = true

        process_api.for_each_process(function(proc_info)
            clear_proc_data(action_data, object_type)

            -- some processes on osx might start with dash
            -- current way of getting process info does not guarantee getting full process name
            -- instead it gets argv[0] of running process
            if ffi.os == "OSX" then
                if proc_info.path == "" or ( not glue.ends(proc_info.name, name) and not glue.ends(proc_info.path, name)) then
                    return false
                end
            else
                if proc_info.path == "" or (proc_info.path ~= name and proc_info.name ~= name) then
                    return false
                end
            end
            proc_found = true
            action_data.data = update_action_data(action_data, object_type, proc_info.pid, proc_info.path)

            if is_whitelisted(proc_info.path, proc_info.pid, ignore_whitelist) then
                action_data.data.result = true
                push_event("pt_" .. object_type .. "_process_skipped", action_name, action_data)
                return false
            end

            if kill_children then
                kill_proc_children(action_name, object_type, proc_info.pid)
            end

            local err
            action_data.data, err = dyn_handlers.kill_proc_common(action_name, action_data, object_type, proc_info.pid)
            if err then
                __log.debugf("process killed -> '%d' with error -> '%s'", proc_info.pid, err)
            else
                __log.debugf("process killed -> '%d'", proc_info.pid)
            end
        end)

        if not proc_found then
            action_data.data.result = false
            action_data.data.reason = "Process not found"
            push_event("pt_process_not_found", action_name, action_data)
        end
        return action_data.data.result
    end

    function handlers.linux.kill_process_by_name_and_id(action_name, action_data, object_type, kill_children, ignore_whitelist)
        assert(type(kill_children) == "boolean", "kill_children flag has invalid type")
        assert(type(ignore_whitelist) == "boolean", "ignore_whitelist flag has invalid type")

        local dproc_id = action_data.data[object_type .. ".process.id"]
        assert(type(dproc_id) == "number", "input process id has invalid type")

        local dproc_name, dproc_path
        if string.find(action_name, "_image_") then
            dproc_path = action_data.data[object_type .. ".process.fullpath"]
            assert(type(dproc_path) == "string", "input process path has invalid type")
            dproc_name = luapath.file(dproc_path)
        else
            dproc_name = action_data.data[object_type .. ".process.name"]
            assert(type(dproc_name) == "string", "input process name has invalid type")
        end
        __log.debug("linux.kill_process_by_name_and_id", dproc_name, dproc_id, kill_children, ignore_whitelist)

        local proc_path, err = process_api.get_process_path(dproc_id)
        __log.debugf("proc info -> '%s' error -> '%s'", proc_path, err)
        if not err and proc_path ~= "" and proc_path ~= nil and (not dproc_path or dproc_path == proc_path) then
            action_data.data = update_action_data(action_data, object_type, dproc_id, proc_path)
            if is_whitelisted(proc_path, dproc_id, ignore_whitelist) then
                action_data.data.result = true
                push_event("pt_" .. object_type .. "_process_skipped", action_name, action_data)
            else
                local name = luapath.file(proc_path) or ""
                local is_requested_process =
                    (ffi.os ~= "OSX" and dproc_name == name) or
                    (ffi.os == "OSX" and glue.ends(dproc_name, name))

                if is_requested_process then
                    if kill_children then
                        kill_proc_children(action_name, object_type, dproc_id)
                    end
                    action_data.data, err = dyn_handlers.kill_proc_common(action_name, action_data, object_type, dproc_id)
                    __log.debugf("proc killed -> '%d' error -> '%s'", dproc_id, err)
                else
                    action_data.data.result = false
                    action_data.data.reason = "Process not found"
                    push_event("pt_process_not_found", action_name, action_data)
                end
            end
        else
            __log.infof("error getting image path for '%s' -> ", err)
            action_data.data.result = false
            action_data.data.reason = err
            push_event("pt_process_not_found", action_name, action_data)
        end

        return action_data.data.result
    end

    --[[ OSX handlers ]]

    function handlers.osx.kill_proc_common(action_name, action_data, object_type, proc_id)
        return handlers.linux.kill_proc_common(action_name, action_data, object_type, proc_id)
    end

    function handlers.osx.kill_process_by_name(action_name, action_data, object_type, name, kill_children, ignore_whitelist)
        return handlers.linux.kill_process_by_name(action_name, action_data, object_type, name, kill_children, ignore_whitelist)
    end

    function handlers.osx.kill_process_by_name_and_id(action_name, action_data, object_type, kill_children, ignore_whitelist)
        return handlers.linux.kill_process_by_name_and_id(action_name, action_data, object_type, kill_children, ignore_whitelist)
    end

end

if ffi.os == "Windows" then
    dyn_handlers = handlers.windows
elseif ffi.os == "Linux" then
    dyn_handlers = handlers.linux
elseif ffi.os == "OSX" then
    dyn_handlers = handlers.osx
end

-- parse process excludes from module config
update_process_excludes()
-- set agent path and info to not let it accidentally kill itself
update_agent_info()

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)

        -- execute received action
        local action_data = cjson.decode(data) or {}
        local action_result = exec_action(name, action_data)

        -- is internal communication from collector module
        if __imc.is_exist(src) then
            local mod_name, group_id = __imc.get_info(src)
            __log.debugf("internal message received from module '%s' group %s", mod_name, group_id)
        else
            __log.debug("message received from the server")
            __api.send_data_to(src, cjson.encode({
                ["retaddr"] = action_data.retaddr,
                ["status"] = tostring(action_result),
                ["agent_id"] = __aid,
                ["name"] = name,
            }))
        end

        __log.infof("requested action '%s' was executed with result: %s", name, action_result)
        return true
    end,

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            -- update process excludes by current module configuration
            module_config = __config.get_current_config()
            update_process_excludes()

            -- update current action and event list from new config
            current_event_config = __config.get_current_event_config()
            module_info = __config.get_module_info()

            -- renew current event engine instance
            if event_engine then
                event_engine:free()
                event_engine = nil
                collectgarbage("collect")
                event_engine = CEventEngine(
                    fields_schema,
                    current_event_config,
                    module_info,
                    prefix_db,
                    __args["debug_correlator"][1] == "true"
                )
            end
        end
        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

push_event("pt_module_started", "", {["data"] = {}})
__api.await(-1)
push_event("pt_module_stopped", "", {["data"] = {}})

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
