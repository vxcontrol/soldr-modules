require("yaci")
require("strict")
local glue  = require("glue")
local cjson = require("cjson.safe")

require("engines.base_engine")
require("engines.db_engine")

CActsEngine = newclass("CActsEngine", CBaseEngine)

-- yara context

local thread = require("thread")
local uuid = require("uuid2")
uuid.seed()

require("yara_cmodule")

local scan_tag = {
    FILE = 4294967294,
    MEM = 4294967295
}

local scan_type = {
    CUSTOM_PROC = 1,
    CUSTOM_FS = 2,
    FAST_PROC = 3,
    FAST_FS = 4,
    FULL_PROC = 5,
    FULL_FS = 6,
}

local task_status = {
    IN_PROGRESS = 0,
    COMPLETED = 1,
    ERROR = 2,
    CANCELED = 3,
    INTERRUPTED = 4,
}

--

--[[
    cfg top keys:
    * config - module arguments (hard limits)
    * db - general database handle
    * rules_meta_files - ...
    * rules_meta_mem - ...
]]
function CActsEngine:init(cfg)
    __log.debug("init CActsEngine object")
    assert(type(cfg) == "table", "configuration object has invalid type")
    assert(type(cfg.db) ~= "nil", "db has invalid type")

    self.db_engine = CDatabaseEngine(cfg.db)
    self.db_engine:create_tables()

    do
        local active_rules = {}

        for rule_id,rule_meta in pairs(cfg.rules_meta_files) do
            active_rules[rule_id] = rule_meta
        end

        for rule_id,rule_meta in pairs(cfg.rules_meta_mem) do
            active_rules[rule_id] = rule_meta
        end

        self.db_engine:update_rules(active_rules)
    end

    cfg.engine = "acts_engine"
    self.super:init(cfg)

    -- initialization of object after base class constructing

    self.config_suffix = cfg.config_suffix
    self:update_config_cb()

    self:yara_update_interrupted_tasks()
    assert(self:yara_init(cfg))

    -- cleanup

    cfg.rules_meta_files = nil
    cfg.rules_meta_mem = nil
    cfg.rules_files = nil
    cfg.rules_mem = nil
end

-- in: nil
-- out: nil
function CActsEngine:free()
    __log.debug("finalize CActsEngine object")

    -- here will be triggered after closing vxproto object (destructor of the state)
end

