require("os")
require("engine")
require("system")
local bit     = require("bit")
local glue    = require("glue")
local cjson   = require("cjson.safe")
local lk32    = require("waffi.windows.kernel32")
local sysinfo = CSystemInfo({})

-- variables to initialize event and action engines
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()

-- event and action engines initialization
local action_engine = CActionEngine(
    {},
    __args["debug_correlator"][1] == "true"
)
local event_engine = CEventEngine(
    fields_schema,
    current_event_config,
    module_info,
    prefix_db,
    __args["debug_correlator"][1] == "true"
)

-- Module mutable global variables
local want_to_update_binary = false
local want_to_update_config = false
local version = "unknown"

-- Module immutable global variables
local arch = __api.get_arch()
local def_sysmon_prefix = "sysmon_vx"
local def_sysmon_binary_name = def_sysmon_prefix .. "_" .. arch .. ".exe"
local def_sysmon_config_name = "config.xml"
local data_sysmon_binary_path = tostring(__tmpdir) .. "\\data\\binaries\\" .. def_sysmon_binary_name
local data_sysmon_config_path = os.getenv("TEMP") .. "\\" .. def_sysmon_config_name
local module_config = cjson.decode(__config.get_current_config())
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

-- events executor by event name and data
local function push_event(event_name, event_data)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(event_data) == "table", "event_data must be a table")
    __log.debugf("push event to correlator: '%s'", event_name)

    -- push the event to the engine
    local info = {
        ["name"] = event_name,
        ["data"] = event_data,
        ["actions"] = {},
    }
    local result, list = event_engine:push_event(info)

    -- check result return variable as marker is there need to execute actions
    if result then
        for action_id, action_result in ipairs(action_engine:exec(__aid, list)) do
            __log.debugf("action '%s' was requested: '%s'", action_id, action_result)
        end
    end
end

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

-- return boolean
local function dump_sysmon_config_file()
    local file = io.open(data_sysmon_config_path, "w+b")
    if not file then
        return false
    end

    local ok = file:write(get_option_config("sysmon_config"))
    file:close()
    return ok
end

-- return boolean
local function compare_sysmon_config_file()
    local file = io.open(data_sysmon_config_path, "rb")
    if not file then
        return false
    end

    local config = file:read("*all")
    file:close()
    return config == get_option_config("sysmon_config")
end

-- return string of name or empty string if serive doesn't exists
local function get_sysmon_service_name()
    local out = sysinfo:exec_cmd("sc query state= all | findstr /i sysmon") or ""
    local sysmon_service_name = string.match(string.lower(out), "(sysmon[^\r\n ]*)")
    if sysmon_service_name then return sysmon_service_name end
    __log.warnf("can't find sysmon service name in output: '%s'", out)
    return ""
end

-- return path to binary as a string
local function get_path_to_sysmon_binary(name)
    if name == "" then
        return ""
    end

    local cmd = "sc qc " .. name
    local regex_en = "BINARY_PATH_NAME[^A-Z]+([^\r\n]+)"
    local regex_ru = "Имя_двоичного_файла[^A-Z]+([^\r\n]+)"
    local out = sysinfo:exec_cmd(cmd) or ""
    local sysmon_path = string.match(out, regex_en) or string.match(encoding.convert(out), regex_ru)
    if sysmon_path then return sysmon_path end
    __log.errorf("can't find path to sysmon binary by cmd '%s' in output: %s", cmd, out)
    return ""
end

-- return: pid number of sysmon service process
local function get_pid_of_sysmon_process(name)
    local cmd = "sc queryex " .. name
    local regex_en = "PID[^0-9]+([^\r\n ]+)"
    local regex_ru = "ID_процесса[^0-9]+([^\r\n ]+)"
    local out = sysinfo:exec_cmd(cmd) or ""
    local pid = string.match(out, regex_en) or string.match(encoding.convert(out), regex_ru)
    if pid == nil then
        __log.warnf("can't find PID for sysmon service in output: %s", out)
        return 0
    end
    return tonumber(pid)
end

-- return: string of running, stopped, unknown
local function check_sysmon_state(name)
    local cmd = "sc query " .. name
    local regex_en = "STATE[^A-Z]+([^\r\n ]+)"
    local regex_ru = "Состояние[^A-Z]+([^\r\n ]+)"
    local out = sysinfo:exec_cmd(cmd) or ""
    local state = string.match(out, regex_en) or string.match(encoding.convert(out), regex_ru)
    if state == nil then
        __log.errorf("can't find sysmon state by cmd '%s' in output: %s", cmd, out)
        return "unknown"
    end
    return string.find(state, "RUNNING") ~= nil and "running" or "stopped"
end

