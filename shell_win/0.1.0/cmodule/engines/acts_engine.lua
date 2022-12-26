require("yaci")
require("strict")
require("engines.base_engine")
require("engines.winprocess")

local fs = require("fs")
local time = require("time")
local cjson   = require("cjson.safe")
local glue = require("glue")
local b64 = require("libb64")


local encoding = {
    -- table maps the one byte CP866 encoding for a character to a Lua string with the UTF-8 encoding for the character (high table)
    "\208\144"    , "\208\145"    , "\208\146"    , "\208\147"    , "\208\148"    , "\208\149"    , "\208\150"    , "\208\151"    ,
    "\208\152"    , "\208\153"    , "\208\154"    , "\208\155"    , "\208\156"    , "\208\157"    , "\208\158"    , "\208\159"    ,
    "\208\160"    , "\208\161"    , "\208\162"    , "\208\163"    , "\208\164"    , "\208\165"    , "\208\166"    , "\208\167"    ,
    "\208\168"    , "\208\169"    , "\208\170"    , "\208\171"    , "\208\172"    , "\208\173"    , "\208\174"    , "\208\175"    ,
    "\208\176"    , "\208\177"    , "\208\178"    , "\208\179"    , "\208\180"    , "\208\181"    , "\208\182"    , "\208\183"    ,
    "\208\184"    , "\208\185"    , "\208\186"    , "\208\187"    , "\208\188"    , "\208\189"    , "\208\190"    , "\208\191"    ,
    "\226\150\145", "\226\150\146", "\226\150\147", "\226\148\130", "\226\148\164", "\226\149\161", "\226\149\162", "\226\149\150",
    "\226\149\149", "\226\149\163", "\226\149\145", "\226\149\151", "\226\149\157", "\226\149\156", "\226\149\155", "\226\148\144",
    "\226\148\148", "\226\148\180", "\226\148\172", "\226\148\156", "\226\148\128", "\226\148\188", "\226\149\158", "\226\149\159",
    "\226\149\154", "\226\149\148", "\226\149\169", "\226\149\166", "\226\149\160", "\226\149\144", "\226\149\172", "\226\149\167",
    "\226\149\168", "\226\149\164", "\226\149\165", "\226\149\153", "\226\149\152", "\226\149\146", "\226\149\147", "\226\149\171",
    "\226\149\170", "\226\148\152", "\226\148\140", "\226\150\136", "\226\150\132", "\226\150\140", "\226\150\144", "\226\150\128",
    "\209\128"    , "\209\129"    , "\209\130"    , "\209\131"    , "\209\132"    , "\209\133"    , "\209\134"    , "\209\135"    ,
    "\209\136"    , "\209\137"    , "\209\138"    , "\209\139"    , "\209\140"    , "\209\141"    , "\209\142"    , "\209\143"    ,
    "\208\129"    , "\209\145"    , "\208\132"    , "\209\148"    , "\208\135"    , "\209\151"    , "\208\142"    , "\209\158"    ,
    "\194\176"    , "\226\136\153", "\194\183"    , "\226\136\154", "\226\132\150", "\194\164"    , "\226\150\160", "\194\160"
}

encoding.convert = function(str)
    local result = {}
    for i = 1, string.len(str) do
        table.insert(result, encoding[string.byte(str,i)-127] or string.sub(str, i, i))
    end
    return table.concat(result)
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
    __log.debug("timer_cb CActsEngine")

    local acts_engine = CActsEngine:cast(self)

    acts_engine:check_running_processes()
    
    return 500
end

function CActsEngine:check_running_processes()
    for k, proc_info in pairs(self.process_map) do
        local is_running = proc_info.proc:is_running()    
        if is_running == true then
            -- check for process output
            local stdout_data = proc_info.proc:check_data()
            if stdout_data ~= '' then
                self.process_map[k].last_active = time.time()
                
                local server_src, browser_src = self:from_process_key(k)
                
                local event_data = {
                    event_type = 'shell_win_output_produced',
                    cmdout = encoding.convert(stdout_data),
                    retaddr = browser_src,
                }
                __api.send_data_to(server_src, cjson.encode(event_data))
            else
                -- check if process obsolete and can be killed
                local current_time = time.time()
                local last_active_time = proc_info.last_active

                -- 15 minutes passed since shell was active.
                if current_time - last_active_time > 15 * 60 then
                    __log.infof('killing inactive terminal session for key: %s', k)
                    proc_info.proc:kill()
                    self.process_map[k] = nil
                end
            end
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
        proc_info.proc:kill()
    end
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
    print(data, src)
    return true
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

    if name == 'shell_win_start' then
        return acts_engine:exec_cmd(src, retaddr)
    end

    if name == 'shell_win_send_input' then
        print(data['data'])
        return acts_engine:provide_input(src, retaddr, data['data'].cmdin)
    end

    if name == 'shell_win_stop' then
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

    proc_info.proc:send_input(input)
    self.process_map[proc_key].last_active = time.time()

    return true
end

-- in: any
-- out: boolean
function CActsEngine:exec_cmd(server_src, browser_src)
    __log.debugf("execCmd CActsEngine with args %s, %s", server_src, browser_src)
    local proc_key = self:process_key(server_src, browser_src)

    local proc_info = self.process_map[proc_key]
    
    if proc_info == nil then
        local procCfg = {
            debug = true,
            cmd = "cmd"
        }
        -- create new process and store it inside map.
        proc_info = {
            proc = CProcess(procCfg),
            last_active = time.time(),
        }
        self.process_map[proc_key] = proc_info
    end

    local is_running = proc_info.proc:is_running()
    if is_running == true then
        proc_info.proc:kill()
    end
    
    return proc_info.proc:run() == true
end

function CActsEngine:stop_shell(server_src, browser_src)
    local proc_key = self:process_key(server_src, browser_src)
    local proc_info = self.process_map[proc_key]

    if proc_info == nil then
        return
    end

    proc_info.proc:kill()
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
