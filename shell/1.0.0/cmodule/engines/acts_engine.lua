require("yaci")
require("strict")
require("engines.base_engine")

local ffi  = require("ffi")
local time = require("time")
local cjson   = require("cjson.safe")

if ffi.os == "Windows" then
    require("ptys.winpty")
else
    require("ptys.unixpty")
end


CActsEngine = newclass("CActsEngine", CBaseEngine)

--[[
    cfg top keys:
    * config - module arguments (hard limits)
]]
function CActsEngine:init(cfg)
    __log.debug("init CActsEngine object")
    assert(type(cfg) == "table", "configuration object has invalid type")

    cfg.engine = "acts_engine"
    self.super:init(cfg)

    -- initialization of object after base class constructing
    self:update_config_cb()

    self.process_map = {}
    self.winpty = nil
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

    if next(acts_engine.process_map) == nil then
        -- process table is empty
        return 250
    end

    acts_engine:check_running_processes()

    return 100
end

function CActsEngine:check_running_processes()
    for k, proc_info in pairs(self.process_map) do
        -- check for process output
        local stdout_data, successful = proc_info.pty:get_data(10)

        if successful then
            if stdout_data ~= '' then
                self.process_map[k].last_active = time.time()

                local server_src, browser_src = self:from_process_key(k)

                local event_data = {
                    out = stdout_data,
                    retaddr = browser_src,
                }
                __api.send_data_to(server_src, cjson.encode(event_data))
            else
                -- Check if process obsolete and can be killed.
                local current_time = time.time()
                local last_active_time = proc_info.last_active

                -- 15 minutes passed since shell was active.
                if current_time - last_active_time > 15 * 60 then
                    __log.infof('killing inactive terminal session for key: %s', k)
                    proc_info.pty:close()
                    self.process_map[k] = nil
                end
            end
        else
            -- Read failed because of the error. Should kill the terminal to avoid errors.
            __log.infof('killing terminal session for key: %s', k)
            proc_info.pty:close()
            self.process_map[k] = nil
        end
    end
end

-- in: nil
-- out: nil
function CActsEngine:quit_cb()
    -- here will be triggered before closing vxproto object and destroying the state
    __log.debug("quit_cb CActsEngine")
    local acts_engine = CActsEngine:cast(self)

    for k, proc_info in pairs(acts_engine.process_map) do
        proc_info.pty:close()
    end
    acts_engine.process_map = {}
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
    local p = cjson.decode(data)
    local retaddr = p['retaddr']

    local acts_engine = CActsEngine:cast(self)

    return acts_engine:provide_input(src, retaddr, p['i'])
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
    __log.debugf("perform custom logic for action '%s' from '%s'", name, src)

    local acts_engine = CActsEngine:cast(self)

    local retaddr = data['retaddr']

    if name == 'shell_start' then
        return acts_engine:exec_cmd(src, retaddr)
    end

    if name == 'shell_stop' then
        return acts_engine:stop_shell(src, retaddr)
    end

    return false
end

function CActsEngine:provide_input(server_src, browser_src, input)
    local proc_key = self:process_key(server_src, browser_src)
    local proc_info = self.process_map[proc_key]
    if proc_info == nil then
        __log.errorf("failed to find process in map for (%s, %s)", server_src, browser_src)
        return false
    end

    proc_info.pty:send_input(input)
    local stdout_data, successful = proc_info.pty:get_data(50)
    if stdout_data ~= '' and successful then
        local s_src, b_src = self:from_process_key(proc_key)

        local event_data = {
            out = stdout_data,
            retaddr = b_src,
        }
        __api.send_data_to(s_src, cjson.encode(event_data))
    end

    self.process_map[proc_key].last_active = time.time()

    return true
end

-- in: any
-- out: boolean
function CActsEngine:exec_cmd(server_src, browser_src)
    __log.debugf("execCmd CActsEngine with args %s, %s", server_src, browser_src)

    local proc_key = self:process_key(server_src, browser_src)
    local proc_info = self.process_map[proc_key]

    local shell_cmd = self:get_shell_cmd()

    __log.infof("spawning shell %s", shell_cmd)

    if proc_info == nil then
        -- create new process and store it inside map.
        local pty = self:get_pty()
        if pty:start(shell_cmd) == false then
            pty:close()
            return false
        end

        proc_info = {
            pty = pty,
            last_active = time.time(),
        }

        self.process_map[proc_key] = proc_info
        return true
    end

    proc_info.pty:close()
    proc_info.pty = self:get_pty()

    if proc_info.pty:start(shell_cmd) == false then
        proc_info.pty:close()
        return false
    end

    proc_info.last_active = time.time()
    self.process_map[proc_key] = proc_info
    return true
end

function CActsEngine:get_shell_cmd()
    if ffi.os == "Windows" then
        return "cmd"
    end

    local env_shell = os.getenv("SHELL")
    if env_shell ~= nil then
        return env_shell
    end

    return "/bin/sh"
end

function CActsEngine:get_pty()
    if ffi.os == "Windows" then
        return CWinPty()
    end
    return CUnixPty()
end

function CActsEngine:stop_shell(server_src, browser_src)
    local proc_key = self:process_key(server_src, browser_src)
    local proc_info = self.process_map[proc_key]

    if proc_info == nil then
        return false
    end

    proc_info.pty:close()
    self.process_map[proc_key] = nil
    return true
end

function CActsEngine:process_key(server_src, browser_src)
    return cjson.encode({server_src= server_src, browser_src= browser_src})
end

function CActsEngine:from_process_key(key)
    local decoded_key = cjson.decode(key)
    return decoded_key.server_src, decoded_key.browser_src
end
