require("yaci")
require("strict")
local pp     = require("pp")
local lfs    = require("lfs")
local md5    = require("md5")
local sha2   = require("sha2")
local glue   = require("glue")
local crc32  = require("crc32")
local cjson  = require("cjson.safe")
local thread = require("thread")
math.randomseed(crc32(tostring({})))

CUploaderResp = newclass("CUploaderResp")

function CUploaderResp:print(...)
    if self.is_debug then
        local t = glue.pack(...)
        for i, v in ipairs(t) do
            t[i] = pp.format(v)
        end
        print(glue.unpack(t))
    end
end

--[[
    cfg top keys:
    * db - sqlite3 object to local DB.
        Use object instead construct beceause the class may used multiple times
        and destructor will called multiple times by engines response amount.
    * request_config - is a object which contains url and method keys to configure sender
    * request_headers - list of objects with name and value keys to extend request data
    * debug - boolean to run it in debug mode
    * debug_curl - boolean to run curl library client in debug mode
]]
function CUploaderResp:init(cfg)
    self.db = assert(cfg.db)
    self.request_config = cfg.request_config or {method="PUT", url=""}
    self.request_headers = cfg.request_headers or {}
    self.is_debug = cfg.debug
    self.debug_curl = cfg.debug_curl
    self.queries = {}
    self.tables = {
        files = "files"
    }
    self.fields = {
        uuid = "CHAR(40) UNIQUE",
        time = "DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))",
        filename = "TEXT",
        filesize = "INT",
        md5_hash = "CHAR(32)",
        sha256_hash = "CHAR(64)",
        local_path = "TEXT",
        upload_response = "TEXT",
        upload_code = "INT",
        agent_id = "CHAR(32)",
        group_id = "CHAR(32)",
    }
    self.file_info_fields = {
        "uuid",
        "filename",
        "filesize",
        "md5_hash",
        "sha256_hash",
        "time",
    }
    self.migrations = {
        -- ["add_new_field"] = [[
        --     ALTER TABLE ]] .. self.tables.files .. [[ ADD COLUMN new_field CHAR(32);
        -- ]],
    }

    if type(cfg.debug) == "boolean" then
        self.is_debug = cfg.debug
    end

    -- sender worker communication
    self.w_rth    = nil
    self.w_q_in   = thread.queue(100)
    self.w_q_out  = thread.queue(100)
    self.w_e_stop = thread.event()
    self.w_ctx = {
        is_debug = self.is_debug,
        debug_curl = self.debug_curl,
        url = self.request_config.url or "",
        method = self.request_config.method or "PUT",
        headers = self.request_headers,
    }

    local table_fields = {}
    for field, ftype in pairs(self.fields) do
        table.insert(table_fields, field .. " " .. ftype)
    end
    table.sort(table_fields)
    self.queries.create_table = [[
        CREATE TABLE IF NOT EXISTS ]] .. self.tables.files .. [[ (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ]] .. table.concat(table_fields, ", ") .. [[
        );
    ]]

    self.queries.get_incomplete_upload = [[
        SELECT *
        FROM ]] .. self.tables.files .. [[
        WHERE time >= datetime('now', '-7 days') AND
            group_id LIKE ? AND upload_response IS NULL
        ORDER BY time DESC;
    ]]

    self.queries.get_file_info_by_uuid = [[
        SELECT ]] .. table.concat(self.file_info_fields, ", ") .. [[
        FROM ]] .. self.tables.files .. [[
        WHERE uuid LIKE ?;
    ]]
    self.queries.get_file_info_by_hash = [[
        SELECT ]] .. table.concat(self.file_info_fields, ", ") .. [[
        FROM ]] .. self.tables.files .. [[
        WHERE md5_hash LIKE ? OR sha256_hash LIKE ?
        ORDER BY time DESC;
    ]]
    self.queries.check_duplicate_file_by_hash = [[
        SELECT ]] .. table.concat(self.file_info_fields, ", ") .. [[
        FROM ]] .. self.tables.files .. [[
        WHERE (md5_hash LIKE ? OR sha256_hash LIKE ?) AND
            time >= datetime('now', '-7 days')
        ORDER BY time DESC;
    ]]
    self.queries.get_uploaded_files = [[
        SELECT ]] .. table.concat(self.file_info_fields, ", ") .. [[
        FROM ]] .. self.tables.files .. [[
        ORDER BY time DESC;
    ]]

    local put_file_fields = {
        "uuid",
        "filename",
        "filesize",
        "md5_hash",
        "sha256_hash",
        "local_path",
        "agent_id",
        "group_id",
    }
    local prepositions = {}
    for _=1,#put_file_fields do
        table.insert(prepositions, "?")
    end
    self.queries.put_file = [[
        INSERT OR IGNORE INTO ]] .. self.tables.files .. [[ (
            ]] .. table.concat(put_file_fields, ", ") .. [[
        ) VALUES (
            ]] .. table.concat(prepositions, ", ") .. [[
        );
    ]]

    self.queries.upload_file_resp = [[
        UPDATE ]] .. self.tables.files .. [[ SET
            upload_code = ?,
            upload_response = ?
        WHERE uuid LIKE ?;
    ]]

    -- create engine table to collect raw events
    self:create_table()
    self:perform_migrations()
