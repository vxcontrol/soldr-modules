require("engine")
require("wineventlog")
local lfs    = require("lfs")
local glue   = require("glue")
local cjson  = require("cjson.safe")
local thread = require("thread")

-- variables to initialize event and action engines
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()
local module_config = cjson.decode(__config.get_current_config())

-- event and action engines initialization
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

-- creating module store folder
lfs.mkdir(lfs.currentdir() .. "\\store")

-- Module mutable global variables
local receivers = {}
local messages_queue = {}
local server_token = ""
local queue_size = tonumber(__args["queue_size"][1])
local is_send_messages = module_config.target_path ~= ""

-- return number
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- events executor by event name and data
local function push_event(event_name, event_data)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(event_data) == "table", "event_data must be a table")
    __log.debugf("push event to correlator: '%s'", event_name)

    -- push the event to the engine
    local info = {
        ["name"] = event_name,
        ["data"] = event_data,
        ["actions"] = {},
    }
    local result, list = event_engine:push_event(info)

    -- check result return variable as marker is there need to execute actions
    if result then
        for action_id, action_result in ipairs(action_engine:exec(__aid, list)) do
            __log.debugf("action '%s' was requested: '%s'", action_id, action_result)
        end
    end
end

-- return nil
local function update_receivers()
    receivers = {}
    local args_receivers = type(__args["receivers"]) == "table" and __args["receivers"] or {}
    local mlist = glue.extend({}, module_config.receivers or {}, args_receivers)
    for irx, module_name in ipairs(mlist) do
        local minfo = " | group_id: " .. __gid .. " | module: " .. module_name
        local token = __imc.make_token(module_name, __gid)
        __log.debugf("receiver[%s] | token: '%s' %s", irx, token, minfo)
        receivers[module_name] = token
    end
end

-- return boolean
local function send(message)
    if tablelength(__agents.get_by_dst(server_token)) == 0 then
        local agents = __agents.dump()
        for _, data in pairs(agents) do
            server_token = data.Dst
            if server_token ~= "" then
                break
            end
        end
    end
    if server_token == "" then
        return false
    end
    if __api.send_data_to(server_token, message.data) then
        __metric.add_int_counter("wel_agent_events_send_count", message.count)
        __metric.add_int_counter("wel_agent_events_send_size", message.size)
        return true
    end
    server_token = ""
    return false
end

-- return boolean
local function send_to_receivers(events)
    local msg = cjson.encode(events)
    if msg == nil then
        __log.errorf("failed to serialize events message: %s", tostring(events))
        return
    end
    for _, imc_token in pairs(receivers) do
        __api.send_data_to(imc_token, msg)
    end
end

-- return nil
local function resend()
    for _=1,#messages_queue do
        if send(messages_queue[1]) then
            table.remove(messages_queue, 1)
        else
            return
        end
    end
end

