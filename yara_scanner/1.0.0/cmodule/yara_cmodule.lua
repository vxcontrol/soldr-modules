require("strict")
require("yaci")

local ffi = require("ffi")

CYaraModule = newclass("CYaraModule")

ffi.cdef [[

typedef struct _yara_error_t
{
    int err;
    bool is_system;
} yara_error_t;

typedef enum _yara_scan_task_priority_t
{
    YARA_SCAN_TASK_PRIORITY_LOW,
    YARA_SCAN_TASK_PRIORITY_HIGH
} yara_scan_task_priority_t;

typedef enum _yara_scan_object_type_t
{
    YARA_SCAN_OBJECT_PROCESS,
    YARA_SCAN_OBJECT_FILE,
} yara_scan_object_type_t;

typedef struct _yara_result_process_t
{
    uint32_t pid;
    const char* imagepath;

    uint32_t rules_count;
    const char* rule_names[1];
} yara_result_process_t;

typedef struct _yara_result_file_t
{
    const char* filepath;
    const char* sha256;

    uint32_t rules_count;
    const char* rule_names[1];
} yara_result_file_t;

typedef struct _yara_rule_load_item_t
{
    uint32_t tag;
    const char* string_data;
    int string_size;
} yara_rule_load_item_t;

typedef struct _yara_pattern_list_t
{
    size_t size;
    const char** items; // wildcard
} yara_pattern_list_t;

typedef struct _yara_scan_proc_params_t // logical AND
{
    int pid;
    const char* imagename_pattern; // wildcard
    yara_pattern_list_t excludes;
} yara_scan_proc_params_t;

typedef struct _yara_scan_fs_params_t
{
    const char* filepath;
    bool recursive;
    yara_pattern_list_t excludes;
} yara_scan_fs_params_t;

typedef enum _yara_callback_mode_t
{
    YARA_CALLBACK_MODE_NONE,  // do not use scan tasks
    YARA_CALLBACK_MODE_ASYNC, // return results independently (just call callback from threads)
    YARA_CALLBACK_MODE_SYNC,  // return results one by one (sync threads before call callback)
} yara_callback_mode_t;

typedef void(*pfn_yara_cb_scan_result_process_t)(const yara_error_t* err, const yara_result_process_t* result,
                                                 const void* userdata);
typedef void(*pfn_yara_cb_scan_result_file_t)(const yara_error_t* err, const yara_result_file_t* result,
                                              const void* userdata);

typedef void(*pfn_yara_cb_scan_task_result_t)(int id, yara_scan_object_type_t object_type,
                                              const yara_error_t* err, const void* result, // yara_result_process_t* or yara_result_file_t*
                                              const void* userdata);
typedef void(*pfn_yara_cb_scan_task_complete_t)(int id, const yara_error_t* err, const void* userdata);

typedef void(*pfn_yara_cb_decode_error_t)(const char *msg, const void* userdata);

typedef struct _yara_callbacks_t
{
    pfn_yara_cb_scan_task_result_t scan_task_result;
    pfn_yara_cb_scan_task_complete_t scan_task_complete;
} yara_callbacks_t;

yara_error_t yara_set_callbacks(yara_callback_mode_t mode,
                                const yara_callbacks_t* cbs, const void* userdata);

yara_error_t yara_initialize();
void yara_finalize();

void yara_decode_error(const yara_error_t* err,
                       pfn_yara_cb_decode_error_t cb, const void* userdata);

yara_error_t yara_reload_rules(yara_rule_load_item_t rule_items[], uint8_t count);
void yara_unload_rules(uint32_t tags[], uint8_t count);

yara_error_t yara_scan_fs(const yara_scan_fs_params_t* params, uint32_t rules_tag,
                          pfn_yara_cb_scan_result_file_t cb, const void* userdata);
yara_error_t yara_scan_task_fs(const yara_scan_fs_params_t* params, uint32_t rules_tag,
                               yara_scan_task_priority_t prio, int* task_id);

yara_error_t yara_scan_proc(const yara_scan_proc_params_t* params, uint32_t rules_tag,
                            pfn_yara_cb_scan_result_process_t cb, const void* userdata);
yara_error_t yara_scan_task_proc(const yara_scan_proc_params_t* params, uint32_t rules_tag,
                                 yara_scan_task_priority_t prio, int* task_id);

yara_error_t yara_scan_task_stop(int task_id);

]]