end

function CUploaderResp:free()
    self:print("finalize CUploaderResp object")
end

local function worker(ctx, q_in, q_out, e_stop)
    local ffi     = require("ffi")
    local lcurl   = require("libcurl")
    local lglue   = require("glue")
    local mtr     = lcurl.multi()
    local url     = ctx.url
    local method  = ctx.method
    local headers = {}
    local state   = {}
    local queue   = {}

    -- update headers list by default values
    local headers_map = {
        ["User-Agent"] = "SOLDR/1.0",
        ["Content-Type"] = "application/octet-stream",
        ["Expect"] = "",
    }
    lglue.map(ctx.headers, function(_, row)
        headers_map[row.name] = row.value
    end)
    lglue.map(headers_map, function(name, value)
        name = tostring(name) or ""
        value = tostring(value) or ""
        table.insert(headers, name .. ":" .. (value ~= "" and " " .. value or ""))
    end)

    local easy = lcurl.easy{
        post = true,
        verbose = ctx.debug_curl,
        ssl_verifyhost = false,
        ssl_verifypeer = false,
    }

    local g_print = print
    local print = function(...)
        if ctx.is_debug then
            g_print(...);
        end
    end

    local function cb_response(ec, task, raw)
        print("receive result", task.id, task.type)
        local res = ffi.string(ffi.cast("char*", raw))
        task.result = task.result .. res
        task.code = tonumber(ec:info("response_code")) or 0
        q_out:push(task)
        return #res
    end

    local function readfile(filename)
        print("readfile ", filename)
        local filedata
        local fhandle = io.open(filename, "rb")
        if nil ~= fhandle then
            filedata = fhandle:read("*all")
            fhandle:close()
        end
        print("readfile return len ", #(tostring(filedata) or ""))
        return filedata
    end

    local function get_easy_upload(task)
        local content = readfile(task.path)
        if content == nil then
            return
        end

        local ec = easy:clone()
        ec:set("postfields", content)
        ec:set("postfieldsize", #content)
        ec:set("httpheader", headers)
        ec:set("customrequest", method)
        ec:set("url", url)
        ec:set("writefunction", function(raw) return cb_response(ec, task, raw) end)
        print("made easy object to upload file", url, task.uuid, task.name)
        task.result = ""
        return ec
    end

    local function process_task(task)
        if task.type == "upload" then
            local ec = get_easy_upload(task)
            if ec == nil then
                print("failed to add upload file task", task.uuid)
            else
                table.insert(state, ec)
                mtr:add(ec)
                print("added task to upload file to external system")
            end
        else
            print("worker received unknown task type")
        end
    end

    while true do
        if e_stop:isset() then break end
        local status, task = q_in:shift(os.time() + 1.0)
        if status then
            print("get task", task.uuid, task.type, task.delay)
            if type(task.delay) == "number" and task.delay ~= 0 then
                task.start_at = os.time() + task.delay
                table.insert(queue, task)
                print("added task " .. task.type .. " to the local queue")
            else
                process_task(task)
            end
        end

        for _=1,#queue do
            if os.time() > queue[1].start_at then
                process_task(table.remove(queue, 1))
            else
                break
            end
        end

        if #state ~= 0 and mtr:perform() == 0 then
            print("try to stop curl multi")
            local nstate = {}
            for i = 1, #state do
                local resp_code = state[i]:info("response_code")
                print("remove easy from state with code", resp_code)
                if resp_code == 0 then
                    local ec = state[i]:clone()
                    mtr:add(ec)
                    table.insert(nstate, ec)
                end
                state[i]:close()
            end
            state = nstate
            if #state ~= 0 then
                print("curl multi was reran")
            else
                print("curl multi was stopped")
            end
        end
    end
    print("worker main loop was exited")
    easy:close()
    mtr:close()
    print("worker was exited")
end

function CUploaderResp:worker_start()
    self:print("worker_start CUploaderResp")
    if self.w_rth == nil then
        self.w_rth = thread.new(
            worker,
            self.w_ctx,
            self.w_q_in,
            self.w_q_out,
            self.w_e_stop
        )
        if self.w_rth ~= nil then
            self:continue_incomplete()
        end
    end
    return self.w_rth ~= nil
end

function CUploaderResp:worker_stop()
    self:print("worker_stop CUploaderResp")
    if self.w_rth ~= nil and self.w_e_stop ~= nil then
        self.w_e_stop:set()
        self.w_rth:join()
        self.w_e_stop = nil
        self.w_rth = nil
    end
    if self.w_q_in ~= nil then
        self.w_q_in:free()
        self.w_q_in = nil
    end
    if self.w_q_out ~= nil then
        self.w_q_out:free()
        self.w_q_out = nil
    end
end

function CUploaderResp:get_file_hashs(filepath)
    self:print("get_file_hashs CUploaderResp by file path", filepath)
    local md5_digest, sha256_digest = md5.digest(), sha2.sha256_digest()
    local file = io.open(filepath, "rb")
    if not file then
        return "", ""
    end
    local read_num, content = 1024 * 1024 -- 1 MB as a chunk to read file
    while true do
        content = file:read(read_num)
        if content == nil then break end
        md5_digest(content)
        sha256_digest(content)
    end
    file:close()
    return glue.tohex(md5_digest()), glue.tohex(sha256_digest())
end

function CUploaderResp:map_columns(cols, rows)
    self:print("map_columns CUploaderResp")
    if #rows == 0 then
        return {}
    end

    local res = {}
    for _,r in ipairs(rows) do
        local row = {}
        for i,c in ipairs(cols) do
            row[c] = r[i]
        end
        table.insert(res, row)
    end

    return res
end

-- in: query, vargs (...)
--      variadic arguments to use it into bind_values
-- out: status (bool), err (string or nil)
function CUploaderResp:exec_query(query, ...)
    self:print("exec_query CUploaderResp")
    self.db:exec("BEGIN TRANSACTION;")
    local err
    local status, stmt = pcall(self.db.prepare, self.db, query)
    if not status then
        self:print("failed to prepare db exec query", tostring(stmt))
        self.db:exec("ROLLBACK;")
        return status, stmt
    end
    stmt:bind_values(...)
    status, err = pcall(stmt)
    if not status then
        self:print("failed to insert query into DB", err)
    end
    status, err = pcall(stmt.finalize, stmt)
    self.db:exec("COMMIT;")
    return status, err
end

-- in: query, vargs (...)
--      variadic arguments to use it into bind_values
-- out: table (array)
--      rows output where each row is a table (dict):
--      column name to data column value
--      * empty table otherways
function CUploaderResp:select_query(query, ...)
    self:print("select_query CUploaderResp")
    local args = glue.pack(...)
    local status, stmt = pcall(self.db.prepare, self.db, query)
    if not status then
        self:print("failed to prepare db select query", tostring(stmt))
        return {}
    end
    if #args > 0 then
        stmt:bind_values(...)
    end

    local rows, cols, step = {}, {}
    repeat
        status, step = pcall(stmt.step, stmt)
        if status and step then
            table.insert(rows, stmt:get_values())
        end
    until (not status or not step)
    if not status then
        self:print("failed to iterate by query results", tostring(step))
        return {}
    end

    for i=0,tonumber(stmt:columns())-1 do
        table.insert(cols, stmt:get_name(i))
    end
    pcall(stmt.finalize, stmt)

    return self:map_columns(cols, rows)
end

function CUploaderResp:make_uuid()
    self:print("make_uuid CUploaderResp")
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

function CUploaderResp:create_table()
    self:print("create_table CUploaderResp", self.tables.files)
    self.db:exec(self.queries.create_table)
end

function CUploaderResp:perform_migrations()
    self:print("perform_migrations CUploaderResp")
    self.db:exec([[
        CREATE TABLE IF NOT EXISTS migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            migration VARCHAR(100) UNIQUE,
            time DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))
        );
    ]])
    local status_migration = false
    local mgts = self:select_query("SELECT * FROM migrations;")
    local check_is_migration_exist = function(name)
        return glue.indexof(name, glue.map(mgts, "migration")) ~= nil
    end
    local db_exec = function(query)
        local status_pcall, status_exec, err = pcall(self.db.exec, self.db, query)
        if status_pcall == false then
            return false, status_exec
        end
        if status_exec == false then
            return false, err
        end
        return true
    end
    self:print("found migrations: ", cjson.encode(mgts))
    self.db:exec("BEGIN TRANSACTION;")
    for name, query in pairs(self.migrations) do
        local status, err
        if not check_is_migration_exist(name) then
            status, err = db_exec(query)
            if not status then
                self:print(string.format("failed to commit migration for '%s': %s", name, err))
                status_migration = false
                goto stop
            end
            status, err = db_exec("INSERT INTO migrations (migration) VALUES ('" .. name .. "');")
            if not status then
                self:print(string.format("failed to insert migration for '%s': %s", name, err))
                status_migration = false
                goto stop
            end
            status_migration = true
        end
    end
    ::stop::
    if status_migration then
        self.db:exec("COMMIT;")
    else
        self.db:exec("ROLLBACK;")
    end