-- return: string of running, stopped, unknown
local function check_sysmon_type(name)
    if name == "" then
        return "unknown"
    elseif string.find(string.lower(name), def_sysmon_prefix) ~= nil then
        return "internal"
    else
        return "external"
    end
end

-- return string of version or nil if error
local function get_sysmon_version(path)
    local regex = "system monitor ([^ ]+)"
    local out = sysinfo:exec_cmd(path)
    if type(out) ~= "string" then
        __log.errorf("can't run sysmon binary '%s' to get service version", path)
        return ""
    end
    local sysmon_service_version = string.match(string.lower(out), regex)
    if sysmon_service_version then return sysmon_service_version end
    __log.errorf("can't find sysmon version by path '%s' in output: %s", path, out)
    return ""
end

-- return winapi module process object to control state of system process
local function get_sysmon_process(pid)
    local hSysmon = lk32.OpenProcess(
        bit.bor(
            lk32.PROCESS_QUERY_LIMITED_INFORMATION,
            lk32.PROCESS_TERMINATE,
            0x00100000 -- lk32.SYNCHRONIZE
        ),
        false, pid)
    if hSysmon == 0 then
        local last_error = tonumber(lk32.GetLastError())
        __log.errorf("can't get sysmon process handle by pid '%d' with error '%d'", pid, last_error)
        return nil
    end
    return hSysmon
end

-- via binary exec (-c flag)
-- return boolean
local function sysmon_config_update(path)
    if path == "" then
        return false
    end

    local out = sysinfo:exec_cmd(path .. " -c " .. data_sysmon_config_path)
    if type(out) ~= "string" then
        __log.errorf("can't run sysmon binary '%s' to update service config", path)
        return false
    end
    if string.find(out, "updated") ~= nil then return true end
    __log.errorf("can't update sysmon config with error output: %s", out)
    return false
end

-- via binary exec (-u flag)
-- return boolean
local function sysmon_uninstall(path)
    if path == "" then
        return false
    end

    local out = sysinfo:exec_cmd(path .. " -u force")
    if type(out) ~= "string" then
        __log.errorf("can't run sysmon binary '%s' to uninstall service", path)
        return false
    end
    if string.find(out, "stopped") ~= nil and string.find(out, "removed") ~= nil then
        return true
    end
    __log.errorf("can't uninstall sysmon service with error output: %s", out)
    return false
end

-- via binary exec (-i flag)
-- return boolean
local function sysmon_install(path)
    if path == "" then
        return false
    end

    local out = sysinfo:exec_cmd(path .. " -accepteula -i")
    if type(out) ~= "string" then
        __log.errorf("can't run sysmon binary '%s' to install service", path)
        return false
    end

    if #glue.collect(string.gmatch(out, "already registered")) == 1 then
        out = sysinfo:exec_cmd(path .. " -u force")
        __log.infof("sysmon already registered and should be removed before with output: %s", out or "")
        __api.await(3000)
        out = sysinfo:exec_cmd(path .. " -accepteula -i")
        if type(out) ~= "string" then
            __log.errorf("can't run sysmon binary '%s' to install service after uninstall", path)
            return false
        end
    end

    local idx, idy = 0, 0
    for _ in string.gmatch(out, "installed") do idx = idx + 1 end
    for _ in string.gmatch(out, "started") do idy = idy + 1 end
    if idx == 2 and idy == 2 then return true end
    __log.errorf("can't install sysmon service with error output: %s", out)
    return false
end

-- via service control (sc) tool
-- return boolean
local function sysmon_start(name)
    local cmd = "sc start " .. name
    local out = sysinfo:exec_cmd(cmd) or ""
    if string.find(out, name) ~= nil then return true end
    __log.errorf("can't start sysmon service by name '%s' with output: %s", name, out)
    return false
end