-- in: nil
-- out: number
--      amount of milliseconds timeout to wait next call of the timer_cb
function CActsEngine:timer_cb()
    -- __log.debug("timer_cb CActsEngine")

    local acts_engine = CActsEngine:cast(self)
    local db_engine = acts_engine.db_engine

    while acts_engine.yara_ctx.q_res:length() ~= 0 do

        local _,res = acts_engine.yara_ctx.q_res:shift(0)

        local task_id = acts_engine.yara_ctx.task_ids[res.task_id]

        if res.data == nil then -- task complete

            acts_engine.yara_ctx.task_ids[res.task_id] = nil
            local workers = acts_engine.yara_ctx.task_ctx[task_id].workers

            if workers == 1 then

                db_engine:add_task_result(task_id, res.err and task_status.ERROR or task_status.COMPLETED, res.time_end, res.err)

                local tag = acts_engine.yara_ctx.user_rules_tags[task_id]
                if type(tag) ~= "nil" then
                    acts_engine.yara_ctx.m:unload_rules({[1] = tag})
                    acts_engine.yara_ctx.user_rules_tags[task_id] = nil
                end

                local payload = {}
                payload.type = "yr_task_result"
                payload.data = {}
                payload.data.task_id = task_id
                payload.data.detects = acts_engine.db_engine:db_request("db_req_task_detects", nil, nil, nil, nil, {task_id = task_id})
                payload.data.error = res.err
                payload.data.user_data = acts_engine.yara_ctx.task_ctx[task_id].user_data

                __api.send_data_to(acts_engine.yara_ctx.task_ctx[task_id].src, cjson.encode(payload))

                acts_engine.yara_ctx.task_ctx[task_id] = nil
            else
                acts_engine.yara_ctx.task_ctx[task_id].workers = workers - 1
            end

            goto continue
        end

        local task = db_engine:get_task(task_id)

        local is_process_res = res.data.pid ~= nil
        local is_file_res = res.data.filepath ~= nil

        local rules = {}

        if type(task.custom_rules) ~= "nil" then
            for _,rule_id in ipairs(res.data.rules) do
                table.insert(rules, {rule_id = rule_id})
            end
        else
            for _,rule_id in ipairs(res.data.rules) do

                local rule = {}
                rule.rule_id = rule_id
                rule.meta = db_engine:get_rule_meta(rule_id)

                for _,exclude_rule in ipairs(acts_engine.exclude_rules) do
                    if exclude_rule.rule_name:lower() == rule.meta.rule_name:lower() then
                        if is_process_res then
                            __log.infof('the rule skipped due to policy, proc_id = %d, proc_image = %s, rule_name = %s',
                                        res.data.pid, res.data.imagepath, rule.meta.rule_name)
                        elseif is_file_res then
                            __log.infof('the rule skipped due to policy, filepath = %s, sha256_filehash = %s, rule_name = %s',
                                        res.data.filepath, res.data.sha256, rule.meta.rule_name)
                        end
                        goto rules_filter_continue
                    end
                end

                for _,malware_class_item in ipairs(acts_engine.malware_class_items) do
                    if malware_class_item.malware_class:lower() == rule.meta.malware_class:lower() then

                        if malware_class_item.enabled == true then
                            break
                        end

                        if is_process_res then
                            __log.infof('the rule skipped due to policy, proc_id = %d, proc_image = %s, rule_name = %s, malware_class = %s',
                                        res.data.pid, res.data.imagepath, rule.meta.rule_name, rule.meta.malware_class)
                        elseif is_file_res then
                            __log.infof('the rule skipped due to policy, filepath = %s, sha256_filehash = %s, rule_name = %s, malware_class = %s',
                                        res.data.filepath, res.data.sha256, rule.meta.rule_name, rule.meta.malware_class)
                        end
                        goto rules_filter_continue
                    end
                end

                table.insert(rules, rule)
                ::rules_filter_continue::
            end
        end

        if is_process_res then

            db_engine:add_task_result_process(task_id, res.data.pid, res.data.imagepath, res.data.err, rules)

            if acts_engine.yara_ctx.task_ctx[task_id].silent_mode == true then
                goto continue
            end

            for _,rule in ipairs(rules) do

                if rule.meta == nil then

                    __log.infof('process matched (custom rule), proc_id = %d, proc_image = %s, rule_name = %s', res.data.pid, res.data.imagepath, rule.rule_id)

                    local event_data = {
                        ['object.process.id'] = res.data.pid,
                        ['object.process.fullpath'] = res.data.imagepath,
                        rule_name = rule.rule_id,
                        rules = task.custom_rules
                    }

                    self:push_event("yr_process_matched_custom", event_data)
                else

                    __log.infof('process matched, proc_id = %d, proc_image = %s, rule_name = %s, malware_class = %s, rule_severity = %s, rule_type = %s, rule_precision = %d',
                                res.data.pid, res.data.imagepath, rule.meta.rule_name, rule.meta.malware_class, rule.meta.rule_severity, rule.meta.rule_type, rule.meta.rule_precision)

                    if rule.meta.is_silent == true then
                        goto rules_continue
                    end

                    local event_suffix = acts_engine.yara_ctx.task_ctx[task_id].event_suffix

                    local event_data = {
                        [event_suffix .. '.process.id'] = res.data.pid,
                        [event_suffix .. '.process.fullpath'] = res.data.imagepath,
                        rule_name = rule.meta.rule_name,
                        malware_class = rule.meta.malware_class,
                        rule_type = rule.meta.rule_type,
                        rule_precision = rule.meta.rule_precision
                    }

                    if rule.meta.rule_severity == 'low' then
                        self:push_event("yr_" .. event_suffix .. "_process_matched_low", event_data)
                    elseif rule.meta.rule_severity == 'medium' then
                        self:push_event("yr_" .. event_suffix .. "_process_matched_medium", event_data)
                    elseif rule.meta.rule_severity == 'high' then
                        self:push_event("yr_" .. event_suffix .. "_process_matched_high", event_data)
                    else
                        __log.errorf('invalid rule severity: %s', rule.meta.rule_severity)
                    end
                end
                ::rules_continue::
            end
        end

        if is_file_res then

            db_engine:add_task_result_file(task_id, res.data.filepath, res.data.sha256, res.data.err, rules)

            if acts_engine.yara_ctx.task_ctx[task_id].silent_mode == true then
                goto continue
            end

            for _,rule in ipairs(rules) do

                if rule.meta == nil then

                    __log.infof('file matched (custom rule), filepath = %s, sha256_filehash = %s, rule_name = %s', res.data.filepath, res.data.sha256, rule.rule_id)

                    local event_data = {
                        ['object.fullpath'] = res.data.filepath,
                        ['object.sha256_hash'] = res.data.sha256,
                        rule_name = rule.rule_id,
                        rules = task.custom_rules
                    }

                    self:push_event("yr_file_matched_custom", event_data)
                else

                    __log.infof('file matched, filepath = %s, sha256_filehash = %s, rule_name = %s, malware_class = %s, rule_severity = %s, rule_type = %s, rule_precision = %d',
                                res.data.filepath, res.data.sha256, rule.meta.rule_name, rule.meta.malware_class, rule.meta.rule_severity, rule.meta.rule_type, rule.meta.rule_precision)

                    if rule.meta.is_silent == true then
                        goto rules_continue
                    end

                    local event_data = {
                        ['object.fullpath'] = res.data.filepath,
                        ['object.sha256_hash'] = res.data.sha256,
                        rule_name = rule.meta.rule_name,
                        malware_class = rule.meta.malware_class,
                        rule_type = rule.meta.rule_type,
                        rule_precision = rule.meta.rule_precision
                    }

                    if rule.meta.rule_severity == 'low' then
                        self:push_event("yr_file_matched_low", event_data)
                    elseif rule.meta.rule_severity == 'medium' then
                        self:push_event("yr_file_matched_medium", event_data)
                    elseif rule.meta.rule_severity == 'high' then
                        self:push_event("yr_file_matched_high", event_data)
                    else
                        __log.errorf('invalid rule severity: %s', rule.meta.rule_severity)
                    end
                end
                ::rules_continue::
            end
        end

        ::continue::
    end

    -- return infinity waiting next timer call
    -- otherways here need use milliseconds timeout to wait next call

    return 100
