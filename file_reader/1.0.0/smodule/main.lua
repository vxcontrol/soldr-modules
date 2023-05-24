local uri    = require("uri")
local crc32  = require("crc32")
local cjson  = require("cjson.safe")
local socket = require("socket")
math.randomseed(crc32(tostring({})))

local module_config = cjson.decode(__config.get_current_config())
local sid = tostring(math.random(1000, 10000))
local last_connect = 0
local limit_secs_connect = 10
local last_sent = 0
local limit_secs = tonumber(__args["sender_limits"][1])
local limit_nums = tonumber(__args["sender_limits"][2])
local target_path, target_sock, target_proto, target_host, target_port, target_connect
local log_lines = {}

-- return number value that present events amount inside
local function get_log_lines(num)
    local size = 0
    if num > #log_lines or num < -1 then num = #log_lines end
    for i=1,num do
        size = size + #log_lines[i]["message"]
    end
    return num, size
end

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

-- getting agent ID by dst token and agent type
local function get_agent_id_by_dst(dst, atype)
    for client_id, client_info in pairs(__agents.get_by_dst(dst)) do
        if client_id == dst then
            if tostring(client_info.Type) == atype then
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

local function tcp_connect(host, port)
    local sock = socket.connect(host, port)
    if sock == nil then
        __log.errorf("connect to tcp target '%s:%d': failed", host, port)
        return nil
    end
    __log.infof("connect to tcp target '%s:%d': successful", host, port)
    local mt = getmetatable(sock)
    mt.__index.send_data = function(self, data)
        return self:send(data)
    end
    return sock
end

local function udp_connect(host, port)
    local sock = socket.udp()
    if sock == nil then
        __log.errorf("connect to udp target '%s:%d': failed", host, port)
        return nil
    end
    __log.infof("connect to udp target '%s:%d': successful", host, port)
    local mt = getmetatable(sock)
    mt.__index.send_data = function(self, data)
        return self:sendto(data, host, port)
    end
    return sock
end