function CYaraModule:init(library_filename)

    assert(type(library_filename) == "string", "library filename must be a string")

    self.module = ffi.load(library_filename)
    self.api = {
        set_callbacks = self.module.yara_set_callbacks,
        initialize = self.module.yara_initialize,
        finalize = self.module.yara_finalize,
        decode_error = self.module.yara_decode_error,
        reload_rules = self.module.yara_reload_rules,
        unload_rules = self.module.yara_unload_rules,
        scan_fs = self.module.yara_scan_fs,
        scan_task_fs = self.module.yara_scan_task_fs,
        scan_proc = self.module.yara_scan_proc,
        scan_task_proc = self.module.yara_scan_task_proc,
        scan_task_stop = self.module.yara_scan_task_stop,
    }
end

function CYaraModule:set_callbacks(callback_result, callback_complete)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(callback_result) == "nil" or type(callback_result) == "function", "callback_result must be a function or nil")
    assert(type(callback_complete) == "nil" or type(callback_complete) == "function", "callback_complete must be a function or nil")

    local cbs = ffi.new("yara_callbacks_t[1]")
    cbs[0].scan_task_result = callback_result
    cbs[0].scan_task_complete = callback_complete

    self.api.set_callbacks(ffi.C.YARA_CALLBACK_MODE_SYNC, cbs, nil)
end

function CYaraModule:initialize()
    assert(self.module ~= nil, "module is not loaded")

    local err = self.api.initialize()
    if err.err ~= 0 then
        return self:decode_error(err)
    end

    return nil
end

function CYaraModule:free()
    assert(self.module ~= nil, "module is not loaded")

    if self.api then
        self.api.set_callbacks = nil
        self.api.initialize = nil
        self.api.finalize = nil
        self.api.decode_error = nil
        self.api.reload_rules = nil
        self.api.unload_rules = nil
        self.api.scan_fs = nil
        self.api.scan_task_fs = nil
        self.api.scan_proc = nil
        self.api.scan_task_proc = nil
        self.api.scan_task_stop = nil

        self.api = nil
    end

    self.module = nil

    collectgarbage("collect")
end

function CYaraModule:finalize()
    assert(self.module ~= nil, "module is not loaded")
    self.api.finalize()
end

