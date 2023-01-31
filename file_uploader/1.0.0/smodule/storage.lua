require("queries")
require("migrations")
local sqlite  = require("lsqlite3")
local luapath = require("path")
local lfs     = require("lfs")
local glue   = require("glue")
local pp     = require("pp")
local cjson  = require("cjson.safe")

-- uploader variables
local db_file_name = "fu_" .. __gid .."_v2.db"
local path_to_db = luapath.normalize(luapath.combine(luapath.combine(lfs.currentdir(), "data"), db_file_name))

FileUploaderStorage = {
    tables = {
        files = "files",
        file_action = "file_action"
    },
    fields = {
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
        group_id = "CHAR(32)"
    },
    tables_fields = {
        file_action_fields = {
            file_id = "INT",
            action = "CHAR(32)",
            time = "DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))",
            upload_response = "TEXT",
            upload_code = "INT",
            result = "CHAR(16)"
        },
    },
    set_action_fields = {
        "action",
        "filepath",
    },
    put_file_fields = {
        "uuid",
        "filename",
        "filesize",
        "md5_hash",
        "sha256_hash",
        "local_path",
        "agent_id",
        "group_id",
    },
    file_info_fields = {
        "id",
        "uuid",
        "filename",
        "filesize",
        "md5_hash",
        "sha256_hash",
        "time",
    }
}

function GetDB()
    local fu_db = sqlite.open(path_to_db, "create")
    if fu_db ~= nil then
        -- add __gc to close database on exit module
        local prox = newproxy(true)
        getmetatable(prox).__gc = function() if fu_db then fu_db:close() end end
        fu_db[prox] = true

        return fu_db
    else
        __log.error("failled to open uploader cache database")
    end
    return nil
end

FileUploaderStorage.__index = FileUploaderStorage

function NewFileUploaderStorage()
    local fuStorage = {}
    setmetatable(fuStorage, FileUploaderStorage)
    fuStorage.db = assert(GetDB()) or ""
    fuStorage.is_debug = true
    fuStorage.migrations = newMigrations(fuStorage.tables, fuStorage.tables_fields)
    fuStorage.queries = newQueries()

    return fuStorage
end

function FileUploaderStorage:FilesToUpload()
    return self:select_query(
        self.queries:get_incomplete_upload(), __gid, "wait"
    )
end

function FileUploaderStorage:UpdateFileActionStatus(status, id)
    return self:exec_query(
        self.queries:update_file_action_status(self.tables.file_action), status, id
    )
end

function FileUploaderStorage:GetFilesFromFilename(filename)
    self:print("exec_get_files_from_filename CUploaderResp", filename)
    return self:select_query(
        self.queries:get_file_from_filename(self.tables.files, self.put_file_fields),
        filename
    )
end

function FileUploaderStorage:GetFileForUpload(filename, md5_hash, sha256_hash)
    self:print("exec_get_file_for_upload CUploaderResp", filename, md5_hash, sha256_hash)
    local file_info = self:select_query(
        self.queries:get_file_for_upload(self.tables.files),
        filename, md5_hash, sha256_hash
    )
    if #file_info == 0 then
        return {}
    end
    file_info = file_info[1]
    return file_info
end

function FileUploaderStorage:SetAction(filepath, actionName)
    self:print("exec_set_action CUploaderResp", filepath, actionName)
    return self:exec_query(
        self.queries:setAction(self.tables.file_action, self.set_action_fields),
        actionName, filepath
    )
end

function FileUploaderStorage:ExecPutFile(uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid)
    self:print("exec_put_file CUploaderResp", uuid, filename, filesize, md5_hash, sha256_hash, aid, __gid)
    return self:exec_query(
        self.queries:put_file(self.tables.files, self.put_file_fields),
        uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid, __gid
    )
end

function FileUploaderStorage:ExecUploadFile(uuid, code, resp, result, place)
    self:print("exec_upload_file CUploaderResp", uuid, code, result)
    local file = self.GetFileInfoByUUID(self, uuid)

    return self:exec_query(
        self.queries:upload_file_resp(self.tables.file_action),
        code, resp, result, place, file.id, "process", "wait"
    )
end

function FileUploaderStorage:SetNewFileOperation(id, action_name)
    return self:exec_query(
        self.queries:set_file_action(self.tables.file_action), id,
        action_name, "process"
    )
end

function FileUploaderStorage:GetFileInfoByUUID(uuid)
    self:print("get_file_info_by_uuid CUploaderResp", uuid)
    local file_info = self:select_query(
        self.queries:get_file_info_by_uuid(self.tables.files, self.file_info_fields),
        uuid
    )
    if #file_info == 0 then
        return {}
    end
    file_info = file_info[1]
    return file_info
end

function FileUploaderStorage:GetFileInfoByHash(md5_hash, sha256_hash)
    self:print("get_file_info_by_hash CUploaderResp", md5_hash, sha256_hash)
    local file_info = self:select_query(
        self.queries:get_file_info_by_hash(self.tables.files),
        md5_hash, sha256_hash
    )

    if #file_info == 0 then
        return {}
    end
    file_info = file_info[1]
    return file_info
end

function FileUploaderStorage:CheckDuplicateFileByHash(md5_hash, sha256_hash)
    self:print("check_duplicate_file_by_hash CUploaderResp", md5_hash, sha256_hash)
    return #self:select_query(
        self.queries:check_duplicate_file_by_hash(self.tables.files),
        md5_hash, sha256_hash
    ) >= 1
end

function FileUploaderStorage:GetUploadedFiles()
    self:print("get_uploaded_files CUploaderResp")
    return self:select_query(self.queries:get_uploaded_files(
        self.tables.files, self.file_info_fields
    ))
end

function FileUploaderStorage:print(...)
    if self.is_debug then
        local t = glue.pack(...)
        for i, v in ipairs(t) do
            t[i] = pp.format(v)
        end
        print(glue.unpack(t))
    end
end

function FileUploaderStorage:CreateTable()
    self:print("create_table FileUploaderStorage", self.tables.files)
    self.db:exec(self.queries:create_table(self.tables.files, self.fields))
end

function FileUploaderStorage:Migrate()
    self:print("perform_migrations CUploaderResp")
    self.db:exec([[
        CREATE TABLE IF NOT EXISTS migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            migration VARCHAR(100) UNIQUE,
            time DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))
        );
    ]])
    local status_migration = false
    local mgts = self:select_query("SELECT * FROM migrations;") -- вот здесь рассмотреть
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
    local migrations = self.migrations:get_migrations()
    for name, query in pairs(migrations) do
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

-- in: query, vargs (...)
--      variadic arguments to use it into bind_values
-- out: table (array)
--      rows output where each row is a table (dict):
--      column name to data column value
--      * empty table otherways
function FileUploaderStorage:select_query(query, ...)
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

function FileUploaderStorage:map_columns(cols, rows)
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
function FileUploaderStorage:exec_query(query, ...)
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

-- execute SQL quesry in local SQLite DB
function exec_query(src, query, db)
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