local function send_logs(recn)
    local log_lines_len = #log_lines
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
        local send = function(msg, len)
            if target_sock:send_data(msg) then
                local cnt, size = get_log_lines(len)
                __metric.add_int_counter("frd_server_events_send_count", cnt)
                __metric.add_int_counter("frd_server_events_send_size", size)
                if log_lines_len == len then
                    log_lines = {}
                else
                    for _=1,len do
                        table.remove(log_lines, 1)
                    end
                end
                last_sent = now
                if #log_lines > limit_nums then
                    send_logs(recn + 1)
                end
            else
                target_sock = nil
            end
        end
        if log_lines_len ~= 0 and (log_lines_len >= limit_nums or now - last_sent > limit_secs) then
            local msg
            local date = os.date("!%b %d %H:%M:%S")
            local log_lines_s = log_lines_len > limit_nums and limit_nums or log_lines_len
            local log_lines_m = {}
            for i=1,log_lines_s do
                msg = string.format("<30>%s %s vxserver[%s]: %s",
                    date, log_lines[i]["data"]["hostname"], sid, log_lines[i]["message"])
                table.insert(log_lines_m, msg)
            end
            msg = table.concat(log_lines_m, "\n") .. "\n"
            send(msg, log_lines_s)
        end
    elseif log_lines_len >= limit_nums * 5 and now - last_sent > limit_secs then
        __log.errorf("dropped current log events cache: %d", log_lines_len)
        __metric.add_int_counter("frd_server_events_drop", #log_lines)
        log_lines = {}
        last_sent = now
    end
end

local function configure_socket()
    target_path = get_option_config("target_path")

    if target_sock ~= nil then
        __log.info("close current connection on configure_socket")
        target_sock:close()
        target_sock = nil
    end

    if type(target_path) == "string" and target_path ~= "" then
        target_path = target_path:match'^()%s*$' and '' or target_path:match'^%s*(.*%S)'
        local parsed_path = uri.parse(target_path)
        target_proto = parsed_path["scheme"] or "tcp"
        target_host = parsed_path["host"] or (parsed_path["path"] and
            string.match(parsed_path["path"], "([^:]*)") or parsed_path["path"]) or "127.0.0.1"
        target_port = tonumber(parsed_path["port"] or (parsed_path["path"] and
            string.match(parsed_path["path"], "[^:]*:(.*)")) or "514")
        if target_proto == "tcp" then
            __log.info("use syslog tcp target")
            target_connect = tcp_connect
        else
            __log.info("use syslog udp target")
            target_connect = udp_connect
        end
    else
        target_connect = nil
        __log.info("target server is not set")
    end
end

configure_socket()

__api.add_cbs({
    data = function(src, data)
        local msg_data = cjson.decode(data)
        local vxagent_id, client_info = get_agent_id_by_dst(src, "VXAgent")
        local bagent_id = get_agent_id_by_dst(src, "Browser")
        local eagent_id = get_agent_id_by_dst(src, "External")
        if vxagent_id ~= "" then
            if type(msg_data["data"]) ~= "table" then
                msg_data["data"] = {}
            end
            local aid, hostname = tostring(client_info.ID), nil
            if client_info.Info ~= nil and client_info.Info.Net ~= nil then
                hostname = tostring(client_info.Info.Net.Hostname)
            end
            msg_data["data"]["hostname"] = hostname or aid or src
            if msg_data["type"] == "log" and type(msg_data["message"]) == "table" then
                __metric.add_int_counter("frd_server_events_recv_count", #msg_data["message"])
                __metric.add_int_counter("frd_server_events_recv_size", #data)
                if target_path ~= "" then
                    for _, msg in ipairs(msg_data["message"]) do
                        table.insert(log_lines, {
                            message = msg,
                            data = msg_data.data,
                        })
                    end
                else
                    __log.debugf("receive log message (events amount): '%d'", #msg_data["message"])
                end
            elseif msg_data["type"] == "update_file_list_resp" then
                local browser_id = msg_data.retaddr
                msg_data.retaddr = nil
                __api.send_data_to(browser_id, cjson.encode(msg_data))
            else
                __log.debugf("receive enexpected message: '%s' and type '%s'",
                msg_data["type"], type(msg_data["message"]))
            end
        else
            -- msg from browser or external...
            local agent_id = bagent_id ~= "" and bagent_id or eagent_id
            local dst, _ = get_agent_src_by_id(agent_id, "VXAgent")
            msg_data.retaddr = src
            __api.send_data_to(dst, cjson.encode(msg_data))
        end
        return true
    end,

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)

        local action_data = cjson.decode(data)
        assert(type(action_data) == "table", "input action data type is invalid")
        action_data.retaddr = src
        local id, _ = get_agent_id_by_dst(src, "Browser")
        local dst, _ = get_agent_src_by_id(id, "VXAgent")
        if dst ~= "" then
            __log.debugf("send action request to '%s'", dst)
            __api.send_action_to(dst, cjson.encode(action_data), name)
        else
            local payload = {
                status = "error",
                error = "connection_error",
            }
            __log.debugf("send response data to '%s'", src)
            __api.send_data_to(src, cjson.encode(payload))
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
            configure_socket()
        end
        return true
    end,
})

local function update_frd_stats()
    __metric.add_int_gauge_counter("frd_server_mem_usage", collectgarbage("count")*1024)
    __metric.add_int_gauge_counter("frd_server_events_queue_count", #log_lines)
end

__log.infof("module '%s' was started", __config.ctx.name)

while not __api.is_close() do
    send_logs()
    update_frd_stats()
    __api.await(100)
end

if target_sock ~= nil then
    limit_secs = 0
    send_logs()
    update_frd_stats()
    target_sock:close()
end

if #log_lines ~= 0 then
    __metric.add_int_counter("frd_server_events_drop", #log_lines)
end

__log.infof("module '%s' was stopped", __config.ctx.name)

return 'success'
