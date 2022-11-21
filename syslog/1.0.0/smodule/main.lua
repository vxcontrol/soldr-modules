local uri    = require("uri")
local uuid   = require("uuid")
local crc32  = require("crc32")
local cjson  = require("cjson.safe")
local socket = require("socket")
math.randomseed(crc32(tostring({})))

-- variables to send events and other data to syslog server
local last_connect = 0
local limit_secs_connect = 10
local last_sent = 0
local limit_secs = tonumber(__args["sender_limits"][1])
local limit_nums = tonumber(__args["sender_limits"][2])
local target_sock, target_host, target_port, target_connect
local id = tostring(math.random(1000, 10000))
local event_queue = {}

-- variables to execute actions on agent side
local module_config = cjson.decode(__config.get_current_config())

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

local function tcp_connect(host, port)
    local sock = socket.connect(host, port)
    if sock == nil then
        __log.errorf("failed to connect to tcp target")
        return nil
    end
    __log.infof("connect to tcp target: successful")
    local mt = getmetatable(sock)
    mt.__index.send_data = function(self, data)
        return self:send(data)
    end
    return sock
end

local function udp_connect(host, port)
    local sock = socket.udp()
    if sock == nil then
        __log.errorf("failed to connect to udp target")
        return nil
    end
    __log.infof("connect to udp target: successful")
    local mt = getmetatable(sock)
    mt.__index.send_data = function(self, data)
        return self:sendto(data, host, port)
    end
    return sock
end

local function get_date(event, date)
    local etime = event.data["time"]
    if type(etime) ~= "string" then
        return date
    end

    local is_utc = true
    local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z"
    local year, month, day, hour, minute, seconds = etime:match(pattern)

    if not year or not month or not day or not hour or not minute or not seconds then
        pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
        year, month, day, hour, minute, seconds = etime:match(pattern)
        if not year or not month or not day or not hour or not minute or not seconds then
            return date
        end
        is_utc = false
    end

    local timestamp = os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = minute,
        sec = seconds,
    })
    return os.date((is_utc and "" or "!") .. "%b %d %H:%M:%S", timestamp)
end

local function make_syslog_event(event, date)
    local data = {}
    for field, value in pairs(event.data) do
        table.insert(data, {
            Name = field,
            text = value,
        })
    end

    event.data.module = event.module
    event.data.name = event.name
    event.data.uuid = event.data.uuid or uuid.generate()
    return string.format("<30>%s %s vxserver[%s]: %s",
        get_date(event, date), event.fqdn, id, cjson.encode(event.data))
end

local function send_events(recn)
    local event_queue_len = #event_queue
    local now = os.time(os.date("!*t"))
    recn = recn or 0
    if recn > 100 then
        return
    end
    if not target_sock and target_connect and now - last_connect > limit_secs_connect then
        target_sock = target_connect(target_host, target_port)
        last_connect = now
    end
    if target_sock then
        if event_queue_len ~= 0 and (event_queue_len >= limit_nums or now - last_sent > limit_secs) then
            local date = os.date("!%b %d %H:%M:%S")
            local event_queue_s = event_queue_len > limit_nums and limit_nums or event_queue_len
            local event_queue_m = {}
            for i=1,event_queue_s do
                table.insert(event_queue_m, make_syslog_event(event_queue[i], date))
            end
            local msg = table.concat(event_queue_m, "\n") .. "\n"
            if target_sock:send_data(msg) then
                __metric.add_int_counter("syslog_server_events_send_count", #event_queue_m)
                __metric.add_int_counter("syslog_server_events_send_size", #msg)
                if event_queue_len == event_queue_s then
                    event_queue = {}
                else
                    for _=1,event_queue_s do
                        table.remove(event_queue, 1)
                    end
                end
                last_sent = now
                if #event_queue > limit_nums then
                    send_events(recn + 1)
                end
            else
                if target_sock ~= nil then
                    target_sock:close()
                    target_sock = nil
                end
            end
        end
    elseif event_queue_len >= limit_nums * 5 and now - last_sent > limit_secs then
        __log.error("dropped current events cache: %d", event_queue_len)
        __metric.add_int_counter("syslog_server_events_drop", #event_queue)
        event_queue = {}
        last_sent = now
    end
end

local function configure_socket(target_path)
    if target_sock ~= nil then
        __log.debug("close current connection")
        target_sock:close()
        target_sock = nil
    end

    if type(target_path) == "string" and target_path ~= "" then
        target_path = target_path:match'^()%s*$' and '' or target_path:match'^%s*(.*%S)'
        local parsed_path = uri.parse(target_path)
        local target_proto = parsed_path["scheme"] or "udp"
        target_host = parsed_path["host"] or (parsed_path["path"] and string.match(parsed_path["path"], "([^:]*)") or parsed_path["path"]) or "127.0.0.1"
        target_port = tonumber(parsed_path["port"] or (parsed_path["path"] and string.match(parsed_path["path"], "[^:]*:(.*)")) or "514")
        if target_proto == "tcp" then
            __log.debugf("use syslog tcp target: '%s:%d'", target_host, target_port)
            target_connect = tcp_connect
        elseif target_proto == "udp" then
            __log.debugf("use syslog udp target: '%s:%d'", target_host, target_port)
            target_connect = udp_connect
        else
            __log.errorf("unsupported target protocol scheme: '%s'", target_proto)
            target_host = nil
            target_port = nil
            target_connect = nil
        end
    else
        target_connect = nil
        __log.info("target server is not set")
    end
end

configure_socket(get_option_config("target_path"))

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function(src, data)
        __log.debugf("receive data from '%s' with data %s", src, data)

        local msg_data = cjson.decode(data)
        local ainfo = {}
        for dst, info in pairs(__agents.get_by_dst(src)) do
            if dst == src then
                ainfo = info
                break
            end
        end
        if msg_data["type"] == "events" then
            __metric.add_int_counter("syslog_server_events_recv_count", #msg_data["message"])
            __metric.add_int_counter("syslog_server_events_recv_size", #data)
            for _, event in ipairs(msg_data["message"]) do
                if not event.fqdn then
                    local hostname = "unknown"
                    if ainfo.Info ~= nil and ainfo.Info.Net ~= nil then
                        hostname = ainfo.Info.Net.Hostname
                    end
                    event.fqdn = event.data.fqdn or hostname
                end
                if not event.data.actions and event.actions then
                    event.data.actions = event.actions
                end
                table.insert(event_queue, event)
            end
        end
        return true
    end,

    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            module_config = cjson.decode(__config.get_current_config())
            configure_socket(get_option_config("target_path"))
        end
        return true
    end,
})

local function update_syslog_stats()
    __metric.add_int_gauge_counter("syslog_server_mem_usage", collectgarbage("count")*1024)
    __metric.add_int_gauge_counter("syslog_server_events_queue_count", #event_queue)
end

__log.infof("module '%s' was started", __config.ctx.name)

while not __api.is_close() do
    send_events()
    update_syslog_stats()
    __api.await(100)
end

if target_sock ~= nil then
    limit_secs = 0
    send_events()
    update_syslog_stats()
    target_sock:close()
end

if #event_queue ~= 0 then
    __metric.add_int_counter("syslog_server_events_drop", #event_queue)
end

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
