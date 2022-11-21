require("uploader")
local lfs     = require("lfs")
local cjson   = require("cjson.safe")
local sqlite  = require("lsqlite3")
local luapath = require("path")

-- uploader variables
local uploader, fu_db
local db_file_name = "fu_" .. __gid .."_v2.db"
local path_to_db = luapath.normalize(luapath.combine(luapath.combine(lfs.currentdir(), "data"), db_file_name))
local module_config = cjson.decode(__config.get_current_config()) or {}

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

-- execute SQL quesry in local SQLite DB
local function exec_query(src, query, db)
    db:exec("BEGIN TRANSACTION;")
    local result = {type="exec_sql_resp", cols={}, rows={}}
    local rstep, err
    local status, stmt = pcall(db.prepare, db, query.sql)
    local send_result = function()
        local response, jerr = cjson.encode(result)
        if not response then
            __log.errorf("failed to encode response by exec: %s", jerr)
        end
        __api.send_data_to(src, response)
    end
    if not status then
        result.status = "error"
        result.error = stmt
        __log.errorf("failed to execute SQL query: %s", query.sql)
        db:exec("ROLLBACK;")
        send_result()
        return
    end
    repeat
        status, rstep = pcall(stmt.step, stmt)
        if status and rstep then
            table.insert(result.rows, stmt:get_values())
        end
    until (not status or not rstep)
    if not status then
        result.status = "error"
        result.error = rstep
        __log.infof("failed to execute SQL query: %s", query.sql)
    else
        result.status = "success"
        for i=0, tonumber(stmt:columns())-1 do
            table.insert(result.cols, stmt:get_name(i))
        end
        __log.infof("SQL query was executed successful: %s", query.sql)
    end
    status, err = pcall(stmt.finalize, stmt)
    if not status then
        __log.errorf("failed to finalize query statement: %s", err)
    end
    db:exec("COMMIT;")
    send_result()
end

-- getting agent ID by dst token and agent type
local function get_agent_id_by_dst(dst, atype)
    for token, info in pairs(__agents.get_by_dst(dst)) do
        if token == dst then
            if tostring(info.Type) == atype or atype == "any" then
                return tostring(info.ID), info
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

-- initialize uploader worker into global module state
local function init_uploader()
    uploader = CUploaderResp({
        db = fu_db,
        debug = __args["debug_uploader"][1] == "true",
        debug_curl = __args["debug_curl"][1] == "true",
        request_config = get_option_config("request_config"),
        request_headers = get_option_config("request_headers"),
    })
    if not uploader:worker_start() then
        __log.error("failed to initialize uploader worker")
        uploader = nil
        collectgarbage("collect")
    end
end

-- uploader cache database
fu_db = sqlite.open(path_to_db, "create")
if fu_db ~= nil then
    init_uploader()

    -- add __gc to close database on exit module
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() if fu_db then fu_db:close() end end
    fu_db[prox] = true
else
    __log.error("failled to open uploader cache database")
end

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function(src, data)
        __log.infof("receive data from '%s' with data %s", src, data)

        local msg_data = cjson.decode(data) or {}
        local vxagent_id = get_agent_id_by_dst(src, "VXAgent")
        if vxagent_id ~= "" then
            if msg_data["type"] == "exec_upload_resp" then
                __log.debugf("server module got response by exec from agent")
                local dst = msg_data.retaddr
                msg_data.retaddr = nil
                msg_data.status = msg_data.status and "success" or "error"
                local send_res = __api.send_data_to(dst, cjson.encode(msg_data))
                __log.debugf("response routed to '%s' with result %s", dst, send_res)
            else
                __log.debugf("receive unknown type message '%s' from agent", msg_data["type"])
            end
        else
            -- msg from browser or external...
            if msg_data["type"] == "exec_sql_req" then
                __log.debugf("server module got request to exec SQL query")
                exec_query(src, msg_data, fu_db)
            else
                __log.debugf("receive unknown type message '%s' from browser", msg_data["type"])
            end
        end

        return true
    end,

    file = function(src, path, name)
        __log.infof("receive file from '%s' with name '%s' path '%s'", src, name, path)

        local aid = get_agent_id_by_dst(src, "any")
        if uploader == nil or not uploader:put_file(name, path, aid) then
            __log.error("failed to process file via uploader")
        end
        return true
    end,

    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)

        local action_data = cjson.decode(data)
        assert(type(action_data) == "table", "input action data type is invalid")
        action_data.retaddr = src
        local id, _ = get_agent_id_by_dst(src, "any")
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

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with data %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            -- update current module config
            module_config = cjson.decode(__config.get_current_config()) or {}

            -- update uploader state after changing module config
            if uploader ~= nil then
                uploader:worker_stop()
            end
            init_uploader()
        end

        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

while not __api.is_close() do
    if uploader ~= nil then
        uploader:process()
    end
    __api.await(1000)
end

-- release uploader
if uploader ~= nil then
    uploader:worker_stop()
    uploader = nil
end
collectgarbage("collect")

-- release database
if fu_db ~= nil then
    fu_db = nil
end
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