end

-- in: nil
-- out: nil
function CActsEngine:quit_cb()
    __log.debug("quit_cb CActsEngine")

    local acts_engine = CActsEngine:cast(self)
    acts_engine.yara_ctx.m:finalize()
    acts_engine.ev_module_stop:set()
    acts_engine.yara_ctx.th_callbacks:join()

    -- here will be triggered before closing vxproto object and destroying the state
end

-- in: string
--      destination token (string) of server module side
-- out: nil
function CActsEngine:agent_connected_cb(dst)
    __log.debugf("agent_connected_cb CActsEngine with token '%s'", dst)
end

-- in: string
--      destination token (string) of server module side
-- out: nil
function CActsEngine:agent_disconnected_cb(dst)
    __log.debugf("agent_disconnected_cb CActsEngine with token '%s'", dst)
end

-- in: nil
-- out: nil
function CActsEngine:update_config_cb()
    __log.debug("update_config_cb CActsEngine")

    local acts_engine = CActsEngine:cast(self)

    local default_config = cjson.decode(__config.get_default_config())
    acts_engine.fastscan_proc_items = default_config['fastscan_proc_items' .. acts_engine.config_suffix]
    acts_engine.fastscan_fs_items = default_config['fastscan_fs_items' .. acts_engine.config_suffix]

    local current_config = cjson.decode(__config.get_current_config())
    acts_engine.exclude_rules = current_config['exclude_rules']
    acts_engine.malware_class_items = current_config['malware_class_items']

    -- convert to generic array
    local fs_excludes = current_config['exclude_fs_items' .. acts_engine.config_suffix]
    if fs_excludes ~= nil then
        acts_engine.exclude_fs_items = {}
        for _,item in pairs(fs_excludes) do
            table.insert(acts_engine.exclude_fs_items, item.filepath)
        end
    end

    -- actual current configuration contains into next fields
    -- self.config.actions
    -- self.config.events
    -- self.config.module
end

