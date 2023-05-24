require("strict")
require("yaci")
local glue = require("glue")

CDatabaseEngine = newclass("CDatabaseEngine")

function CDatabaseEngine:init(db)
    self.db = assert(db)
    self.queries = {}

    --

    self.queries.create_table_tasks = [[
        CREATE TABLE IF NOT EXISTS tasks (
            task_id TEXT PRIMARY KEY, -- GUID
            task_type INTEGER NOT NULL, -- 1: custom_proc, 2: custom_fs, 3: fast_proc, 4: fast_fs, 5 full_proc, 6: full_fs
            objects_type INTEGER NOT NULL, -- 1: proc, 2: fs
            custom_rules TEXT
        );
    ]]

    self.queries.create_table_task_status = [[
        CREATE TABLE IF NOT EXISTS task_status (
            task_id TEXT,
            status INTEGER NOT NULL,
            time_start TEXT NOT NULL,
            time_end TEXT,
            objects INTEGER NOT NULL,
            error TEXT, -- error of setting task, not of scanning elements
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    self.queries.create_table_task_params_proc = [[
        CREATE TABLE IF NOT EXISTS task_params_proc (
            task_id TEXT,
            proc_id INTEGER,
            proc_image TEXT,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    self.queries.create_table_task_params_fs = [[
        CREATE TABLE IF NOT EXISTS task_params_fs (
            task_id TEXT,
            filepath TEXT,
            recursive INTEGER,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    self.queries.create_table_task_result_process = [[
        CREATE TABLE IF NOT EXISTS task_result_process (
            task_id TEXT,
            object_id INTEGER NOT NULL, -- task_results->objects
            proc_id INTEGER,
            proc_image TEXT,
            error TEXT,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    self.queries.create_table_task_result_file = [[
        CREATE TABLE IF NOT EXISTS task_result_file (
            task_id TEXT,
            object_id INTEGER NOT NULL, -- task_results->objects
            filepath TEXT,
            sha256 TEXT,
            error TEXT,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    self.queries.create_table_task_detects = [[
        CREATE TABLE IF NOT EXISTS task_detects (
            task_id TEXT,
            object_id INTEGER NOT NULL,
            rule_id TEXT,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id)
        );
    ]]

    -- meta of actual and old rules
    self.queries.create_table_rules = [[
        CREATE TABLE IF NOT EXISTS rules (
            active INTEGER NOT NULL,
            rule_id TEXT PRIMARY KEY,
            rule_name TEXT NOT NULL,
            malware_class TEXT NOT NULL,
            malware_family TEXT NOT NULL,
            rule_severity TEXT NOT NULL,
            rule_type TEXT NOT NULL,
            is_silent INTEGER NOT NULL,
            description TEXT NOT NULL,
            date TEXT NOT NULL,
            hash TEXT NOT NULL,
            reference TEXT NOT NULL,
            rule_precision INTEGER NOT NULL
        );
    ]]

    self.queries.add_rule = [[
        REPLACE INTO rules VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ]]

    self.queries.add_task = [[
        INSERT INTO tasks VALUES(?, ?, ?, ?);
    ]]

    self.queries.get_task = [[
        SELECT task_id,task_type,objects_type,custom_rules
        FROM tasks
        WHERE task_id LIKE ?
    ]]

    self.queries.add_task_status = [[
        INSERT INTO task_status VALUES(?, ?, ?, ?, ?, ?);
    ]]

    self.queries.update_task_status_add_object = [[
        UPDATE task_status SET objects = ? WHERE task_id = ?
    ]]

    self.queries.get_task_status_objects = [[
        SELECT objects
        FROM task_status
        WHERE task_id == ?
    ]]

    self.queries.get_task_status_status = [[
        SELECT status
        FROM task_status
        WHERE task_id == ?
    ]]

    self.queries.update_task_status_done = [[
        UPDATE task_status SET status = ?, time_end = ?, error = ? WHERE task_id = ?
    ]]

    self.queries.add_task_params_proc = [[
        INSERT INTO task_params_proc VALUES(?, ?, ?);
    ]]

    self.queries.add_task_params_fs = [[
        INSERT INTO task_params_fs VALUES(?, ?, ?);
    ]]

    self.queries.add_task_result_process = [[
        INSERT INTO task_result_process VALUES(?, ?, ?, ?, ?);
    ]]

    self.queries.add_task_result_file = [[
        INSERT INTO task_result_file VALUES(?, ?, ?, ?, ?);
    ]]

    self.queries.add_task_detect = [[
        INSERT INTO task_detects VALUES(?, ?, ?);
    ]]

    self.queries.get_rule_meta = [[
        SELECT *
        FROM rules
        WHERE rule_id == ?
    ]]

    -- cache queries

    -- file cache
    self.queries.create_table_file_cache = [[
        CREATE TABLE IF NOT EXISTS file_cache (
            filepath TEXT,
            sha256 TEXT,
            scan_results TEXT
        );
    ]]

    self.queries.create_index_for_file_cache = [[
        CREATE INDEX IF NOT EXISTS file_cache_index ON file_cache (filepath, sha256);
    ]]

    self.queries.add_to_file_cache = [[
        INSERT INTO file_cache VALUES(?, ?, ?, ?);
    ]]

    -- process cache
    self.queries.create_table_process_cache = [[
        CREATE TABLE IF NOT EXISTS process_cache (
            process_id INTEGER,
            process_image TEXT,
            last_scan_time DOUBLE,
            scan_results TEXT
        );
    ]]

    self.queries.create_index_for_process_cache = [[
        CREATE INDEX IF NOT EXISTS process_cache_index ON process_cache (process_id, process_image);
    ]]

    self.queries.add_to_process_cache = [[
        INSERT INTO process_cache VALUES(?, ?, ?, ?);
    ]]

    self.queries.get_from_process_cache = [[
        SELECT scan_results, last_scan_time
        FROM process_cache
        WHERE process_id == ? AND process_image == ?
    ]]

    -- test query
    self.queries.get_all_from_process_cache = [[
        SELECT *
        FROM process_cache
    ]]

    self.queries.delete_from_process_cache = [[
        DELETE
        FROM process_cache
        WHERE process_id == ? AND process_image == ?
    ]]

    self.queries.delete_all_from_process_cache = [[
        DELETE
        FROM process_cache
    ]]
end

function CDatabaseEngine:free()
    __log.debug("finalize CDatabaseEngine object")
end

function CDatabaseEngine:create_tables()
    __log.debug("CDatabaseEngine:create_tables")

    self:exec_query(self.queries.create_table_rules)
    self:exec_query(self.queries.create_table_tasks)
    self:exec_query(self.queries.create_table_task_status)
    self:exec_query(self.queries.create_table_task_params_proc)
    self:exec_query(self.queries.create_table_task_params_fs)
    self:exec_query(self.queries.create_table_task_result_process)
    self:exec_query(self.queries.create_table_task_result_file)
    self:exec_query(self.queries.create_table_task_detects)
    self:exec_query(self.queries.create_table_file_cache)
    self:exec_query(self.queries.create_index_for_file_cache)
    self:exec_query(self.queries.create_table_process_cache)
    self:exec_query(self.queries.create_index_for_process_cache)
end

-- from json
function CDatabaseEngine:add_rule(rule_id, rule_meta)
    assert(type(rule_id) == "string", "rule_id must be a value of string type")
    assert(type(rule_meta) == "table", "rule_meta must be a value of table type")
    assert(type(rule_meta["rule_name"]) == "string", "rule_name must be a value of string type")
    assert(type(rule_meta["malware_class"]) == "string", "malware_class must be a value of string type")
    assert(type(rule_meta["malware_family"]) == "string", "malware_family must be a value of string type")
    assert(type(rule_meta["rule_severity"]) == "string", "rule_severity must be a value of string type")
    assert(type(rule_meta["rule_type"]) == "string", "rule_type must be a value of string type")
    assert(type(rule_meta["is_silent"]) == "boolean", "is_silent must be a value of string type")
    assert(type(rule_meta["description"]) == "string", "description must be a value of string type")
    assert(type(rule_meta["date"]) == "string", "date must be a value of string type")
    assert(type(rule_meta["hash"]) == "table", "hash must be a value of table type")
    assert(type(rule_meta["reference"]) == "table", "reference must be a value of table type")
    assert(type(rule_meta["rule_precision"]) == "number", "rule_precision must be a value of number type")

    return self:exec_query(self.queries.add_rule,
        1,
        rule_id,
        rule_meta["rule_name"],
        rule_meta["malware_class"],
        rule_meta["malware_family"],
        rule_meta["rule_severity"],
        rule_meta["rule_type"],
        rule_meta["is_silent"],
        rule_meta["description"],
        rule_meta["date"],
        table.concat(rule_meta["hash"], "|"),
        table.concat(rule_meta["reference"], "|"),
        rule_meta["rule_precision"])
end

function CDatabaseEngine:get_task(task_id)
    assert(type(task_id) == "string", "task_id must be a value of string type")

    local query = self:select_query_unpack_single(self.queries.get_task, task_id)
    if not query then
        __log.debug("CDatabaseEngine:get_task, empty query results")
        return nil
    end

    local res = {
        task_id = query["task_id"],
        task_type = query["task_type"],
        objects_type = query["objects_type"],
        custom_rules = query["custom_rules"],
    }

    return res
end

function CDatabaseEngine:update_rules(active_rules)
    __log.debug("CDatabaseEngine:update_rules")
    assert(type(active_rules) == "table", "active_rules must be a value of table type")

    local current_rules = self:select_query("SELECT rule_id,active FROM rules")
    if not current_rules then
        __log.debug("CDatabaseEngine:get_task, empty query results")
        return nil
    end

    local active_rules_in_db = {}

    for _, rule in ipairs(current_rules) do
        if active_rules[rule.rule_id] ~= nil then
            active_rules_in_db[rule.rule_id] = true;
            if rule.active == 0 then
                __log.debugf("mark rule as active, rule_id = %s", rule.rule_id)
                self:exec_query("UPDATE rules SET active = 1 WHERE rule_id = ?", rule.rule_id)
            end
        else
            local detects = self:select_query_unpack_single([[
                SELECT COUNT(*)
                FROM tasks A,
                     task_detects B
                WHERE A.task_id == B.task_id
                  AND A.custom_rules IS NULL
                  AND B.rule_id = ?
            ]], rule.rule_id)

            if not detects or detects["COUNT(*)"] == 0 then
                __log.debugf("delete rule, rule_id = %s", rule.rule_id)
                self:exec_query("DELETE FROM rules WHERE rule_id = ?", rule.rule_id)
            else
                if rule.active == 1 then
                    __log.debugf("mark rule as inactive, rule_id = %s", rule.rule_id)
                    self:exec_query("UPDATE rules SET active = 0 WHERE rule_id = ?", rule.rule_id)
                end
            end
        end
    end

    for rule_id, rule_meta in pairs(active_rules) do
        if active_rules_in_db[rule_id] == nil then
            self:add_rule(rule_id, rule_meta)
        end
    end
end

function CDatabaseEngine:add_task_proc(task_id, proc_id, proc_image, task_type, rules)
    __log.debug("CDatabaseEngine:add_task_proc")
    assert(type(task_id) == "string", "task_id must be a value of string type")
    assert(type(proc_id) == "nil" or type(proc_id) == "number", "proc_id must be a value of nil or number type")
    assert(type(proc_image) == "nil" or type(proc_image) == "string", "proc_image must be a value of nil or string type")
    assert(type(task_type) == "number", "task_type must be a value of number type")
    assert(type(rules) == "nil" or type(rules) == "string", "rules must be a value of nil or string type")

    local res = self:exec_query(self.queries.add_task, task_id, task_type, 1, rules)
    if not res then
        return res
    end

    res = self:exec_query(self.queries.add_task_params_proc, task_id, proc_id, proc_image)
    if not res then
        return res
    end

    return self:exec_query(self.queries.add_task_status,
        task_id,
        0,
        os.date("!%Y-%m-%dT%H:%M:%SZ", os.time()), -- GMT
        nil,
        0,
        nil)
end

function CDatabaseEngine:add_task_fs(task_id, filepath, recursive, task_type, rules)
    __log.debug("CDatabaseEngine:add_task_fs")
    assert(type(task_id) == "string", "task_id must be a value of string type")
    assert(type(filepath) == "nil" or type(filepath) == "string", "filepath must be a value of nil or string type")
    assert(type(recursive) == "nil" or type(recursive) == "boolean", "recursive must be a value of nil or boolean type")
    assert(type(task_type) == "number", "task_type must be a value of number type")
    assert(type(rules) == "nil" or type(rules) == "string", "rules must be a value of nil or string type")

    local res = self:exec_query(self.queries.add_task, task_id, task_type, 2, rules)
    if not res then
        return res
    end

    res = self:exec_query(self.queries.add_task_params_fs, task_id, filepath, recursive)
    if not res then
        return res
    end

    return self:exec_query(self.queries.add_task_status,
        task_id,
        0,
        os.date("!%Y-%m-%dT%H:%M:%SZ", os.time()), -- GMT
        nil,
        0,
        nil)
end

function CDatabaseEngine:add_task_result(task_id, status, time_end, err)
    __log.debug("CDatabaseEngine:add_task_result")
    assert(type(task_id) == "string", "task_id must be a value of string type")
    assert(type(status) == "number", "status must be a value of number type")
    assert(type(time_end) == "nil" or type(time_end) == "string", "time_end must be a value of nil or string type")
    assert(type(err) == "nil" or type(err) == "string", "err must be a value of nil or string type")

    local query = self:select_query_unpack_single(self.queries.get_task_status_status, task_id)
    if not query then
        return nil
    end

    if query["status"] ~= 0 then -- specific status is set
        return nil
    end

    return self:exec_query(self.queries.update_task_status_done, status, time_end, err, task_id)
end

function CDatabaseEngine:add_task_result_process(task_id, proc_id, proc_image, err, detects)
    __log.debug("CDatabaseEngine:add_task_result_process")
    assert(type(task_id) == "string", "task_id must be a value of string type")
    assert(type(proc_id) == "nil" or type(proc_id) == "number", "proc_id must be a value of nil or string type")
    assert(type(proc_image) == "nil" or type(proc_image) == "string", "proc_image must be a value of nil or string type")
    assert(type(err) == "nil" or type(err) == "string", "err must be a value of nil or string type")
    assert(type(detects) == "nil" or type(detects) == "table", "detects must be a value of nil or table type")

    local query = self:select_query_unpack_single(self.queries.get_task_status_objects, task_id)
    if not query then
        return nil
    end

    local object = query["objects"]

    local res = self:exec_query(self.queries.update_task_status_add_object, object + 1, task_id)
    if not res then
        return res
    end

    res = self:exec_query(self.queries.add_task_result_process, task_id, object, proc_id, proc_image, err)
    if not res then
        return res
    end

    if detects ~= nil then
        for _, rule in ipairs(detects) do
            res = self:exec_query(self.queries.add_task_detect, task_id, object, rule.rule_id)

            if not res then
                return res
            end
        end
    end

    return true
end

function CDatabaseEngine:add_task_result_file(task_id, filepath, sha256, err, detects)
    __log.debug("CDatabaseEngine:add_task_result_file")
    assert(type(task_id) == "string", "task_id must be a value of string type")
    assert(type(filepath) == "nil" or type(filepath) == "string", "filepath must be a value of nil or string type")
    assert(type(sha256) == "nil" or type(sha256) == "string", "sha256 must be a value of nil or string type")
    assert(type(err) == "nil" or type(err) == "string", "err must be a value of nil or string type")
    assert(type(detects) == "nil" or type(detects) == "table", "detects must be a value of nil or table type")

    local query = self:select_query_unpack_single(self.queries.get_task_status_objects, task_id)
    if not query then
        return nil
    end

    local object = query["objects"]

    local res = self:exec_query(self.queries.update_task_status_add_object, object + 1, task_id)
    if not res then
        return res
    end

    res = self:exec_query(self.queries.add_task_result_file, task_id, object, filepath, sha256, err)
    if not res then
        return res
    end

    if detects ~= nil then
        for _, rule in ipairs(detects) do
            res = self:exec_query(self.queries.add_task_detect, task_id, object, rule.rule_id)
            if not res then
                return res
            end
        end
    end

    return true
end

-- execute cache queries

function CDatabaseEngine:add_to_process_cache(process_id, process_image, last_scan_time, scan_results)
    __log.info("CDatabaseEngine:add_to_process_cache")

    assert(process_id and type(process_id) == "number", "invalid process_id parameter")
    assert(process_image and type(process_image) == "string", "invalid process_image parameter")
    assert(last_scan_time and type(last_scan_time) == "number", "invalid last_scan_time parameter")
    assert(scan_results and type(scan_results) == "string", "invalid scan_results parameter")

    return self:exec_query(self.queries.add_to_process_cache, process_id, process_image, last_scan_time, scan_results)
end

function CDatabaseEngine:get_from_process_cache(process_id, process_image)
    __log.info("CDatabaseEngine:get_from_process_cache")

    assert(type(process_id) == "number", "process_id must be a value of number type")
    assert(type(process_image) == "string", "process_image must be a value of number type")

    local results = self:select_query_unpack_single(self.queries.get_from_process_cache, process_id, process_image)
    if not results then
        __log.info("CDatabaseEngine:get_scan_results_from_cache ~ empty query results")
        return nil
    end
    return results
end

function CDatabaseEngine:get_all_from_process_cache()
    __log.info("CDatabaseEngine:get_all_from_process_cache")

    local results = self:select_query(self.queries.get_all_from_process_cache)
    if not results then
        __log.info("CDatabaseEngine:get_all_from_process_cache ~ empty query results")
        return nil
    end
    return results
end

function CDatabaseEngine:delete_from_process_cache(process_id, process_image)
    __log.info("CDatabaseEngine:delete_from_process_cache")

    assert(type(process_id) == "number", "process_id must be a value of number type")
    assert(type(process_image) == "string", "process_image must be a value of number type")

    -- TODO? self:delete_query(<>)
    self:select_query_unpack_single(self.queries.delete_from_process_cache, process_id, process_image)
end

function CDatabaseEngine:clear_process_cache()
    __log.info("CDatabaseEngine:clear_process_cache")

    self:exec_query(self.queries.delete_all_from_process_cache)
end

function CDatabaseEngine:get_rule_meta(rule_id)
    __log.debug("CDatabaseEngine:get_rule_meta")
    assert(type(rule_id) == "string", "rule_id must be a value of string type")

    local query = self:select_query_unpack_single(self.queries.get_rule_meta, rule_id)
    if not query then
        __log.debug("CDatabaseEngine:get_rule_meta, empty query results")
        return nil
    end

    local res = {
        rule_name = query["rule_name"],
        malware_class = query["malware_class"],
        malware_family = query["malware_family"],
        rule_severity = query["rule_severity"],
        rule_type = query["rule_type"],
        is_silent = query["is_silent"] == 1,
        description = query["description"],
        date = query["date"],
        hash = glue.gsplit(query["hash"], "|"),
        reference = glue.gsplit(query["reference"], "|"),
        rule_precision = query["rule_precision"],
    }

    return res
end

local function compose_filter(filters)
    if filters == nil or #filters == 0 then
        return ""
    end

    local str = ""

    for i, filter in ipairs(filters) do
        if filter.value == "" then
            goto continue
        end

        if type(filter.value) == "string" then
            str = str .. filter.field .. " LIKE \"%" .. filter.value .. "%\""
        else
            str = str .. filter.field .. " == " .. filter.value
        end

        if i ~= #filters then
            str = str .. " AND "
        end
        ::continue::
    end

    if str ~= "" then
        str = " WHERE " .. str
    end

    return str
end

local function compose_order_and_limit(page, page_size, sort)
    local str = ""

    if sort ~= nil and sort.prop ~= nil and sort.order ~= nil then
        str = str .. " ORDER BY " .. sort.prop .. (sort.order == "ascending" and " ASC" or " DESC")
    end

    if page ~= nil and page_size ~= nil then
        str = str .. " LIMIT " .. page_size .. " OFFSET " .. (page - 1) * page_size
    end

    return str
end

--

function CDatabaseEngine:db_request(request_type, page, page_size, sort, filters, request_params)
    local res = {}
    --local query

    local filters_str = compose_filter(filters)
    local order_and_limit_str = compose_order_and_limit(page, page_size, sort)

    if request_type == "db_req_active_rules" then
        if filters_str == "" then
            filters_str = " WHERE active = 1"
        else
            filters_str = filters_str .. " AND active = 1"
        end

        local main_part = "FROM rules" .. filters_str

        local select = self:select_query_unpack_single("SELECT COUNT(*) " .. main_part)
        if select == nil then
            res.error = "unable to get count of items"
            return res
        end

        res.total = select["COUNT(*)"]

        res.rules = self:select_query("SELECT * " .. main_part .. order_and_limit_str)
        if not res.rules then
            res.error = "unable to get items"
            res.total = nil
            return res
        end
    elseif request_type == "db_req_tasks" then
        if filters_str == "" then
            filters_str = " WHERE A.task_id == B.task_id"
        else
            filters_str = filters_str .. " AND A.task_id == B.task_id"
        end

        local select = self:select_query_unpack_single("SELECT COUNT(*) FROM tasks A,task_status B" .. filters_str)
        if select == nil then
            res.error = "unable to get count of items"
            return res
        end

        res.total = select["COUNT(*)"]

        res.tasks = self:select_query([[
            SELECT A.task_id,
                   A.task_type,
                   A.objects_type,
                   A.custom_rules,
                   B.status,
                   B.time_start,
                   B.time_end,
                   B.objects,
                   B.error,
                   COUNT(C.task_id) as detects
            FROM tasks A
            INNER JOIN task_status B ON A.task_id = B.task_id
            LEFT JOIN task_detects C ON A.task_id = C.task_id
        ]] .. filters_str .. [[
            GROUP BY A.task_id
        ]] .. order_and_limit_str)

        if not res.tasks then
            res.error = "unable to get items"
            res.total = nil
            return res
        end

        for _, task in ipairs(res.tasks) do
            if task.task_type == 1 then -- CUSTOM_PROC = 1
                task.task_params = self:select_query_unpack_single(
                    "SELECT proc_id,proc_image FROM task_params_proc WHERE task_id = ?", task.task_id)
            elseif task.task_type == 2 then -- CUSTOM_FS = 2
                task.task_params = self:select_query_unpack_single(
                    "SELECT filepath,recursive FROM task_params_fs WHERE task_id = ?", task.task_id)
                task.task_params.recursive = task.task_params.recursive == 1
            end
        end
    elseif request_type == "db_req_task_detects" then
        local task_info = self:select_query_unpack_single(self.queries.get_task, request_params.task_id)
        if task_info == nil then
            res.error = "unable to get task info"
            return res
        end

        if filters_str == "" then
            filters_str = " WHERE A.task_id = ?"
        else
            filters_str = filters_str .. " AND A.task_id = ?"
        end

        local item_params
        local items_table
        if task_info.objects_type == 1 then
            item_params = " A.proc_image,A.proc_id,"
            items_table = " task_result_process A,"
        else
            item_params = " A.filepath,A.sha256,"
            items_table = " task_result_file A,"
        end

        local rule_params
        local main_part

        if task_info.custom_rules == nil then
            rule_params = "C.rule_name,C.malware_class,C.rule_precision"
            main_part = [[
                FROM
            ]] .. items_table .. [[
                task_detects B,rules C
            ]] .. filters_str .. [[
                AND B.rule_id = C.rule_id
                AND A.task_id = B.task_id
                AND A.object_id = B.object_id
            ]]
        else
            rule_params = "B.rule_id as rule_name"
            main_part = [[
                FROM
            ]] .. items_table .. [[
                task_detects B
            ]] .. filters_str .. [[
                AND A.task_id = B.task_id
                AND A.object_id = B.object_id
            ]]
        end

        local select = self:select_query_unpack_single("SELECT COUNT(*) " .. main_part, request_params.task_id)
        if select == nil then
            res.error = "unable to get count of items"
            return res
        end

        res.total = select["COUNT(*)"]

        res.detects = self:select_query("SELECT" .. item_params .. rule_params .. main_part .. order_and_limit_str, request_params.task_id)
        if not res.detects then
            res.error = "unable to get items"
            res.total = nil
            return res
        end
    else
        return nil
    end

    return res
end

--

-- in: table, table
--      columns list in table variable type
--      rows list in table variable type and each row is a table
-- out: table
--      result of mapping columns to rows and making nested tables
function CDatabaseEngine:map_columns(cols, rows)
    assert(type(cols) == "table", "missing columns list")
    assert(type(rows) == "table", "missing rows list")

    if #rows == 0 then
        return {}
    end

    return glue.map(rows, function (tk, row)
        row = row or tk or {}
        local rrow = {}
        for i, col in ipairs(cols) do
            rrow[col] = row[i]
        end
        return rrow
    end)
end

-- in: string, vargs (...)
--      string as SQL query to exec
--      variadic arguments to use it into bind_values
-- out: boolean, string or nil
--      boolean as result of execute query
--      string as error result when execution was failed
function CDatabaseEngine:exec_query(query, ...)
    assert(type(query) == "string", "missing query string to exec it")

    local err
    local status, stmt = pcall(self.db.prepare, self.db, query)
    if not status then
        __log.errorf("failed to prepare db exec query, %s", tostring(stmt))
        return status, stmt
    end
    if select("#", ...) > 0 then
        stmt:bind_values(...)
    end
    status, err = pcall(stmt)
    if not status then
        __log.errorf("failed to insert query into DB, %s", err)
    end
    status, err = pcall(stmt.finalize, stmt)
    return status, err
end

-- in: string, vargs (...)
--      string as SQL query to select data
--      variadic arguments to use it into bind_values
-- out: table (array)
--      rows output where each row is a table (dict):
--      column name to data column value
--      * empty table otherways
function CDatabaseEngine:select_query(query, ...)
    assert(type(query) == "string", "missing query string to select it")

    local status, stmt = pcall(self.db.prepare, self.db, query)
    if not status then
        local error = tostring(stmt)
        __log.errorf("failed to prepare db query: %s", error)
        return { error = error }
    end
    if select("#", ...) > 0 then
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
        __log.errorf("failed to iterate by query results, step: %s", tostring(step))
        return {}
    end

    for i = 0, tonumber(stmt:columns()) - 1 do
        table.insert(cols, stmt:get_name(i))
    end
    pcall(stmt.finalize, stmt)

    return self:map_columns(cols, rows)
end

function CDatabaseEngine:select_query_unpack_single(query, ...)
    local res = self:select_query(query, ...)
    return res and res[1] or nil
end
