require("engine")
require("file_reader")
local lfs     = require("lfs")
local glue    = require("glue")
local cjson   = require("cjson.safe")
local thread  = require("thread")
local luapath = require("path")

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
local store_dir = luapath.combine(lfs.currentdir(), "store")
lfs.mkdir(store_dir)

-- Module mutable global variables
local receivers = {}
local messages_queue = {}
local server_token = ""
local queue_size = tonumber(__args["queue_size"][1])
local is_send_messages = module_config.target_path ~= ""

-- generate and return uuid
local function make_uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- return number
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- events executor by event name, action and action_data
local function push_event(event_name, action_name, action_data)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(action_name) == "string", "action_name must be a string")
    assert(type(action_data) == "table", "action_data must be a table")
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
        __metric.add_int_counter("frd_agent_events_send_count", message.count)
        __metric.add_int_counter("frd_agent_events_send_size", message.size)
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
            __metric.add_int_counter("frd_agent_events_drop", cnt)
            collectgarbage("collect")
            __metric.add_int_gauge_counter("frd_agent_mem_usage", collectgarbage("count")*1024)
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
    local config_json = string.format([[{
        "servers": {
            "tcp_and_udp": {
                "tcp": {
                    "binding": {
                        "FQDN": "0.0.0.0"
                    },
                    "port": 0,
                    "message_size_max": 1048576
                },
                "udp": {
                    "binding": {
                        "IP4": "0.0.0.0"
                    },
                    "port": 0,
                    "read_buffer_size": 65536
                }
            }
        },
        "event_buffer_size": 512,
        "output_format": "JSON",
        "special_events_assembly_settings": {
            "assembly_interval": 1,
            "event_record_groups": {
                "auditd": {
                    "key_includes_src_ip": false,
                    "key_fields_from_records": [
                        "timestamp",
                        "eventid"
                    ],
                    "filter_regexps": [
                        ".*type=(?P<type>\\S+)\\s.*audit.*\\((?P<timestamp>[0-9]*[.,]?[0-9]+):(?P<eventid>[0-9]+)\\):\\s*(?P<value>.*)"
                    ],
                    "group_by_field_settings": {
                        "regex_group_for_field_name": "type",
                        "regex_group_for_value": "value"
                    }
                }
            }
        },
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
            "send_interval": 500
        },
        "module_settings": {
            "keepalive_interval": 500,
            "metric": false,
            "scope_id": "%s",
            "tenant_id": "%s",
            "logging": "<?xml version='1.0' encoding='utf-8'?><config><root><Logger level='ERROR'/><Metric level='ERROR'/><SysLog level='ERROR'/><ModuleRunner level='ERROR'/><ModuleHost level='ERROR'/></root></config>",
            "agent_id": "",
            "task_id": "",
            "historical": false
        },
        "memory_settings": {
            "chunk_size": 1024,
            "pre_allocated_memory": 3,
            "max_allowed_memory": 64
        }
    }]], tostring(params.scope_id), tostring(params.tenant_id))

    local config = cjson.decode(config_json)
    local log_files = {}
    for _, fl in ipairs(module_config.log_files or {}) do
        log_files[fl["filepath"]] = {
            ["select"] = fl["select"] or "*",
            ["suppress"] = fl["suppress"] or "",
        }
    end
    config["log_channels"] = log_files

    return cjson.encode(config)
end

local want_to_quit = false
local q_in = thread.queue(100)
local q_out = thread.queue(100)
local q_e_stop = thread.event()
local q_e_quit = thread.event()
local wm_e = CFileReader(q_in, q_out, q_e_stop, q_e_quit, get_profile(), store_dir)

-- return nil
local function handler()
    local cnt = 0
    local status, msg
    repeat
        status, msg = q_out:shift(os.time() + 0.05)
        if status and type(msg) == "table" then
            if msg.type == "result" and type(msg.data) == "string" then
                local events = cjson.decode(msg.data) or {}
                local messages = {}
                for _, event in ipairs(events) do
                    if type(event) == "table" then
                        local jbody = cjson.decode(event.body)
                        if jbody and type(jbody) == "table" then
                            if (jbody.node == nil) then jbody.node = "127.0.0.1" end
                            event.body = cjson.encode(jbody) or ""
                            table.insert(messages, cjson.encode(event) or "")
                            event.body = jbody
                        elseif type(event.body) == "string" and string.find(event.body, "node=") == nil then
                            event.body = event.body .. " node=127.0.0.1"
                            table.insert(messages, cjson.encode(event) or "")
                        end
                    end
                end
                if not want_to_quit and not __api.is_close() then
                    send_to_receivers(events)
                end
                send_log(messages)
            elseif msg.type == "debug" and type(msg.data) == "table" then
                __log.info(glue.unpack(msg.data))
            elseif msg.type == "error" and type(msg.data) == "string" then
                __log.errorf("catch error from file reader log collector: '%s': '%s'", msg.data, msg.err)
                push_event("frd_module_internal_error", "", {["data"] = {reason = msg.data}})
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

local function exec_action(action_name, action_data)
    local log_filepath
    local set_failure = function(reason)
        action_data.data.result = false
        action_data.data.reason = reason
        return false, "frd_module_internal_error"
    end

    if action_name == "frd_rewind_logfile" then
        log_filepath = action_data.data["log.filepath"]
    else
        __log.errorf("unknown action '%s' was requested", action_name)
        return set_failure("action_unknown")
    end

    if log_filepath == nil or log_filepath == "" then
        __log.error("requested file path is empty")
        return set_failure("file_path_is_empty")
    end
    action_data.data["uuid"] = action_data.data["uuid"] or make_uuid()

    q_e_stop:set()
    wm_e:wait()
    wm_e:rewind(store_dir, log_filepath)
    q_e_stop:clear()
    q_e_quit:clear()
    wm_e = CFileReader(q_in, q_out, q_e_stop, q_e_quit, get_profile(), store_dir)

    action_data.data.result = true
    action_data.data.reason = "rewind successful"
    return true, "frd_logfile_rewinded_successful"

end

__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)

        -- execute received action
        local action_data = cjson.decode(data) or {}
        local action_result, event_name = exec_action(name, action_data)
        push_event(event_name, name, action_data)

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

            -- reload configuration for file reader library
            q_e_stop:set()
            wm_e:wait()
            q_e_stop:clear()
            q_e_quit:clear()
            wm_e = CFileReader(q_in, q_out, q_e_stop, q_e_quit, get_profile(), store_dir)
        end
        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

push_event("frd_module_started", "", {["data"] = {reason = "regular start"}})

update_receivers()

while not handler() do
    __metric.add_int_gauge_counter("frd_agent_mem_usage", collectgarbage("count")*1024)
    __api.await(300)
end

-- wait file reader library instance
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
        __metric.add_int_counter("frd_agent_events_drop", cnt)
    end
end

push_event("frd_module_stopped", "", {["data"] = {reason = "regular stop"}})

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
