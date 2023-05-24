require("engines.acts_engine")

local sqlite = require("lsqlite3")
local cjson = require("cjson")

local ffi = require("ffi")

local osx = ffi.os == "OSX" or nil
local linux = ffi.os == "Linux" or nil
local win = ffi.abi "win" or nil

-- base config to actions engine
local cfg = {
    config = {},
}

local YARA_DATABASE_FILE = "soldr_yara_v3.db"

local yara_rules_files = {
    WINDOWS_JSON = "rules/kb_windows.json",
    LINUX_JSON = "rules/kb_linux.json",
    OSX_JSON = "rules/kb_osx.json",
    MEMORY_JSON = "rules/kb_memory.json",
    WINDOWS_YAR = "rules/kb_windows.yar",
    LINUX_YAR = "rules/kb_linux.yar",
    OSX_YAR = "rules/kb_osx.yar",
    MEMORY_YAR = "rules/kb_memory.yar"
}

-- actions engine initialize
local acts_engine

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function (src, data)
        __log.debugf("receive data from '%s' with data %s", src, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_data(src, data)
    end,
    file = function (src, path, name)
        __log.infof("receive file from '%s' with name '%s' path '%s'", src, name, path)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_file(src, path, name)
    end,
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function (src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        local action_result = acts_engine:recv_action(src, data, name)
        __log.infof("requested action '%s' was executed: %s", name, action_result)
        return action_result
    end,
    control = function (cmtype, data)
        __log.debugf("receive control msg '%s' with data %s", cmtype, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        if cmtype == "quit" then
            acts_engine:quit()
        end
        if cmtype == "agent_connected" then
            acts_engine:agent_connected(data)
        end
        if cmtype == "agent_disconnected" then
            acts_engine:agent_disconnected(data)
        end
        if cmtype == "update_config" then
            acts_engine:update_config()
        end

        return true
    end,
})

-- main database
cfg.db = sqlite.open(YARA_DATABASE_FILE, "create")
if not cfg.db then
    __log.error("failled to open database")
    return "failed"
else
    cfg.db:exec([[
        pragma temp_store = memory;
        pragma journal_mode = WAL;
        pragma synchronous = NORMAL;
        pragma wal_autocheckpoint = 1000;
        pragma foreign_keys = TRUE;
        vacuum;
    ]])

    -- add __gc to close database on exit module
    local db_prox = newproxy(true)
    getmetatable(db_prox).__gc = function () if cfg.db then cfg.db:close() end end
    cfg.db[db_prox] = true
end

-- initialize rules

local function get_file_content(path)
    assert((type(path) == "string"), "Invalid type of path parameter")
    local file_content = __files[path]
    if file_content then
        return file_content
    end
    return __files[path:gsub("/", "\\")]
end

local function cleanup_json_files()
    __files[yara_rules_files.WINDOWS_JSON] = nil
    __files[yara_rules_files.LINUX_JSON] = nil
    __files[yara_rules_files.OSX_JSON] = nil
    __files[yara_rules_files.MEMORY_JSON] = nil
end

local function cleanup_yar_files()
    __files[yara_rules_files.WINDOWS_YAR] = nil
    __files[yara_rules_files.LINUX_YAR] = nil
    __files[yara_rules_files.OSX_YAR] = nil
    __files[yara_rules_files.MEMORY_YAR] = nil
end

local function init_rules()
    -- TODO refactoring
    do
        local rules_meta_json
        if win then
            rules_meta_json = get_file_content(yara_rules_files.WINDOWS_JSON)
        elseif linux then
            rules_meta_json = get_file_content(yara_rules_files.LINUX_JSON)
        elseif osx then
            rules_meta_json = get_file_content(yara_rules_files.OSX_JSON)
        else
            error("unknown platform")
        end
        assert(type(rules_meta_json == "string"))
        -- TODO handle rules_meta_json ~ nil
        cfg.rules_meta_files = cjson.decode(rules_meta_json)
        assert(type(cfg.rules_meta_files == "table"))

        rules_meta_json = get_file_content(yara_rules_files.MEMORY_JSON)
        assert(type(rules_meta_json == "string"))
        -- TODO handle rules_meta_json ~ nil
        cfg.rules_meta_mem = cjson.decode(rules_meta_json)
        assert(type(cfg.rules_meta_mem == "table"))
    end

    cleanup_json_files()

    if win then
        cfg.config_suffix = "_win"
        -- TODO handle slashes
        cfg.filepath_library = __tmpdir .. "\\yara_scanner.dll"
        cfg.rules_files = get_file_content(yara_rules_files.WINDOWS_YAR)
    elseif linux then
        cfg.config_suffix = "_linux"
        cfg.filepath_library = __tmpdir .. "/libyara_scanner.so"
        cfg.rules_files = get_file_content(yara_rules_files.LINUX_YAR)
    elseif osx then
        cfg.config_suffix = "_mac"
        cfg.filepath_library = __tmpdir .. "/libyara_scanner.so"
        cfg.rules_files = get_file_content(yara_rules_files.OSX_YAR)
    else
        error("unknown platform")
    end

    cfg.rules_mem = get_file_content(yara_rules_files.MEMORY_YAR)

    cleanup_yar_files()

    collectgarbage("collect")
end

init_rules()

-- os

if win then
    cfg.filepath_system_root = "%SYSTEMDRIVE%\\"
else
    cfg.filepath_system_root = "/"
end

--

acts_engine = CActsEngine(cfg)

__log.infof("module '%s' was started", __config.ctx.name)

acts_engine:push_event("yr_module_started", { reason = "regular start" })
acts_engine:run()
acts_engine:push_event("yr_module_stopped", { reason = "regular stop" })
__api.del_cbs({ "data", "file", "action", "control" })
__log.infof("module '%s' was stopped", __config.ctx.name)

acts_engine:cleanup()

-- explicit engine destroy
acts_engine = nil
collectgarbage("collect")

-- release database
cfg.db:close()
cfg.db = nil
collectgarbage("collect")

return "success"
