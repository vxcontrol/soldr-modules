local cjson    = require("cjson.safe")
local protocol = require("protocol/protocol")

require("engine")
require("protocol/actions_validator")

local smodule = {}

--- Module quit trigger handler.
-- @param reason Defines reason for a module stop (agent_stop, module_remove, module_update).
smodule.quit_handler = function(_) end

--- New agent connected handler.
-- @param dst Connected agent token.
smodule.agent_connected_handler = function(_) end

--- Agent disconnected handler.
-- @param dst Disconnected agent token.
smodule.agent_disconnected_handler = function(_) end

--- Module configuration update handler.
-- @param previous_config Previous config object.
-- @param new_config New config object.
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

    smodule.actions = create_strict_strings_set(smodule.action_validator.actions, "action")
    smodule.events = create_strict_strings_set(smodule.event_engine.event_name_list, "event")
    smodule.fields = create_strict_strings_set(smodule.action_validator.fields_validators, "field")
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

smodule.push_event = function(agent_id, event_name, event_data, actions)
    assert(agent_id ~= nil and agent_id ~= "", "agent id must be defined")
    assert(event_name ~= nil and event_name ~= "", "event name must be defined")
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
        for action_id, action_result in ipairs(smodule.action_engine:exec(agent_id, actions_list)) do
            __log.infof("action '%s' was requested and executed with result: %s", action_id, action_result)
        end
    end
end

smodule.start = function(action_handlers, data_handlers, background_process)
    __api.add_cbs({
        data = function(src, data)
            local msg_data = cjson.decode(data) or {}
            local return_dst = msg_data.__retaddr
            msg_data.__cid = msg_data.__cid or make_uuid()

            -- If message is a valid response then it need to be proxied back to initial caller
            local vxagent_id = get_agent_id_by_dst(src, "VXAgent")
            if vxagent_id ~= "" and return_dst ~= nil and return_dst ~= "" then
                msg_data.__retaddr = nil
                return __api.send_data_to(return_dst, cjson.encode(msg_data))
            end

            local action_name = msg_data.name

            local response = {
                __retaddr = return_dst,
                __cid = msg_data.__cid,
                __aid = __aid,
                __msg_type = protocol.message_name.internal_data_response,
                name = action_name,
                -- NOTE(mkochegarov): Request data can be quite large for 'data' requests
                --                    that's why it was decided not to copy it back into response
                -- request_data = cjson.decode(cjson.encode(msg_data)),
            }

            -- TODO: it is not possible to do a validation of the "data" messages
            --       as we don't have schemas for them, once schemas are introduced
            --       validation can be added here

            -- Server module can handle data request on it's own
            local data_handler = (data_handlers or {})[action_name]
            if data_handler ~= nil then
                response.error, response.data = data_handler.handler(msg_data.data)
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

            __log.debugf("data message '%s' was proxied", action_name)
            __api.send_msg_to(src, cjson.encode({
                __msg_type = protocol.message_name.data_proxied,
                __cid = msg_data.__cid,
                name = action_name,
            }), protocol.message_type.info)

            msg_data.__msg_type = msg_data.__msg_type or protocol.message_name.data_request
            msg_data.__retaddr = src
            return __api.send_data_to(dst, cjson.encode(msg_data))
        end,

        action = function(src, data, action_name)
            local action_data = cjson.decode(data) or {}

            action_data.__cid = action_data.__cid or make_uuid()

            local response = {
                __retaddr = action_data.__retaddr,
                __cid = action_data.__cid,
                __msg_type = protocol.message_name.action_response,
                name = action_name,
                request_data = cjson.decode(cjson.encode(action_data)),
            }

            local result, error, reason = smodule.action_validator:validate(action_name, action_data.data)
            if not result then
                response.status = "error"
                response.error = error
                response.reason = reason
                __log.errorf("%s: %s", error, reason)
                return __api.send_data_to(src, cjson.encode(response))
            end

            -- Server module can handle action on it's own
            local action_handler = (action_handlers or {})[action_name]
            if action_handler ~= nil then
                response.error, response.data = action_handler.handler(action_data.data)
                response.status = (response.error == nil) and "success" or "error"
                return __api.send_data_to(src, cjson.encode(response))
            end

            -- Server module can't handle action so it need to be proxied to the agent
            local id, _ = get_agent_id_by_dst(src, "any")
            local dst, _ = get_agent_src_by_id(id, "VXAgent")
            if dst == "" then
                response.status, response.error = "error", protocol.connection_errors.common
                __log.errorf("%s: connected agent not found, src: %s", response.error, src)
                return __api.send_data_to(src, cjson.encode(response))
            else
                response.__aid = id
            end

            __log.debugf("action '%s' was proxied", action_name)
            __api.send_msg_to(src, cjson.encode({
                __msg_type = protocol.message_name.action_proxied,
                __cid = action_data.__cid,
                name = action_name,
            }), protocol.message_type.info)

            action_data.__msg_type = action_data.__msg_type or protocol.message_name.action_request
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
                    smodule.quit_handler(data)
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

    __log.infof("module '%s' was started", __config.ctx.name)

    if background_process ~= nil then
        while not __api.is_close() do
            local result, await_time = background_process()
            if not result then
                __log.errorf("module '%s' background process failed it's execution")
                break
            end
            -- default await time is 1 second, which can be changed by a background_process()
            await_time = await_time or 1000
            __api.await(await_time)
        end
    else
        __api.await(-1)
    end

    smodule.unload_dependencies()

    __log.infof("module '%s' was stopped", __config.ctx.name)

    return "success"
end

-- NOTE: initial module dependencies are gonna be loaded automatically
-- even before "start" is called, that is done in this way to make it
-- possible to use data from actions/events/fields in module code
smodule.load_dependencies()

return smodule