end

function CUploaderResp:exec_put_file(uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid)
    self:print("exec_put_file CUploaderResp", uuid, filename, filesize, md5_hash, sha256_hash, aid, __gid)
    return self:exec_query(self.queries.put_file, uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid, __gid)
end

function CUploaderResp:exec_upload_file(uuid, code, resp)
    self:print("exec_upload_file CUploaderResp", uuid, code)
    return self:exec_query(self.queries.upload_file_resp, code, resp, uuid)
end

function CUploaderResp:get_file_info_by_uuid(uuid)
    self:print("get_file_info_by_uuid CUploaderResp", uuid)
    local file_info = self:select_query(self.queries.get_file_info_by_uuid, uuid)
    if #file_info == 0 then
        return {}
    end
    file_info = file_info[1]
    return file_info
end

function CUploaderResp:get_file_info_by_hash(md5_hash, sha256_hash)
    self:print("get_file_info_by_hash CUploaderResp", md5_hash, sha256_hash)
    return self:select_query(self.queries.get_file_info_by_hash, md5_hash, sha256_hash)
end

function CUploaderResp:check_duplicate_file_by_hash(md5_hash, sha256_hash)
    self:print("check_duplicate_file_by_hash CUploaderResp", md5_hash, sha256_hash)
    return #self:select_query(self.queries.check_duplicate_file_by_hash, md5_hash, sha256_hash) >= 1