-- in: string, string
--      source token (string) of sender module side
--      data payload (string) as a custom string serialized struct object (json)
-- out: boolean
--      result of data processing from business logic
function CActsEngine:recv_data_cb(src, data)
    __log.debugf("perform custom logic for data with payload '%s' from '%s'", data, src)

    local payload = cjson.decode(data)
    if type(payload) ~= "table" then
        return false
    end

    local params = payload.data or {}

    -- remove nodes with cjson.null value
    for k,v in pairs(params) do
        if v == cjson.null then
            params[k] = nil
        end
    end

    if not (params.proc_id == nil or tonumber(params.proc_id) ~= nil) or
       not (params.proc_image == nil or type(params.proc_image) == "string") or
       not (params.filepath == nil or type(params.filepath) == "string") or
       not (params.recursive == nil or type(params.recursive) == "boolean") or
       not (params.rules == nil or type(params.rules) == "string") or
       not (params.task_id == nil or type(params.task_id) == "string") or
       not (params.silent_mode == nil or type(params.silent_mode) == "boolean") then
        __log.errorf("invalid data parameters for data request: %s", data)
        return false
    end

    local function process_scan_resp(results, err)

        local is_imc = self:get_sender_info(src)

        if not is_imc then
            __api.send_data_to(src, cjson.encode(
                glue.merge({type = "scan_response", results = results, error = err}, payload)
            ))
        end

        return true
    end

    local acts_engine = CActsEngine:cast(self)

    local is_imc = self:get_sender_info(src)
    if not is_imc then
        if payload.type == "db_req_active_rules" then
            payload.data = acts_engine.db_engine:db_request(payload.type, params.page, params.pageSize, params.sort, params.filters)
            payload.type = "db_resp_active_rules"
            __api.send_data_to(src, cjson.encode(payload))
        elseif payload.type == "db_req_tasks" then
            payload.data = acts_engine.db_engine:db_request(payload.type, params.page, params.pageSize, params.sort, params.filters)
            payload.type = "db_resp_tasks"
            __api.send_data_to(src, cjson.encode(payload))
        elseif payload.type == "db_req_task_detects" then
            payload.data = acts_engine.db_engine:db_request(payload.type, params.page, params.pageSize, params.sort, params.filters, {task_id = params.task_id})
            payload.type = "db_resp_task_detects"
            __api.send_data_to(src, cjson.encode(payload))
        end
    end

    if payload.type == "yr_task_stop" then

        if params.task_id == nil then
            return false
        end

        payload.data = acts_engine:yara_task_stop(params.task_id)
        payload.type = "yr_task_stop_result"
        __api.send_data_to(src, cjson.encode(payload))

        return true

    elseif payload.type == "yr_task_scan_proc" then
        return process_scan_resp(acts_engine:yara_task_scan_proc(src, params.silent_mode == true, params.user_data,
                                                                 tonumber(params.proc_id), params.proc_image, "object", params.rules))
    elseif payload.type == "yr_task_scan_fs" then

        if params.filepath == nil then
            return false
        end

        return process_scan_resp(acts_engine:yara_task_scan_fs(src, params.silent_mode == true, params.user_data,
                                                               params.filepath, params.recursive == true, params.rules))
    elseif payload.type == "yr_task_fastscan_proc" then
        return process_scan_resp(acts_engine:yara_task_fastscan_proc(src, params.silent_mode == true, params.user_data, params.rules))
    elseif payload.type == "yr_task_fastscan_fs" then
        return process_scan_resp(acts_engine:yara_task_fastscan_fs(src, params.silent_mode == true, params.user_data, params.rules))
    elseif payload.type == "yr_task_fullscan_proc" then
        return process_scan_resp(acts_engine:yara_task_fullscan_proc(src, params.silent_mode == true, params.user_data, params.rules))
    elseif payload.type == "yr_task_fullscan_fs" then
        return process_scan_resp(acts_engine:yara_task_fullscan_fs(src, params.silent_mode == true, params.user_data, params.rules))
    end

    return false
end

-- in: string, string, string
--      source token (string) of sender module side
--      file path (string) on local FS where received file was stored
--      file name (string) is a original file name which was set on sender side
-- out: boolean
--      result of file processing from business logic
function CActsEngine:recv_file_cb(src, path, name)
    __log.debugf("perform custom logic for file with path '%s' and name '%s' from '%s'", path, name, src)
    return true
end

