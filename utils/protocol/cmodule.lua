local cjson    = require("cjson.safe")
local glue     = require("glue")
local protocol = require("protocol/protocol")
local ffi      = require("ffi")

require("engine")
require("protocol/actions_validator")

local cmodule = {}
cmodule.quit_handler = function() end
cmodule.agent_connected_handler = function(_) end
cmodule.agent_disconnected_handler = function(_) end
cmodule.update_config_handler = function(_, _) end

-- TODO: use common shared uuid library
local crc32 = require("crc32")
math.randomseed(crc32(tostring({})))
local function make_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

cmodule.require = function(name)
    -- "windows", "linux", "osx", "bsd", "posix", "other"
    local os = string.lower(ffi.os)
    -- "x86", "x64", "arm", "ppc", "ppcspe", "mips"
    local arch = string.lower(ffi.arch)

    local lib_names = {
        string.format("%s_%s_%s", name, os, arch),
        string.format("%s_%s", name, os),
        string.format("%s_other_os", name)
    }

    for _, lib_name in ipairs(lib_names) do
        local result = { pcall(require, lib_name) };
        if result[1] then
            return table.unpack(result, 2, #result)
        end
    end

    error(string.format("none of modules %s found", table.concat(lib_names, ", ")), 2)
end

cmodule.unload_dependencies = function()
    if cmodule.action_engine ~= nil then
        cmodule.action_engine:free()
        cmodule.action_engine = nil
    end
    if cmodule.event_engine ~= nil then
        cmodule.event_engine:free()
        cmodule.event_engine = nil
    end
    if cmodule.action_validator ~= nil then
        cmodule.action_validator:free()
        cmodule.action_validator = nil
    end
    collectgarbage("collect")
end

local function create_strict_strings_set(table, key_type)
    local result = {}
    for key, value in pairs(table or {}) do
        if type(key) == "number" then
            result[value] = value
            result[value:gsub("[.]", "_")] = value
        else
            result[key] = key
            result[key:gsub("[.]", "_")] = key
        end
    end
    setmetatable(result, { __index = function(_, key)
        error("unknown " .. key_type .. " '" .. key .. "' requested", 2)
    end, })
    return result
end

cmodule.load_dependencies = function()
    local action_config_schema = __config.get_action_config_schema()
    local current_event_config = __config.get_current_event_config()
    local fields_schema = __config.get_fields_schema()
    local module_info = __config.get_module_info()

    cmodule.unload_dependencies()

    cmodule.action_engine = CActionEngine(
        nil,
        __args and __args.debug
    )
    cmodule.event_engine = CEventEngine(
        fields_schema, current_event_config, module_info, __gid .. ".",
        __args and __args.debug
    )
    cmodule.action_validator = CActionsValidator(
        fields_schema, action_config_schema)

    cmodule.actions = create_strict_strings_set(cmodule.action_validator.actions, "action")
    cmodule.events = create_strict_strings_set(cmodule.event_engine.event_name_list, "event")
    cmodule.fields = create_strict_strings_set(cmodule.action_validator.fields_validators, "field")
end

cmodule.push_event_for_action = function(event_name, action_name, event_data, actions)
    assert(event_name ~= nil and event_name ~= "", "event name must be defined")
    assert(action_name ~= nil and action_name ~= "", "action name must be defined")
    event_data = event_data or {}
    actions = actions or {}

    if action_name ~= "" then
        local action_full_name = __config.ctx.name .. "." .. action_name
        if glue.indexof(action_full_name, actions) == nil then
            table.insert(actions, action_full_name)
        end
    end
    cmodule.push_event(event_name, event_data, actions)
end

cmodule.push_event = function(event_name, event_data, actions)
    assert(event_name ~= nil and event_name ~= "", "event name must be defined")
    event_data = event_data or {}
    actions = actions or {}

    local event = {
        __module = __config.ctx.name,
        name = event_name, data = event_data,
        actions = actions,
    }
    local result, actions_list = cmodule.event_engine:push_event(event)

    -- result value defines if there are actions that need to be executed
    if result then
        for action_id, action_result in ipairs(cmodule.action_engine:exec(__aid, actions_list)) do
            __log.infof("action '%s' was requested and executed with result: %s", action_id, action_result)
        end
    end
end

cmodule.start = function(action_handlers, background_process)
    __api.add_cbs({

        action = function(src, data, action_name)
            local action_data = cjson.decode(data) or {}

            action_data.__cid = action_data.__cid or make_uuid()

            local response = {
                __retaddr = action_data.__retaddr,
                __cid = action_data.__cid,
                __aid = __aid,
                __msg_type = protocol.message_name.action_response,
                name = action_name,
                request_data = cjson.decode(cjson.encode(action_data)),
            }

            local result, error, reason = cmodule.action_validator:validate(action_name, action_data.data)
            if not result then
                response.status = "error"
                response.error = error
                response.reason = reason
                return __api.send_data_to(src, cjson.encode(response))
            end

            local action_handler = (action_handlers or {})[action_name]
            if action_handler == nil then
                response.status = "error"
                response.error = protocol.implementation_errors.action_handler_not_defined
                return __api.send_data_to(src, cjson.encode(response))
            end

            local action_handler_result, event_data = action_handler.handler(action_data.data)
            local event_name = action_handler.success
            if not action_handler_result then
                event_name = action_handler.failure
            end

            event_data.__cid = action_data.__cid
            event_data.uuid = action_data.uuid or make_uuid()

            cmodule.push_event_for_action(event_name, action_name, event_data)

            response.data = event_data
            if action_handler_result then
                response.status = "success"
            else
                response.status = "error"
                response.error = protocol.implementation_errors.action_handler_error
                response.reason = event_data.reason
            end
            return __api.send_data_to(src, cjson.encode(response))
        end,

        control = function(cmtype, data)
            __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

            if cmtype == "update_config" then
                local previous_config = cmodule.module_config
                cmodule.load_dependencies()
                if cmodule.update_config_handler then
                    cmodule.update_config_handler(previous_config, cmodule.module_config)
                end
            end
            if cmtype == "quit" then
                if cmodule.quit_handler then
                    cmodule.quit_handler()
                end
            end
            if cmtype == "agent_connected" then
                if cmodule.agent_connected_handler then
                    cmodule.agent_connected_handler(data)
                end
            end
            if cmtype == "agent_disconnected" then
                if cmodule.agent_disconnected_handler then
                    cmodule.agent_disconnected_handler(data)
                end
            end
            return true
        end,
    })

    __log.infof("module '%s' was started", __config.ctx.name)

    if background_process ~= nil then
        while not __api.is_close() do
            background_process()
            __api.await(1000)
        end
    else
        __api.await(-1)
    end

    cmodule.unload_dependencies()

    __log.infof("module '%s' was stopped", __config.ctx.name)

    return "success"
end

-- NOTE: initial module dependencies are gonna be loaded automatically
-- even before "start" is called, that is done in this way to make it
-- possible to use data from actions/events/fields in module code
cmodule.load_dependencies()

return cmodule