end

function CUploaderResp:get_uploaded_files()
    self:print("get_uploaded_files CUploaderResp")
    return self:select_query(self.queries.get_uploaded_files)
end

function CUploaderResp:make_upload_file_msg(uuid, filename, local_path)
    self:print("make_upload_file_msg CUploaderResp", uuid, filename, local_path)
    return {
        ["uuid"] = uuid,
        ["type"] = "upload",
        ["path"] = local_path,
        ["name"] = filename,
    }
end

function CUploaderResp:continue_incomplete()
    self:print("continue_incomplete CUploaderResp")
    local files_to_upload = self:select_query(self.queries.get_incomplete_upload, __gid)
    for _, file in ipairs(files_to_upload) do
        if file.uuid and file.filename and file.local_path then
            self.w_q_in:push(self:make_upload_file_msg(file.uuid, file.filename, file.local_path))
        end
    end
end

function CUploaderResp:put_file(filename, local_path, aid)
    local uuid = self:make_uuid()
    local filesize = lfs.attributes(local_path, "size")
    if filesize == nil then
        self:print("local file not found by path", local_path)
        return false
    end
    local md5_hash, sha256_hash = self:get_file_hashs(local_path)
    self:print("put_file CUploaderResp", uuid, filename, md5_hash, sha256_hash, aid)
    if self:check_duplicate_file_by_hash(md5_hash, sha256_hash) then
        self:print("found duplicate file by hash into local DB")
        return true
    end
    local status, err = self:exec_put_file(uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid)
    if not status then
        self:print("failed to put file record to local DB", err)
        return false
    end
    if self.request_config.url == "" then
        self:print("external system url is not set so the record will store only to local DB")
        return true
    end
    if self.w_q_in == nil then
        self:print("failed to run file process, worker has already stopped")
        return false
    end
    self.w_q_in:push(self:make_upload_file_msg(uuid, filename, local_path))
    return true
end

function CUploaderResp:upload_file(uuid, filename, local_path, code, resp)
    self:print("upload_file CUploaderResp", uuid, filename, local_path, code)
    local status, err = self:exec_upload_file(uuid, code, resp)
    if not status then
        self:print("failed to update (upload) file record in local DB", err)
        return false
    end
    if self.w_q_in == nil then
        self:print("failed to run file process, worker has already stopped")
        return false
    end
    return true
end

function CUploaderResp:process()
    local results = {}
    local status, resp
    repeat
        status, resp = self.w_q_out:shift(os.time() + 0.1)
        if status then
            self:print("got response from worker", resp.uuid, resp.type, resp.name, resp.path, resp.result)
            if type(resp.error) == "string" then
                self:print("failed to process http response from uploader: ", cjson.encode(resp))
            elseif resp.type == "upload" then
                self:upload_file(resp.uuid, resp.name, resp.path, resp.code, resp.result)
            end
        end
    until not status
    return results
end