-- in: string, string, table
--      source token (string) of sender module side
--      action name (string) to execute it into the acts_engine
--      action data (table) as a arguments to execute action via acts_engine
--        e.x. {"data": {"key": "val"}, "actions": ["mod1.act1"]}
-- out: boolean
--      result of action processing from business logic
function CActsEngine:recv_action_cb(src, data, name)
    __log.debugf("perform custom logic for action '%s'", name)

    local function process_resp(results, err)

        local is_imc = self:get_sender_info(src)

        if not is_imc then
            __api.send_data_to(src, cjson.encode(
                glue.merge({type = "action_response", name = name, results = results, error = err}, data)
            ))
        end
        return true
    end

    local acts_engine = CActsEngine:cast(self)
    local params = data.data or {}
    local validate_params = function(...)
        local t = glue.pack(...)
        for _, v in ipairs(t) do
            if (v == "object.process.id" and tonumber(params[v]) == nil) or
               (v == "subject.process.id" and tonumber(params[v]) == nil) or
               (v == "object.process.fullpath" and type(params[v]) ~= "string") or
               (v == "subject.process.fullpath" and type(params[v]) ~= "string") or
               (v == "object.fullpath" and type(params[v]) ~= "string") or
               (v == "recursive" and not (params[v] == nil or type(params[v]) == "boolean")) then
                __log.errorf("invalid data parameter '%s' for action '%s', request: %s", v, name, cjson.encode(params))
                return false
            end
        end
        return true
    end

    if name == "yr_object_scan_proc" then
        if not validate_params("object.process.id", "object.process.fullpath") then
            return false
        end

        return process_resp(acts_engine:yara_scan_proc(tonumber(params["object.process.id"]), params["object.process.fullpath"], "object"))
    elseif name == "yr_subject_scan_proc" then
        if not validate_params("subject.process.id", "subject.process.fullpath") then
            return false
        end

        return process_resp(acts_engine:yara_scan_proc(tonumber(params["subject.process.id"]), params["subject.process.fullpath"], "subject"))
    elseif name == "yr_scan_fs" then
        if not validate_params("object.fullpath", "recursive") then
            return false
        end

        return process_resp(acts_engine:yara_scan_fs(params["object.fullpath"], params["recursive"] == true))
    elseif name == "yr_object_task_scan_proc" then
        if not validate_params("object.process.id", "object.process.fullpath") then
            return false
        end

        return process_resp(acts_engine:yara_task_scan_proc(src, false, nil,
                                                            tonumber(params["object.process.id"]), params["object.process.fullpath"], "object"))
    elseif name == "yr_subject_task_scan_proc" then
        if not validate_params("subject.process.id", "subject.process.fullpath") then
            return false
        end

        return process_resp(acts_engine:yara_task_scan_proc(src, false, nil,
                                                            tonumber(params["subject.process.id"]), params["subject.process.fullpath"], "subject"))
    elseif name == "yr_task_scan_fs" then
        if not validate_params("object.fullpath", "recursive") then
            return false
        end

        return process_resp(acts_engine:yara_task_scan_fs(src, false, nil,
                                                          params["object.fullpath"], params["recursive"] == true))
    elseif name == "yr_task_fastscan_proc" then
        return process_resp(acts_engine:yara_task_fastscan_proc(src, false))
    elseif name == "yr_task_fastscan_fs" then
        return process_resp(acts_engine:yara_task_fastscan_fs(src, false))
    elseif name == "yr_task_fullscan_proc" then
        return process_resp(acts_engine:yara_task_fullscan_proc(src, false))
    elseif name == "yr_task_fullscan_fs" then
        return process_resp(acts_engine:yara_task_fullscan_fs(src, false))
    end

    return false
end

-- yara context

local function callback_worker(thread_ctx, filepath_library, ev_callback_ready, q_callback_err, ev_module_stop, q_res)

    local m

    local function callback_result(task_id, object_type, err, result, _)
        q_res:push({task_id = task_id,
                    data = m:decode_result_raw(result, object_type),
                    err = err ~= nil and m:decode_error(err) or nil})
    end

    local function callback_complete(task_id, err, _)
        q_res:push({task_id = task_id,
                    time_end = os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()), -- GMT
                    err = err ~= nil and m:decode_error(err) or nil})
    end

    local function load(modulename)
        local errmsg = ""
        local modulepath = string.gsub(modulename, "%.", "/")
        local filenames = {modulepath .. "/init.lua", modulepath .. ".lua"}
        for _, filename in ipairs(filenames) do
            local filedata = thread_ctx.__files[filename]
            if filedata then
                return assert(loadstring(filedata, filename), "can't load " .. tostring(modulename))
            end
            errmsg = errmsg .. "\n\tno file '" .. filename .. "' (checked with custom loader)"
        end
        return errmsg
    end

    table.insert(package.loaders, 2, load)

    local function callback_worker_p()
        require("strict")
        require("yara_cmodule")

        m = CYaraModule(filepath_library)
        m:set_callbacks(callback_result, callback_complete)

        ev_callback_ready:set()
        ev_module_stop:wait()
    end

    local status, err = require("glue").pcall(callback_worker_p)

    if not status then
        q_callback_err:push(err)
        ev_callback_ready:set()
        return
    end
end

