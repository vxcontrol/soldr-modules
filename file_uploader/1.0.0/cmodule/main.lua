require("engine")
local glue    = require("glue")
local cjson   = require("cjson.safe")
local crc32   = require("crc32")
local luapath = require("path")
local fs      = require("fs")
math.randomseed(crc32(tostring({})))

-- correlator config
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()
local module_config = cjson.decode(__config.get_current_config()) or {}
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

-- engine config
local server_token = ""
local files_queue = {}

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

local function get_server_token()
    local tablelength = function(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end

    if tablelength(__agents.get_by_dst(server_token)) == 0 then
        server_token = ""
    else
        return server_token
    end
    for client_id, client_info in pairs(__agents.dump()) do
        if tostring(client_info.Type) == "VXAgent" then
            server_token = tostring(client_id)
            return server_token
        end
    end

    return ""
end

local function make_uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function clear_file_data(action_data, pattern)
    for key in pairs(action_data) do
        if type(key) == "string" and key:find("^" .. pattern) then
            action_data[key] = nil
        end
    end
end

local function push_event(event_name, action_name, action_data)
    local actions = action_data.actions or {}
    if action_name ~= "" then
        local action_full_name = __config.ctx.name .. "." .. action_name
        if glue.indexof(action_full_name, actions) == nil then
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

local function exec_action(dst, action_name, action_data)
    local object_name, object_value, object_prefix, object_type
    local set_failure = function(reason)
        action_data.data.result = false
        action_data.data.reason = reason
        return false, "fu_upload_internal_error"
    end

    if action_name == "fu_upload_object_file" then
        object_name = "object_file"
        object_prefix, object_type = "object", "object"
        object_value = action_data.data["object.fullpath"]
    elseif action_name == "fu_upload_object_proc_image" then
        object_name = "object_proc_image"
        object_prefix, object_type = "object.process", "object"
        object_value = action_data.data["object.process.fullpath"]
    elseif action_name == "fu_upload_subject_proc_image" then
        object_name = "subject_proc_image"
        object_prefix, object_type = "subject.process", "subject"
        object_value = action_data.data["subject.process.fullpath"]
    else
        __log.errorf("unknown action '%s' was requested", action_name)
        return set_failure("action_unknown")
    end

    if object_value == nil or object_value == "" then
        __log.error("requested file path is empty")
        return set_failure("file_path_is_empty")
    end
    clear_file_data(action_data.data, object_prefix)
    action_data.data["uuid"] = action_data.data["uuid"] or make_uuid()
    action_data.data[object_type]                  = "file_object"
    action_data.data[object_prefix .. ".path"]     = luapath.dir(object_value)
    action_data.data[object_prefix .. ".name"]     = luapath.file(object_value)
    action_data.data[object_prefix .. ".ext"]      = luapath.ext(object_value)
    action_data.data[object_prefix .. ".fullpath"] = object_value
    if object_prefix == "subject.process" or object_prefix == "object.process" then
        action_data.data[object_type .. ".path"]     = action_data.data[object_prefix .. ".path"]
        action_data.data[object_type .. ".name"]     = action_data.data[object_prefix .. ".name"]
        action_data.data[object_type .. ".ext"]      = action_data.data[object_prefix .. ".ext"]
        action_data.data[object_type .. ".fullpath"] = action_data.data[object_prefix .. ".fullpath"]
    end

    local result, reason
    local filename = luapath.file(object_value)
    local filesize = fs.attr(object_value, "size")
    local file_size_limit = get_option_config("file_size_limit") * 1024 * 1024
    if filesize == nil then
        reason = "file_not_found"
        result = false
        __log.errorf("can't get file '%s' size", object_value)
    elseif filesize > file_size_limit then
        reason = "file_size_exceeded"
        result = false
        __log.errorf("exceeded file size (%d > %d) for '%s'", filesize, file_size_limit, object_value)
    else
        result = __api.send_file_from_fs_to(dst, object_value, filename)
        reason = result and "uploaded successful" or "internal_error"
    end

    action_data.data.result = result
    action_data.data.reason = reason
    return result, result and
        "fu_" .. object_name .. "_upload_successful" or
        "fu_" .. object_name .. "_upload_failed"
end

local function perform_action(src, dst, action_name, action_data)
    local action_result, event_name = exec_action(dst, action_name, action_data)
    push_event(event_name, action_name, action_data)

    -- is internal communication from collector module
    if __imc.is_exist(src) then
        local mod_name, group_id = __imc.get_info(src)
        __log.debugf("internal message received from module '%s' group %s", mod_name, group_id)
    else
        __log.debug("message received from the server")
        __api.send_data_to(src, cjson.encode({
            ["retaddr"] = action_data.retaddr,
            ["status"] = action_result,
            ["error"] = not action_result and action_data.data.reason or nil,
            ["agent_id"] = __aid,
            ["name"] = action_name,
            ["type"] = "exec_upload_resp",
        }))
    end

    return action_result
end

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
        local dst = get_server_token()
        if dst ~= "" then
            local action_result = perform_action(src, dst, name, action_data)
            __log.infof("requested action '%s' was executed with result: %s", name, action_result)
        else
            table.insert(files_queue, {
                src = src,
                name = name,
                data = action_data,
            })
            __log.infof("requested action '%s' was delayed", name)
        end
        return true
    end,

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            -- update current action and event list from new config
            module_config = cjson.decode(__config.get_current_config()) or {}
            current_event_config = __config.get_current_event_config()
            module_info = __config.get_module_info()

            -- renew current event engine instance
            if event_engine ~= nil then
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

push_event("fu_module_started", "", {["data"] = {}})
while not __api.is_close() do
    while #files_queue > 0 and not __api.is_close() do
        local dst = get_server_token()
        if dst ~= "" then
            local action = table.remove(files_queue, 1)
            local action_result = perform_action(action.src, dst, action.name, action.data)
            __log.infof("delayed action '%s' was performed with result: %s", action.name, action_result)
            __api.await(50)
        else
            break
        end
    end
    __api.await(1000)
end
push_event("fu_module_stopped", "", {["data"] = {}})

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
