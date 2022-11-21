require("engine")
local ffi   = require("ffi")
local cjson = require("cjson.safe")

-- variables to initialize event and action engines
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()
local actions_config = cjson.decode(__config.get_current_action_config())

-- Module mutable global variables
local last_sent = 0
local limit_secs = tonumber(__args["sender_limits"][1])
local limit_nums = tonumber(__args["sender_limits"][2])
local limit_queue = tonumber(__args["queue_limit_size"][1])
local messages_queue = {}
local server_token = ""

-- OS specific methods and variables
local fqdn

if tostring(ffi.os) == "Windows" then
    local lk32 = require("waffi.windows.kernel32")

    local hostlen = ffi.new("DWORD[1]")
    hostlen[0] = 256
    local hostname = ffi.new("CHAR[?]", hostlen[0])
    local res = lk32.GetComputerNameExA(
        lk32.ComputerNameDnsFullyQualified,
        hostname,
        hostlen
    )
    if res ~= 0 then
        fqdn = ffi.string(hostname, hostlen[0])
    else
        fqdn = ""
    end
else
    local get_fqdn = function()
        local f = io.popen("hostname -f", "r")
        if not f then return nil end
        local s = f:read("*a")
        f:close()
        if not s then return nil end
        return s:gsub('^%s+', ''):gsub('%s+$', ''):gsub('[\n\r]+', ' ')
    end

    fqdn = get_fqdn()
end

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
        ["data"] = event_data.data or {},
        ["actions"] = event_data.actions or {},
    }
    local result, list = event_engine:push_event(info)

    -- check result return variable as marker is there need to execute actions
    if result then
        for action_id, action_result in ipairs(action_engine:exec(__aid, list)) do
            __log.debugf("action '%s' was requested: '%s'", action_id, action_result)
        end
    end
end

-- return boolean
local function send(packet)
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
    if __api.send_data_to(server_token, packet) then
        return true
    end
    server_token = ""
    return false
end

-- return nil
local function send_messages(recn)
    local messages_queue_len = #messages_queue
    local now = os.time(os.date("!*t"))
    recn = recn or 0
    if recn > 100 then
        return
    end
    if messages_queue_len ~= 0 and (messages_queue_len >= limit_nums or now - last_sent > limit_secs) then
        local packet = {
            ["type"] = "events",
            ["message"] = {},
        }
        local messages_queue_s = messages_queue_len > limit_nums and limit_nums or messages_queue_len
        for i=1,messages_queue_s do
            table.insert(packet.message, messages_queue[i])
        end
        local msg = cjson.encode(packet)
        if send(msg) then
            __metric.add_int_counter("syslog_agent_events_send_count", messages_queue_s)
            __metric.add_int_counter("syslog_agent_events_send_size", #msg)
            if messages_queue_len == messages_queue_s then
                messages_queue = {}
            else
                for _=1,messages_queue_s do
                    table.remove(messages_queue, 1)
                end
            end
            last_sent = now
            if #messages_queue > limit_nums then
                send_messages(recn + 1)
            end
        end
    end
end

-- return nil
local function add_message_to_queue(message)
    if #messages_queue >= limit_queue then
        table.remove(messages_queue, 1)
        __metric.add_int_counter("syslog_agent_events_drop", 1)
    end
    table.insert(messages_queue, message)
end

-- simple events generator by current event config
local function exec_action(action_name, action_data)
    if actions_config[action_name] == nil then
        __log.errorf("requested action '%s' not exists in current action config", action_name)
        return false
    end

    if action_name == "send_to_syslog" then
        add_message_to_queue(action_data)
    end
    return true
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

        -- is internal communication from collector module
        local mod_name = __config.ctx.name
        if __imc.is_exist(src) then
            local group_id
            mod_name, group_id = __imc.get_info(src)
            __log.debugf("internal message received from module '%s' group %s", mod_name, group_id)
        else
            __log.debug("message received from the server")
        end

        -- execute received action
        local action_data = cjson.decode(data)
        action_data.module = mod_name
        action_data.fqdn = fqdn
        action_data.actions = action_data.actions or { __config.ctx.name .. "." .. name }
        local action_result = exec_action(name, action_data)
        __log.infof("requested action '%s' was executed with result: %s", name, action_result)
        return true
    end,

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            -- update current action and event list from new config
            actions_config = cjson.decode(__config.get_current_action_config())
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

push_event("syslog_module_started", {})

while not __api.is_close() do
    send_messages()
    __metric.add_int_gauge_counter("syslog_agent_mem_usage", collectgarbage("count")*1024)
    __api.await(100)
end

send_messages()
if #messages_queue ~= 0 then
    __metric.add_int_counter("syslog_agent_events_drop", #messages_queue)
end

push_event("syslog_module_stopped", {})

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