local function preparing_phase()
    __log.debug("try to get sysmon service name")
    local sysmon_service_name = get_sysmon_service_name()
    local sysmon_service_type = check_sysmon_type(sysmon_service_name)

    if sysmon_service_name ~= "" then
        local sysmon_service_path = get_path_to_sysmon_binary(sysmon_service_name)
        local new_sysmon_version = get_sysmon_version(data_sysmon_binary_path)
        local current_sysmon_version = get_sysmon_version(sysmon_service_path)
        local msg = "name " .. sysmon_service_name .. "; "
        msg = msg .. "type " .. sysmon_service_type .. "; "
        msg = msg .. "cur version " .. current_sysmon_version .. "; "
        msg = msg .. "new version " .. new_sysmon_version
        version = current_sysmon_version
        __log.infof("found sysmon service: %s", msg)
        push_event("sysmon_already_installed", {
            reason = msg,
            version = current_sysmon_version,
        })

        if current_sysmon_version ~= new_sysmon_version then
            __log.debug("current sysmon version is different to the new")
            if get_option_config("replace_current_sysmon_binary") or sysmon_service_type == "internal" then
                __log.debug("try to uninstall current sysmon service and install the new again")
                if not sysmon_uninstall(sysmon_service_path) then
                    local err = "failed to uninstall current sysmon service"
                    __log.error(err)
                    push_event("sysmon_updated_error", {
                        reason = err,
                        version = current_sysmon_version,
                    })
                    return "control"
                else
                    want_to_update_binary = true
                    __log.info("sysmon uninstalled successful and try to install internal")
                    return "install"
                end
            else
                __log.info("replacing of current sysmon version not permitted")
            end
        else
            __log.info("current sysmon version is equal to the new")
        end

        if get_option_config("replace_current_sysmon_config") then
            __log.debug("need to replace current sysmon config according module configuration")
            return "configure"
        end

        __log.info("used previous sysmon configuration")
        return "control"
    else -- unknown sysmon version because it isn't installed
        __log.info("sysmon not installed")
        return "install"
    end
end

local function install_phase()
    __log.debug("try to install sysmon")
    version = get_sysmon_version(data_sysmon_binary_path)
    if not sysmon_install(data_sysmon_binary_path) then
        local err = "failed to install sysmon from module directory"
        __log.error(err)
        push_event("sysmon_installed_error", {
            reason = err,
            version = version,
        })
        return "control"
    end

    local sysmon_service_name = get_sysmon_service_name()
    if sysmon_service_name ~= "" then
        local msg = "name " .. sysmon_service_name
        if check_sysmon_state(sysmon_service_name) == "running" then
            local event = want_to_update_binary and "updated" or "installed"
            want_to_update_binary = false
            __log.infof("sysmon %s success: %s", event, msg)
            push_event("sysmon_" .. event .. "_success", {
                reason = msg,
                version = version,
            })
        else
            local err = "sysmon not running after install: " .. msg
            __log.error(err)
            push_event("sysmon_installed_error", {
                reason = err,
                version = version,
            })
            return "control"
        end
    else
        local err = "sysmon service not found after install"
        __log.error(err)
        push_event("sysmon_installed_error", {
            reason = err,
            version = version,
        })
        return "control"
    end

    want_to_update_config = true
    __log.info("need to configure new installed sysmon service")
    return "configure"
end

local function configure_phase()
    __log.debug("try to configure sysmon")
    local sysmon_service_name = get_sysmon_service_name()
    local sysmon_service_path = get_path_to_sysmon_binary(sysmon_service_name)
    version = get_sysmon_version(sysmon_service_path)
    if check_sysmon_state(sysmon_service_name) == "stopped" then
        __log.info("sysmon is stopped and should be running")
        if not sysmon_start(sysmon_service_name) then
            local err = "failed to start sysmon servive"
            __log.error(err)
            push_event("sysmon_started_error", {
                reason = err,
                version = version,
            })
        else
            local msg = "name " .. sysmon_service_name .. "; "
            msg = msg .. "version " .. version
            __log.infof("sysmon started success: %s", msg)
            push_event("sysmon_started_success", {
                reason = msg,
                version = version,
            })
        end
    else
        __log.info("sysmon is running")
    end

    if want_to_update_config or not compare_sysmon_config_file() then
        if not get_option_config("replace_current_sysmon_config") then
            __log.info("update sysmon congig not permitted")
            want_to_update_config = false
            return "control"
        end
        __log.info("sysmon config is outdated or empty")
        if not dump_sysmon_config_file() then
            local err = "failed to dump sysmon config to module directory"
            __log.error(err)
            push_event("sysmon_config_updated_error", {
                reason = err,
                version = version,
            })
            return "control"
        end
        if not sysmon_config_update(sysmon_service_path) then
            want_to_update_config = false
            local err = "failed to update sysmon config from module directory"
            __log.error(err)
            push_event("sysmon_config_updated_error", {
                reason = err,
                version = version,
            })
            return "control"
        else
            local msg = "name " .. sysmon_service_name
            __log.info("sysmon config updated success")
            push_event("sysmon_config_updated_success", {
                reason = msg,
                version = version,
            })
        end
    else
        __log.debug("current sysmon config is equal to the new")
    end

    __log.info("need to run control handler to checking sysmon lifecycle")
    return "control"
end