-- in: any
-- out: boolean
function CActsEngine:yara_init(cfg)

    __log.debugf("yara_init CActsEngine")

    self.filepath_system_root = cfg.filepath_system_root
    self.ev_module_stop = thread.event()

    self.yara_ctx = {}
    self.yara_ctx.task_ctx = {} -- map task_ids to task context (workers, event_suffix, silent_mode, ...)
    self.yara_ctx.task_ids = {} -- convert library raw task_ids to guid for DB

    self.yara_ctx.user_rules_next_tag = 0
    self.yara_ctx.user_rules_tags = {} -- map task_id to rule_tag

    self.yara_ctx.q_res = thread.queue(100)

    local ev_callback_ready = thread.event()
    local q_callback_err = thread.queue(1)

    self.yara_ctx.th_callbacks = thread.new(callback_worker, {
        __tmpdir = __tmpdir,
        __files = __files,
        __debug = true,
        __module_id = tostring(__config.ctx.name)
    }, cfg.filepath_library, ev_callback_ready, q_callback_err, self.ev_module_stop, self.yara_ctx.q_res)

    ev_callback_ready:wait()

    if q_callback_err:length() ~= 0 then
        local _,err = q_callback_err:shift(0)
        __log.errorf('unable to initialize yara callback instance: %s', err)
        return false
    end

    __log.debug('yara callback worker: ready')

    self.yara_ctx.m = CYaraModule(cfg.filepath_library)

    local err = self.yara_ctx.m:initialize()
    if err ~= nil then
        __log.errorf('unable to initialize yara main instance: %s', err)
        return false
    end

    err = self.yara_ctx.m:reload_rules({[scan_tag.FILE] = {string = cfg.rules_files},
                                        [scan_tag.MEM]  = {string = cfg.rules_mem}})
    if err ~= nil then
        __log.errorf('unable to load yara rules: %s', err)
        return false
    end

    return true
end

-- load new rules with temporary tag
function CActsEngine:prepare_user_rules(task_id, rules)

    local tag = self.yara_ctx.user_rules_next_tag

    local err = self.yara_ctx.m:reload_rules({[tag] = {string = rules}})
    if err ~= nil then
        return nil, err
    end

    self.yara_ctx.user_rules_tags[task_id] = tag
    self.yara_ctx.user_rules_next_tag = tag + 1

    return tag
end

function CActsEngine:yara_scan_proc(proc_id, proc_image, event_suffix)

    do
        local msg = "yara_scan_proc CActsEngine"
        if proc_id ~= nil then
            msg = msg .. string.format(", proc_id: %d", proc_id)
        end
        if proc_image ~= nil then
            msg = msg .. string.format(", proc_image: %s", proc_image)
        end

        __log.debug(msg)
    end

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local success,res = self.yara_ctx.m:scan_proc(proc_id, proc_image, scan_tag.MEM)
    if not success then
        __log.error(res)
        return nil, res
    end

    local results = {}

    for _,item in ipairs(res) do

        local result = {}
        result.error = item.error
        result.proc_image = item.proc_image
        result.proc_id = item.proc_id
        result.rules = {}

        for _,rule_id in ipairs(item.rules) do

            local rule_meta = self.db_engine:get_rule_meta(rule_id)

            for _,exclude_rule in ipairs(self.exclude_rules) do
                if exclude_rule.rule_name:lower() == rule_meta.rule_name:lower() then
                    __log.infof('the rule skipped due to policy, proc_id = %d, proc_image = %s, rule_name = %s',
                                item.proc_id, item.proc_image, rule_meta.rule_name)
                    goto rules_continue
                end
            end

            for _,malware_class_item in ipairs(self.malware_class_items) do
                if malware_class_item.malware_class:lower() == rule_meta.malware_class:lower() then

                    if malware_class_item.enabled == true then
                        break
                    end

                    __log.infof('the rule skipped due to policy, proc_id = %d, proc_image = %s, rule_name = %s, malware_class = %s',
                                item.proc_id, item.proc_image, rule_meta.rule_name, rule_meta.malware_class)
                    goto rules_continue
                end
            end

            table.insert(result.rules, rule_meta)

            __log.infof('process matched, proc_id = %d, proc_image = %s, rule_name = %s, malware_class = %s, rule_severity = %s, rule_type = %s, rule_precision = %d',
                        item.proc_id, item.proc_image, rule_meta.rule_name, rule_meta.malware_class, rule_meta.rule_severity, rule_meta.rule_type, rule_meta.rule_precision)

            if rule_meta.is_silent == true then
                goto rules_continue
            end

            local event_data = {
                [event_suffix ..'.process.id'] = item.proc_id,
                [event_suffix ..'.process.fullpath'] = item.proc_image,
                rule_name = rule_meta.rule_name,
                malware_class = rule_meta.malware_class,
                rule_type = rule_meta.rule_type,
                rule_precision = rule_meta.rule_precision
            }

            if rule_meta.rule_severity == 'low' then
                self:push_event("yr_" .. event_suffix .. "_process_matched_low", event_data)
            elseif rule_meta.rule_severity == 'medium' then
                self:push_event("yr_" .. event_suffix .. "_process_matched_medium", event_data)
            elseif rule_meta.rule_severity == 'high' then
                self:push_event("yr_" .. event_suffix .. "_process_matched_high", event_data)
            else
                __log.errorf('invalid rule severity: %s', rule_meta.rule_severity)
            end
            ::rules_continue::
        end

        table.insert(results, result)
    end

    -- return #matches ~= 0 and matches or nil
    return results
end