function CYaraModule:reload_rules(rules)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(rules) == "table", "rules must be table of paris \"tag - table\"")

    local mmap = require("mmap")

    local rules_opened = {}

    for tag,t in pairs(rules) do

        local map, own

        if t.string ~= nil then
            map = {
                addr = ffi.cast("const void*", t.string),
                size = #t.string
            }
        elseif t.filepath ~= nil then
            map = assert(mmap.mmap_ro(t.filepath))
            own = true
        end

        table.insert(rules_opened, {tag = tag, map = map, own = own})
    end

    local load_items = ffi.new("yara_rule_load_item_t[?]", #rules_opened)

    for i,rule in ipairs(rules_opened) do
        load_items[i - 1].tag = rule.tag
        load_items[i - 1].string_data = rule.map.addr
        load_items[i - 1].string_size = rule.map.size
    end

    local err = self.api.reload_rules(load_items, #rules_opened)

    for _,rule in ipairs(rules_opened) do
        if rule.own then
            --rule.map:free()
            mmap.munmap(rule.map)
        end
    end

    if err.err ~= 0 then
        return self:decode_error(err)
    end

    return nil
end

function CYaraModule:unload_rules(tags)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(tags) == "table", "rules must be table (array of tags)")

    local unload_tags = ffi.new("uint32_t[?]", #tags)

    for i,tag in ipairs(tags) do
        unload_tags[i - 1] = tag
    end

    self.api.unload_rules(unload_tags, #tags)
end

local result_process_ct = ffi.typeof("const yara_result_process_t*")
local result_file_ct = ffi.typeof("const yara_result_file_t*")

function CYaraModule:decode_result(result)
    assert(type(result) == "cdata", "result must be cdata")

    local _ = self
    local result_ct = ffi.typeof(result)

    local res = {}

    if result_ct == result_process_ct then
        if result.pid ~= nil then
            res.pid = result.pid
        end
        if result.imagepath ~= nil then
            res.imagepath = ffi.string(result.imagepath)
        end
    elseif result_ct == result_file_ct then
        if result.filepath ~= nil then
            res.filepath = ffi.string(result.filepath)
        end
        if result.sha256 ~= nil then
            res.sha256 = ffi.string(result.sha256)
        end
    else
        assert(false, "invalid result argument")
    end

    res.rules = {}
    if result.rules_count ~= 0 then
        for i=1,result.rules_count do
            table.insert(res.rules, ffi.string(result.rule_names[i - 1]))
        end
    end

    return res
end

function CYaraModule:decode_result_raw(result, ctype)
    if ctype == ffi.C.YARA_SCAN_OBJECT_PROCESS then
        return self:decode_result(ffi.cast("const yara_result_process_t*", result))
    elseif ctype == ffi.C.YARA_SCAN_OBJECT_FILE then
        return self:decode_result(ffi.cast("const yara_result_file_t*", result))
    else
        assert(false, "unknown result type")
    end
end

function CYaraModule:decode_error(err)
    assert(type(err) == "cdata")

    local msg

    local decode_error_callback_c = ffi.cast("pfn_yara_cb_decode_error_t", function(str, _)
        msg = ffi.string(str)
    end)

    self.api.decode_error(err, decode_error_callback_c, nil)
    decode_error_callback_c:free()

    if err.is_system then
        return "system error = " .. err.err .. " (" .. msg .. ")"
    end

    return "libyara error = " .. err.err .. " (" .. msg .. ")"
end

function CYaraModule:prepare_process_path(path)

    local _ = self

    if path == nil then
        return nil
    end

    assert(type(path) == "string", "path must be a string")

    if path:find("*") == nil and path:find("?") == nil then
        return "*" .. path .. "*"
    end

    return path
end

function CYaraModule:scan_fs(filepath, recursive, tag, excludes)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(filepath) == "string", "filepath must be a string")
    assert(type(recursive) == "boolean", "recursive must be a boolean")
    assert(type(tag) == "number", "tag must be a number")
    assert(type(excludes) == "table" or type(excludes) == "nil", "excludes must be a table or nil")

    local results = {}

    local result_callback_c = ffi.cast("pfn_yara_cb_scan_result_file_t", function(err, result, _)

        local msg
        if err ~= nil then
            msg = self:decode_error(err[0])
        end

        local data = self:decode_result(result)
        table.insert(results, {error = msg, filepath = data.filepath, sha256_filehash = data.sha256, rules = data.rules})
    end)

    local params = ffi.new("yara_scan_fs_params_t[1]")
    params[0].filepath = filepath
    params[0].recursive = recursive

    if excludes ~= nil and #excludes ~= 0 then

        params[0].excludes.size = #excludes
        params[0].excludes.items = ffi.new("const char*[?]", #excludes)

        for i,exclude in ipairs(excludes) do
            params[0].excludes.items[i - 1] = exclude
        end
    else
        params[0].excludes.size = 0;
    end

    local err = self.api.scan_fs(params, tag, result_callback_c, nil)
    result_callback_c:free()

    if err.err ~= 0 then
        return false, self:decode_error(err)
    end

    return true, results
end

function CYaraModule:scan_proc(pid, imagename, tag, excludes)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(pid) == "number" or type(pid) == "nil", "pid must be a number or nil")
    assert(type(imagename) == "string" or type(imagename) == "nil", "imagename must be a string or nil")
    assert(type(tag) == "number", "tag must be a number")
    assert(type(excludes) == "table" or type(excludes) == "nil", "excludes must be a table or nil")

    local results = {}

    local result_callback_c = ffi.cast("pfn_yara_cb_scan_result_process_t", function(err, result, _)

        local msg
        if err ~= nil then
            msg = self:decode_error(err[0])
        end

        local data = self:decode_result(result)
        table.insert(results, {error = msg, proc_image = data.imagepath, proc_id = data.pid, rules = data.rules})
    end)

    local params = ffi.new("yara_scan_proc_params_t[1]")
    params[0].pid = pid ~= nil and pid or 0
    params[0].imagename_pattern = self:prepare_process_path(imagename)

    if excludes ~= nil and #excludes ~= 0 then

        params[0].excludes.size = #excludes
        params[0].excludes.items = ffi.new("const char*[?]", #excludes)

        for i,exclude in ipairs(excludes) do
            params[0].excludes.items[i - 1] = exclude
        end
    else
        params[0].excludes.size = 0;
    end

    local err = self.api.scan_proc(params, tag, result_callback_c, nil)
    result_callback_c:free()

    if err.err ~= 0 then
        return false, self:decode_error(err)
    end

    return true, results
end

function CYaraModule:task_scan_fs(filepath, recursive, tag, excludes)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(filepath) == "string", "filepath must be a string")
    assert(type(recursive) == "boolean", "recursive must be a boolean")
    assert(type(tag) == "number", "tag must be a number")
    assert(type(excludes) == "table" or type(excludes) == "nil", "excludes must be a table or nil")

    local params = ffi.new("yara_scan_fs_params_t[1]")
    params[0].filepath = filepath
    params[0].recursive = recursive

    if excludes ~= nil and #excludes ~= 0 then

        params[0].excludes.size = #excludes
        params[0].excludes.items = ffi.new("const char*[?]", #excludes)

        for i,exclude in ipairs(excludes) do
            params[0].excludes.items[i - 1] = exclude
        end
    else
        params[0].excludes.size = 0;
    end

    local task_id = ffi.new("int[1]")

    local err = self.api.scan_task_fs(params, tag, ffi.C.YARA_SCAN_TASK_PRIORITY_LOW, task_id)
    if err.err ~= 0 then
        return false, self:decode_error(err)
    end

    return true, task_id[0]
end

function CYaraModule:task_scan_proc(pid, imagename, tag, excludes)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(pid) == "number" or type(pid) == "nil", "pid must be a number or nil")
    assert(type(imagename) == "string" or type(imagename) == "nil", "imagename must be a string or nil")
    assert(type(tag) == "number", "tag must be a number")
    assert(type(excludes) == "table" or type(excludes) == "nil", "excludes must be a table or nil")

    local params = ffi.new("yara_scan_proc_params_t[1]")
    params[0].pid = pid ~= nil and pid or 0
    params[0].imagename_pattern = self:prepare_process_path(imagename)

    if excludes ~= nil and #excludes ~= 0 then

        params[0].excludes.size = #excludes
        params[0].excludes.items = ffi.new("const char*[?]", #excludes)

        for i,exclude in ipairs(excludes) do
            params[0].excludes.items[i - 1] = exclude
        end
    else
        params[0].excludes.size = 0;
    end

    local task_id = ffi.new("int[1]")

    local err = self.api.scan_task_proc(params, tag, ffi.C.YARA_SCAN_TASK_PRIORITY_LOW, task_id)
    if err.err ~= 0 then
        return false, self:decode_error(err)
    end

    return true, task_id[0]
end

function CYaraModule:task_scan_stop(task_id)
    assert(self.module ~= nil, "module is not loaded")
    assert(type(task_id) == "number", "task_id must be a number")

    local err = self.api.scan_task_stop(task_id)
    if err.err ~= 0 then
        return false, self:decode_error(err)
    end

    return true
end
