require("engines.acts_engine")

local sqlite = require("lsqlite3")
local cjson = require("cjson")

local ffi = require("ffi")

local osx = ffi.os == 'OSX' or nil
local linux = ffi.os == 'Linux' or nil
local win = ffi.abi'win' or nil

-- base config to actions engine
local cfg = {
    config = {},
}

-- actions engine initialize
local acts_engine

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function(src, data)
        __log.debugf("receive data from '%s' with data %s", src, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_data(src, data)
    end,

    file = function(src, path, name)
        __log.infof("receive file from '%s' with name '%s' path '%s'", src, name, path)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_file(src, path, name)
    end,

    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        local action_result = acts_engine:recv_action(src, data, name)
        __log.infof("requested action '%s' was executed: %s", name, action_result)
        return action_result
    end,

    control = function(cmtype, data)
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
cfg.db = sqlite.open("soldr_yara_v2.db", "create")
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
    getmetatable(db_prox).__gc = function() if cfg.db then cfg.db:close() end end
    cfg.db[db_prox] = true
end

-- rules meta

do
    local rules_meta_json
    if win then
        rules_meta_json = __files['rules/kb_windows.json']
    elseif linux then
        rules_meta_json = __files['rules/kb_linux.json']
    elseif osx then
        rules_meta_json = __files['rules/kb_osx.json']
    else
        error("unknown platform")
    end
    assert(type(rules_meta_json == "string"))

    cfg.rules_meta_files = cjson.decode(rules_meta_json)
    assert(type(cfg.rules_meta_files == "table"))

    rules_meta_json = __files['rules/kb_memory.json']
    assert(type(rules_meta_json == "string"))

    cfg.rules_meta_mem = cjson.decode(rules_meta_json)
    assert(type(cfg.rules_meta_mem == "table"))
end

__files['rules/kb_windows.json'] = nil
__files['rules/kb_linux.json'] = nil
__files['rules/kb_osx.json'] = nil
__files['rules/kb_memory.json'] = nil

-- files

if win then
    cfg.config_suffix = '_win'
    cfg.filepath_library = __tmpdir .. '/yara_scanner.dll'
    cfg.rules_files = __files['rules/kb_windows.yar']
elseif linux then
    cfg.config_suffix = '_linux'
    cfg.filepath_library = __tmpdir .. '/libyara_scanner.so'
    cfg.rules_files = __files['rules/kb_linux.yar']
elseif osx then
    cfg.config_suffix = '_mac'
    cfg.filepath_library = __tmpdir .. '/libyara_scanner.so'
    cfg.rules_files = __files['rules/kb_osx.yar']
else
    error("unknown platform")
end

cfg.rules_mem = __files['rules/kb_memory.yar']

__files['rules/kb_windows.yar'] = nil
__files['rules/kb_linux.yar'] = nil
__files['rules/kb_osx.yar'] = nil
__files['rules/kb_memory.yar'] = nil

collectgarbage("collect")

-- os

if win then
    cfg.filepath_system_root = "%SYSTEMDRIVE%\\"
else
    cfg.filepath_system_root = "/"
end

--

acts_engine = CActsEngine(cfg)

__log.infof("module '%s' was started", __config.ctx.name)

acts_engine:push_event("yr_module_started", {reason = "regular start"})
acts_engine:run()
acts_engine:push_event("yr_module_stopped", {reason = "regular stop"})

__log.infof("module '%s' was stopped", __config.ctx.name)

-- explicit destroy engines
acts_engine = nil
collectgarbage("collect")

-- release database
cfg.db:close()
cfg.db = nil
collectgarbage("collect")

return "success"