function CActsEngine:yara_scan_fs(filepath, recursive)

    __log.debugf("yara_scan_fs CActsEngine, filepath: %s", filepath)

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local success, res = self.yara_ctx.m:scan_fs(filepath, recursive, scan_tag.FILE)
    if not success then
        __log.error(res)
        return nil, res
    end

    local results = {}

    for _,item in ipairs(res) do

        local result = {}
        result.error = item.error
        result.filepath = item.filepath
        result.sha256_filehash = item.sha256_filehash
        result.rules = {}

        for _,rule_id in ipairs(item.rules) do

            local rule_meta = self.db_engine:get_rule_meta(rule_id)

            for _,exclude_rule in ipairs(self.exclude_rules) do
                if exclude_rule.rule_name:lower() == rule_meta.rule_name:lower() then
                    __log.infof('the rule skipped due to policy, filepath = %s, sha256_filehash = %s, rule_name = %s',
                                item.filepath, item.sha256_filehash, rule_meta.rule_name)
                    goto rules_continue
                end
            end

            for _,malware_class_item in ipairs(self.malware_class_items) do
                if malware_class_item.malware_class:lower() == rule_meta.malware_class:lower() then

                    if malware_class_item.enabled == true then
                        break
                    end

                    __log.infof('the rule skipped due to policy, filepath = %s, sha256_filehash = %s, rule_name = %s, malware_class = %s',
                                item.filepath, item.sha256_filehash, rule_meta.rule_name, rule_meta.malware_class)
                    goto rules_continue
                end
            end

            table.insert(result.rules, rule_meta)

            __log.infof('file matched, filepath = %s, sha256_filehash = %s, rule_name = %s, malware_class = %s, rule_severity = %s, rule_type = %s, rule_precision = %d',
                        item.filepath, item.sha256_filehash, rule_meta.rule_name, rule_meta.malware_class, rule_meta.rule_severity, rule_meta.rule_type, rule_meta.rule_precision)

            if rule_meta.is_silent == true then
                goto rules_continue
            end

            local event_data = {
                ['object.fullpath'] = item.filepath,
                ['object.sha256_hash'] = item.sha256_filehash,
                rule_name = rule_meta.rule_name,
                malware_class = rule_meta.malware_class,
                rule_type = rule_meta.rule_type,
                rule_precision = rule_meta.rule_precision
            }

            if rule_meta.rule_severity == 'low' then
                self:push_event("yr_file_matched_low", event_data)
            elseif rule_meta.rule_severity == 'medium' then
                self:push_event("yr_file_matched_medium", event_data)
            elseif rule_meta.rule_severity == 'high' then
                self:push_event("yr_file_matched_high", event_data)
            else
                __log.errorf('invalid rule severity: %s', rule_meta.rule_severity)
            end
            ::rules_continue::
        end

        table.insert(results, result)
    end

    return results
end