-- main function for business logic of module
local function control_phase()
    __log.debug("try to control sysmon service")
    local sysmon_service_name = get_sysmon_service_name()
    local last_state = check_sysmon_state(sysmon_service_name)
    local sysmon_service_process, new_state
    local update_sysmon_service_process = function ()
        local sysmon_service_pid = get_pid_of_sysmon_process(sysmon_service_name)
        if sysmon_service_pid ~= 0 then
            sysmon_service_process = get_sysmon_process(sysmon_service_pid)
        else
            sysmon_service_process = nil
        end
    end
    if last_state == "running" then
        update_sysmon_service_process()
    end
    while true do
        if sysmon_service_process then
            local wait_result = lk32.WaitForSingleObject(sysmon_service_process, 1000)
            if wait_result == lk32.WAIT_TIMEOUT then
                goto next
            end
        end
        new_state = check_sysmon_state(sysmon_service_name)
        if last_state ~= new_state then
            if new_state == "stopped" then
                __log.info("sysmon is stopped and should be running")
                push_event("sysmon_unexpected_stopped", {
                    reason = "from state: " .. last_state,
                    version = version,
                })
                sysmon_service_process = nil
                if not sysmon_start(sysmon_service_name) then
                    local err = "failed to start sysmon servive"
                    __log.error(err)
                    push_event("sysmon_started_error", {
                        reason = err,
                        version = version,
                    })
                else
                    local msg = "name " .. sysmon_service_name .. "; "
                    msg = msg .. "version " .. version
                    new_state = "running"
                    __log.infof("sysmon started success: %s", msg)
                    push_event("sysmon_started_success", {
                        reason = msg,
                        version = version,
                    })
                    update_sysmon_service_process()
                end
            elseif new_state == "running" then
                __log.info("sysmon is running")
                push_event("sysmon_already_started", {
                    reason = "from state: " .. last_state,
                    version = version,
                })
                update_sysmon_service_process()
            elseif new_state == "unknown" then
                __log.info("sysmon was uninstalled by user and should be reinstall")
                push_event("sysmon_unexpected_uninstalled", {
                    reason = "from state: " .. last_state,
                    version = version,
                })
                sysmon_service_process = nil
                __api.await(1000)
                if install_phase() == "configure" then
                    __log.info("sysmon installed successful")
                    sysmon_service_name = get_sysmon_service_name()
                    if configure_phase() == "control" then
                        __log.info("sysmon configured successful")
                        new_state = "running"
                        update_sysmon_service_process()
                    else
                        __log.error("sysmon configured with error")
                    end
                else
                    __log.error("sysmon installed with error")
                end
            end
            __log.info("next loop in control handler")
            last_state = new_state
        end
        ::next::
        if __api.is_close() then
            break
        end
        __api.await(3000)
    end
end

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)
        if cmtype == "update_config" then
            -- update current action and event list from new config
            current_event_config = __config.get_current_event_config()
            module_info = __config.get_module_info()

            -- renew current event engine instance
            if event_engine ~= nil then
                event_engine:free()
                event_engine = nil
                collectgarbage("collect")
                event_engine = CEventEngine(
                    fields_schema,
                    current_event_config,
                    module_info,
                    prefix_db,
                    __args["debug_correlator"][1] == "true"
                )
            end

            module_config = cjson.decode(__config.get_current_config())
            want_to_update_config = true
            configure_phase()
        end
        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

__log.infof("replace binary is '%s'", get_option_config("replace_current_sysmon_binary"))
__log.infof("replace config is '%s'", get_option_config("replace_current_sysmon_config"))

local next_phase = preparing_phase()
while next_phase do
    if next_phase == "install" then
        next_phase = install_phase()
    elseif next_phase == "configure" then
        next_phase = configure_phase()
    elseif next_phase == "control" then
        next_phase = control_phase()
    else
        __log.errorf("unexpected next handler: %s", next_phase)
        break
    end
end

-- TODO: here need to get reason of stopping
local sysmon_service_name = get_sysmon_service_name()
local sysmon_service_type = check_sysmon_type(sysmon_service_name)
if get_option_config("replace_current_sysmon_binary") or sysmon_service_type == "internal" then
    __log.debug("try to uninstall sysmon")
    if not sysmon_uninstall(get_path_to_sysmon_binary(sysmon_service_name)) then
        local err = "failed to uninstall sysmon from the system before remove module"
        __log.error(err)
        push_event("sysmon_uninstalled_error", {
            reason = err,
            version = version,
        })
    else
        __log.info("sysmon was uninstalled from the system")
        if not os.remove(data_sysmon_config_path) then
            local err = "failed to remove sysmon config from the FS before remove module"
            __log.error(err)
            push_event("sysmon_uninstalled_error", {
                reason = err,
                version = version,
            })
        else
            __log.info("sysmon config was removed from the FS")
            push_event("sysmon_uninstalled_success", {
                reason = "regular logic",
                version = version,
            })
        end
    end
else
    __log.info("keep current sysmon version on the system")
end

action_engine = nil
event_engine = nil
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return 'success'