-- return nil
local function send_log(msgs)
    if not is_send_messages then
        return
    end

    local msg_data = {
        ["type"] = "log",
        ["message"] = msgs,
        ["data"] = {},
    }
    local data = cjson.encode(msg_data)
    local message = {data = data, count = #msgs, size = #data}
    if not send(message) then
        if #messages_queue >= queue_size + 100 then
            __log.error("drop message from queue because size limit exceeded")
            local cnt = 0
            for _=1,100 do
                cnt = cnt + messages_queue[1].count
                table.remove(messages_queue, 1)
            end
            __metric.add_int_counter("wel_agent_events_drop", cnt)
            collectgarbage("collect")
            __metric.add_int_gauge_counter("wel_agent_mem_usage", collectgarbage("count")*1024)
        end
        table.insert(messages_queue, message)
    end
end

-- return string
local function get_profile()
    local params = {
        scope_id  = "00000000-0000-0000-0000-000000000005",
        tenant_id = "00000000-0000-0000-0000-000000000000",
    }
    local config_json = string.format([[
        {
            "connection": {
                "auth": {
                    "domain": "",
                    "login": "",
                    "password": ""
                },
                "auth_type": "Negotiate"
            },
            "event_buffer_size": 512,
            "output_format": "JSON",
            "log_channels": {
            },
            "actualization_period": 500,
            "new_events_only": true,
            "inputs": {
                "00000000-0000-0000-0000-000000000000": {
                    "description": {
                        "expected_datetime_formats": [
                            "DATETIME_ISO8601",
                            "DATETIME_YYYYMMDD_HHMMSS"
                        ]
                    }
                }
            },
            "result_package": {
                "package_quantity": 100,
                "send_interval": 100
            },
            "module_settings": {
                "keepalive_interval": 500,
                "pre_reconnect_delay": 60000,
                "number_of_reconnects": 15,
                "metric": false,
                "scope_id": "%s",
                "tenant_id": "%s",
                "logging": "<?xml version='1.0' encoding='utf-8'?><config><root><Logger level='ERROR'/><Metric level='ERROR'/><wineventlog level='ERROR'/><ModuleRunner level='ERROR'/><ModuleHost level='ERROR'/></root></config>",
                "agent_id": "",
                "task_id": "",
                "historical": false
            },
            "memory_settings": {
                "chunk_size": 1024,
                "pre_allocated_memory": 16,
                "max_allowed_memory": 256
            }
        }
    ]], tostring(params.scope_id), tostring(params.tenant_id))

    local config = cjson.decode(config_json)
    local log_channels = {}
    for _, ch in ipairs(module_config.log_channels or {}) do
        log_channels[ch["channel"]] = {
            ["select"] = ch["select"],
            ["suppress"] = ch["suppress"],
        }
    end
    config["log_channels"] = log_channels

    return cjson.encode(config)
end

local want_to_quit = false
local q_in = thread.queue(100)
local q_out = thread.queue(100)
local q_e_stop = thread.event()
local q_e_quit = thread.event()
local wm_e = CWinEventLog(q_in, q_out, q_e_stop, q_e_quit, get_profile())

-- return nil
local function handler()
    local cnt = 0
    local status, msg
    repeat
        status, msg = q_out:shift(os.time() + 0.2)
        if status and type(msg) == "table" then
            if msg.type == "result" and type(msg.data) == "string" then
                local events = cjson.decode(msg.data) or {}
                local messages = {}
                for _, event in ipairs(events) do
                    table.insert(messages, cjson.encode(event) or "")
                    if type(event) == "table" then
                        event.body = cjson.decode(event.body) or {}
                    end
                end
                if not want_to_quit and not __api.is_close() then
                    send_to_receivers(events)
                end
                send_log(messages)
            elseif msg.type == "debug" and type(msg.data) == "table" then
                __log.info(glue.unpack(msg.data))
            elseif msg.type == "error" and type(msg.data) == "string" then
                __log.errorf("catch error from windows events log collector: '%s': '%s'", msg.data, msg.err)
                push_event("wel_module_internal_error", {reason = msg.data})
            end
        end
        cnt = cnt + 1
        __api.await(10)
    until not status or cnt >= 20

    if q_e_quit:isset() and want_to_quit then
        __log.info("condition to quit worker is set")
    end

    resend()
    return q_e_quit:isset() and want_to_quit
end

__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "quit" then
            -- notify library to quit
            q_e_stop:set()
            want_to_quit = true
            __log.info("send message to the library to stop")
        end
        if cmtype == "update_config" then
            -- update current action and event list from new config
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

            -- renew receivers list from new current config
            module_config = cjson.decode(__config.get_current_config())
            update_receivers()
            is_send_messages = module_config.target_path ~= ""

            -- reload configuration for wineventlog library
            q_e_stop:set()
            wm_e:wait()
            q_e_stop:clear()
            q_e_quit:clear()
            wm_e = CWinEventLog(q_in, q_out, q_e_stop, q_e_quit, get_profile())
        end
        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

push_event("wel_module_started", {reason = "regular start"})

update_receivers()

while not handler() do
    __metric.add_int_gauge_counter("wel_agent_mem_usage", collectgarbage("count")*1024)
    __api.await(300)
end

-- wait wineventlog library instance
__log.info("wait to stop the library")
wm_e:wait()
q_e_stop:clear()
q_e_quit:clear()

-- free posix obects
q_in:free()
q_out:free()

-- all events mark as drop
do
    local cnt = 0
    for i=1,#messages_queue do
        cnt = cnt + messages_queue[i].count
    end
    if cnt ~= 0 then
        __metric.add_int_counter("wel_agent_events_drop", cnt)
    end
end

push_event("wel_module_stopped", {reason = "regular stop"})

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