function CActsEngine:yara_task_scan_proc(src, silent_mode, user_data, proc_id, proc_image, event_suffix, rules)

    do
        local msg = "yara_task_scan_proc CActsEngine"
        if proc_id ~= nil then
            msg = msg .. string.format(", proc_id: %d", proc_id)
        end
        if proc_image ~= nil then
            msg = msg .. string.format(", proc_image: %s", proc_image)
        end

        __log.debug(msg)
    end

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.MEM

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    local success, res = self.yara_ctx.m:task_scan_proc(proc_id, proc_image, tag, nil)
    if not success then
        __log.error(res)
        return nil, res
    end

    self.db_engine:add_task_proc(task_id, proc_id, proc_image, scan_type.CUSTOM_PROC, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 1

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    else
        self.yara_ctx.task_ctx[task_id].event_suffix = event_suffix
    end

    self.yara_ctx.task_ids[res] = task_id
    return {task_id = task_id}
end

function CActsEngine:yara_task_scan_fs(src, silent_mode, user_data, filepath, recursive, rules)

    __log.debugf("yara_task_scan_fs CActsEngine, filepath: %s", filepath)

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.FILE

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    local success, res = self.yara_ctx.m:task_scan_fs(filepath, recursive, tag, self.exclude_fs_items)
    if not success then
        __log.error(res)
        return nil, res
    end

    self.db_engine:add_task_fs(task_id, filepath, recursive, scan_type.CUSTOM_FS, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 1

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    end

    self.yara_ctx.task_ids[res] = task_id
    return {task_id = task_id}
end

function CActsEngine:yara_task_fastscan_proc(src, silent_mode, user_data, rules)

    __log.debug("yara_task_fastscan_proc CActsEngine")

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.MEM

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    self.db_engine:add_task_proc(task_id, nil, nil, scan_type.FAST_PROC, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 0

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    else
        self.yara_ctx.task_ctx[task_id].event_suffix = "object"
    end

    for _,item in ipairs(self.fastscan_proc_items) do

        local success, res = self.yara_ctx.m:task_scan_proc(nil, item.proc_image, tag, nil)
        if not success then
            __log.error(res)
            goto continue
        end

        self.yara_ctx.task_ids[res] = task_id
        self.yara_ctx.task_ctx[task_id].workers = self.yara_ctx.task_ctx[task_id].workers + 1
        ::continue::
    end

    return {task_id = task_id}
end

function CActsEngine:yara_task_fastscan_fs(src, silent_mode, user_data, rules)

    __log.debug("yara_task_fastscan_fs CActsEngine")

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.FILE

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    self.db_engine:add_task_fs(task_id, nil, nil, scan_type.FAST_FS, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 0

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    end

    for _,item in ipairs(self.fastscan_fs_items) do

        local success, res = self.yara_ctx.m:task_scan_fs(item.filepath, item.recursive, tag, self.exclude_fs_items)
        if not success then
            __log.error(res)
            goto continue
        end

        self.yara_ctx.task_ids[res] = task_id
        self.yara_ctx.task_ctx[task_id].workers = self.yara_ctx.task_ctx[task_id].workers + 1
        ::continue::
    end

    return {task_id = task_id}
end

function CActsEngine:yara_task_fullscan_proc(src, silent_mode, user_data, rules)

    __log.debug("yara_task_fullscan_proc CActsEngine")

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.MEM

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    self.db_engine:add_task_proc(task_id, nil, nil, scan_type.FULL_PROC, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 1

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    else
        self.yara_ctx.task_ctx[task_id].event_suffix = "object"
    end

    local success, res = self.yara_ctx.m:task_scan_proc(nil, "*", tag, nil)
    if not success then
        __log.error(res)
        return nil, res
    end

    self.yara_ctx.task_ids[res] = task_id
    return {task_id = task_id}
end

function CActsEngine:yara_task_fullscan_fs(src, silent_mode, user_data, rules)

    __log.debug("yara_task_fullscan_fs CActsEngine")

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local task_id = uuid.new()
    local tag = scan_tag.FILE

    if type(rules) ~= "nil" then

        local res, err = self:prepare_user_rules(task_id, rules)
        if res == nil then
            return nil, err
        end

        tag = res
    end

    self.db_engine:add_task_fs(task_id, nil, nil, scan_type.FULL_FS, rules)

    self.yara_ctx.task_ctx[task_id] = {}
    self.yara_ctx.task_ctx[task_id].src = src
    self.yara_ctx.task_ctx[task_id].user_data = user_data
    self.yara_ctx.task_ctx[task_id].workers = 1

    if silent_mode then
        self.yara_ctx.task_ctx[task_id].silent_mode = true
    end

    local success, res = self.yara_ctx.m:task_scan_fs(self.filepath_system_root, true, tag, self.exclude_fs_items)
    if not success then
        __log.error(res)
        return nil, res
    end

    self.yara_ctx.task_ids[res] = task_id
    return {task_id = task_id}
end


function CActsEngine:yara_task_stop(task_id)

    __log.debug("yara_task_stop CActsEngine")

    if self.yara_ctx == nil or self.yara_ctx.m == nil then
        local err = 'yara engine is not initialized'
        __log.error(err)
        return nil, err
    end

    local ids = {}

    for id,task_id_ in pairs(self.yara_ctx.task_ids) do
        if task_id == task_id_ then
            table.insert(ids, id)
        end
    end

    local stopped = false

    for _,id in ipairs(ids) do
        local success = self.yara_ctx.m:task_scan_stop(id)
        if success then
            stopped = true
        end
    end

    if stopped then
        self.db_engine:add_task_result(task_id, task_status.CANCELED, os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()), nil)
    end

    return {task_id = task_id, stopped = stopped}
end

function CActsEngine:yara_update_interrupted_tasks()

    __log.debug("yara_update_interrupted_tasks CActsEngine")

    local res = self.db_engine:db_request("db_req_tasks", nil, nil, nil, {[1] = {field = "status", value = task_status.IN_PROGRESS}})
    if type(res) ~= "table" or type(res.tasks) ~= "table" then
        __log.errorf("failed to get interrupted tasks with result: '%s'", tostring(cjson.encode(res)))
        return
    end
    for _,task in ipairs(res.tasks) do
        __log.infof('task has not been completed, set interrupted status, task_id = %s', task.task_id)
        self.db_engine:add_task_result(task.task_id, task_status.INTERRUPTED)
    end
end
