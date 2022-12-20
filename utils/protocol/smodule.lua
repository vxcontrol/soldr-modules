local cjson    = require("cjson.safe")
local glue     = require("glue")
local protocol = require("protocol/protocol")
local tablex   = require("pl.tablex")

require("engine")
require("protocol/actions_validator")

local smodule = {}
smodule.quit_handler = function() end
smodule.agent_connected_handler = function(_) end
smodule.agent_disconnected_handler = function(_) end
smodule.update_config_handler = function(_, _) end

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

smodule.unload_dependencies = function()
    if smodule.action_engine ~= nil then
        smodule.action_engine:free()
        smodule.action_engine = nil
    end
    if smodule.event_engine ~= nil then
        smodule.event_engine:free()
        smodule.event_engine = nil
    end
    if smodule.action_validator ~= nil then
        smodule.action_validator:free()
        smodule.action_validator = nil
    end
    collectgarbage("collect")
end

smodule.load_dependencies = function()
    local action_config_schema = __config.get_action_config_schema()
    local current_event_config = __config.get_current_event_config()
    local fields_schema = __config.get_fields_schema()
    local module_info = __config.get_module_info()

    smodule.module_config = cjson.decode(__config.get_current_config()) or {}

    smodule.unload_dependencies()

    smodule.action_engine = CActionEngine(
        nil,
        __args and __args.debug
    )
    smodule.event_engine = CEventEngine(
        fields_schema, current_event_config, module_info, __gid .. ".",
        __args and __args.debug
    )
    smodule.action_validator = CActionsValidator(
        fields_schema, action_config_schema)
end

-- getting agent ID by dst token and agent type
local function get_agent_id_by_dst(dst, atype)
    for client_id, client_info in pairs(__agents.get_by_dst(dst)) do
        if client_id == dst then
            if tostring(client_info.Type) == atype or atype == "any" then
                return tostring(client_info.ID), client_info
            end
        end
    end
    return "", {}
end

-- getting agent source token by ID and agent type
local function get_agent_src_by_id(id, atype)
    for client_id, client_info in pairs(__agents.get_by_id(id)) do
        if tostring(client_info.Type) == atype or atype == "any" then
            return tostring(client_id), client_info
        end
    end
    return "", {}
end

smodule.push_event_for_action = function(event_name, action_name, event_data, actions)
    assert(action_name ~= "", "event name must be defined")
    assert(action_name ~= "", "action name must be defined")
    event_data = event_data or {}
    actions = actions or {}

    if action_name ~= "" then
        local action_full_name = __config.ctx.name .. "." .. action_name
        if glue.indexof(action_full_name, actions) == nil then
            table.insert(actions, action_full_name)
        end
    end
    smodule.push_event(event_name, event_data, actions)
end

smodule.push_event = function(event_name, event_data, actions)
    assert(event_name ~= "", "event name must be defined")
    event_data = event_data or {}
    actions = actions or {}

    local event = {
        __module = __config.ctx.name,
        name = event_name, data = event_data,
        actions = actions,
    }
    local result, actions_list = smodule.event_engine:push_event(event)

    -- result value defines if there are actions that need to be executed
    if result then
        for action_id, action_result in ipairs(smodule.action_engine:exec(__aid, actions_list)) do
            __log.infof("action '%s' was requested and executed with result: %s", action_id, action_result)
        end
    end
end

smodule.start = function(action_handlers, data_callback, background_process)
    __api.add_cbs({
        data = function(src, data)
            local msg_data = cjson.decode(data) or {}
            local return_dst = msg_data.__retaddr
            local vxagent_id = get_agent_id_by_dst(src, "VXAgent")
            if vxagent_id ~= "" and return_dst ~= nil and return_dst ~= "" then
                msg_data.__retaddr = nil
                return __api.send_data_to(return_dst, cjson.encode(msg_data))
            end

            -- msg from browser or external
            if data_callback ~= nil then
                return data_callback(src, nil)
            end
            return false
        end,

        action = function(src, data, action_name)
            local action_data = cjson.decode(data) or {}

            action_data.__cid = action_data.__cid or make_uuid()

            local response = {
                __retaddr = action_data.__retaddr,
                __cid = action_data.__cid,
                __aid = __aid,
                __msg_type = protocol.message_name.action_response,
                name = action_name,
                request_data = tablex.copy(action_data),
            }

            local result, error, reason = smodule.action_validator:validate(action_name, action_data.data)
            if not result then
                response.status = "error"
                response.error = error
                response.reason = reason
                return __api.send_data_to(src, cjson.encode(response))
            end

            -- Server module can handle action on it's own
            local action_handler = (action_handlers or {})[action_name]
            if action_handler ~= nil then
                response.error, response.response_data = action_handler(action_data.data)
                response.status = (response.error == nil) and "success" or "error"
                return __api.send_data_to(src, cjson.encode(response))
            end

            -- Server module can't handle action so it need to be proxied to the agent
            local id, _ = get_agent_id_by_dst(src, "any")
            local dst, _ = get_agent_src_by_id(id, "VXAgent")
            if dst == "" then
                response.status, response.error = "error", protocol.connection_errors.common
                return __api.send_data_to(src, cjson.encode(response))
            end

            __log.debugf("action '%s' was proxied", action_name)
            __api.send_msg_to(src, cjson.encode({
                __msg_type = protocol.message_name.action_proxied,
                __cid = action_data.__cid,
                name = action_name,
            }))

            action_data.__retaddr = src
            return __api.send_action_to(dst, cjson.encode(action_data), action_name)
        end,

        control = function(cmtype, data)
            __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

            if cmtype == "update_config" then
                local previous_config = smodule.module_config
                smodule.load_dependencies()
                if smodule.update_config_handler then
                    smodule.update_config_handler(previous_config, smodule.module_config)
                end
            end
            if cmtype == "quit" then
                if smodule.quit_handler then
                    smodule.quit_handler()
                end
            end
            if cmtype == "agent_connected" then
                if smodule.agent_connected_handler then
                    smodule.agent_connected_handler(data)
                end
            end
            if cmtype == "agent_disconnected" then
                if smodule.agent_disconnected_handler then
                    smodule.agent_disconnected_handler(data)
                end
            end
            return true
        end,
    })

    smodule.load_dependencies()

    __log.infof("module '%s' was started", __config.ctx.name)

    if background_process ~= nil then
        while not __api.is_close() do
            background_process()
            __api.await(1000)
        end
    else
        __api.await(-1)
    end

    smodule.unload_dependencies()

    __log.infof("module '%s' was stopped", __config.ctx.name)

    return "success"
end

return smodule
