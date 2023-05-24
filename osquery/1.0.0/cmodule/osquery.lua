local helpers = require("helpers")
local socket = require("socket")

-- Module immutable global variables
-- WARNING!
-- osquery_msi_name should contains version of msi package (see Osquery:get_msi_version())
local osquery_msi_name = "osquery-5.5.1.msi"
local data_osquery_msi_path = tostring(__tmpdir) .. "\\data\\binaries\\" .. osquery_msi_name

local encoding = {
    -- table maps the one byte CP866 encoding for a character to a Lua string with the UTF-8 encoding for the character (high table)
    "\208\144", "\208\145", "\208\146", "\208\147", "\208\148", "\208\149", "\208\150", "\208\151",
    "\208\152", "\208\153", "\208\154", "\208\155", "\208\156", "\208\157", "\208\158", "\208\159",
    "\208\160", "\208\161", "\208\162", "\208\163", "\208\164", "\208\165", "\208\166", "\208\167",
    "\208\168", "\208\169", "\208\170", "\208\171", "\208\172", "\208\173", "\208\174", "\208\175",
    "\208\176", "\208\177", "\208\178", "\208\179", "\208\180", "\208\181", "\208\182", "\208\183",
    "\208\184", "\208\185", "\208\186", "\208\187", "\208\188", "\208\189", "\208\190", "\208\191",
    "\226\150\145", "\226\150\146", "\226\150\147", "\226\148\130", "\226\148\164", "\226\149\161", "\226\149\162", "\226\149\150",
    "\226\149\149", "\226\149\163", "\226\149\145", "\226\149\151", "\226\149\157", "\226\149\156", "\226\149\155", "\226\148\144",
    "\226\148\148", "\226\148\180", "\226\148\172", "\226\148\156", "\226\148\128", "\226\148\188", "\226\149\158", "\226\149\159",
    "\226\149\154", "\226\149\148", "\226\149\169", "\226\149\166", "\226\149\160", "\226\149\144", "\226\149\172", "\226\149\167",
    "\226\149\168", "\226\149\164", "\226\149\165", "\226\149\153", "\226\149\152", "\226\149\146", "\226\149\147", "\226\149\171",
    "\226\149\170", "\226\148\152", "\226\148\140", "\226\150\136", "\226\150\132", "\226\150\140", "\226\150\144", "\226\150\128",
    "\209\128", "\209\129", "\209\130", "\209\131", "\209\132", "\209\133", "\209\134", "\209\135",
    "\209\136", "\209\137", "\209\138", "\209\139", "\209\140", "\209\141", "\209\142", "\209\143",
    "\208\129", "\209\145", "\208\132", "\209\148", "\208\135", "\209\151", "\208\142", "\209\158",
    "\194\176", "\226\136\153", "\194\183", "\226\136\154", "\226\132\150", "\194\164", "\226\150\160", "\194\160"
}

encoding.convert = function(str)
    local result = {}
    for i = 1, string.len(str) do
        table.insert(result, encoding[string.byte(str, i) - 127] or string.sub(str, i, i))
    end
    return table.concat(result)
end

local Osquery = {}

function Osquery:get_bypass_daemon_binary_path()
    local typical_paths = {
        [["C:\Program Files\osquery\osqueryd\osqueryd.exe"]],
        [["C:\Program Files (x86)\osquery\osqueryd\osqueryd.exe"]]
    }

    for i = 1, 2 do
        if helpers.is_file_exist(typical_paths[i]) then
            __log.infof("found osquery in typical path %s", typical_paths[i])
            return typical_paths[i]
        end
    end

    return ""
end

-- return string with path to .exe of installed osquery daemon
function Osquery:get_daemon_binary_path()
    local cmd = "sc qc osqueryd"

    local regex_en = "BINARY_PATH_NAME[^\"A-Z]+([^\r\n]+)"
    local regex_ru = "Имя_двоичного_файла[^\"A-Z]+([^\r\n]+)"

    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local osquery_path = string.match(out, regex_en) or string.match(encoding.convert(out), regex_ru) or ""
    osquery_path = osquery_path:gsub("--flagfile.*", "")

    if osquery_path ~= "" then
        return helpers.normalize_path(osquery_path)
    end
    __log.errorf("can not find path to osquery binary by cmd '%s' in output: %s", cmd, out)

    return self:get_bypass_daemon_binary_path()
end

-- return string with path to .exe interactive console of installed osquery
function Osquery:get_console_binary_path()
    local console_path = self:get_daemon_binary_path():gsub("osqueryd\\osqueryd.exe", "osqueryi.exe")

    return console_path
end

-- return string - path to manage-osqueryd.ps1 for execute powershell command
function Osquery:get_ps_manage_path()
    local path = self:get_daemon_binary_path():gsub("osqueryd\\osqueryd.exe", "manage-osqueryd.ps1")

    return helpers.normalize_path(path)
end

-- return string with path to config of installed osquery
function Osquery:get_config_path()
    local config_path = self:get_daemon_binary_path():gsub("osqueryd\\osqueryd.exe", "osquery.conf")

    return helpers.normalize_path(config_path)
end

-- return string with path to flagfile of installed osquery
function Osquery:get_flagfile_path()
    local config_path = self:get_daemon_binary_path():gsub("osqueryd\\osqueryd.exe", "osquery.flags")

    return helpers.normalize_path(config_path)
end

-- return string - path to osquery dir
function Osquery:get_dir_path()
    local path = self:get_daemon_binary_path():gsub("\\osqueryd\\osqueryd.exe.*", "\"")

    return helpers.normalize_path(path)
end

-- return string ("osqueryd" or '')
function Osquery:get_service_name()
    local cmd = "sc query state= all | findstr /i osqueryd"
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local osquery_service_name = string.match(string.lower(out), "(osqueryd[^\r\n ]*)")
    if osquery_service_name then
        return osquery_service_name
    end

    __log.warnf("can not find osquery service name in output: '%s'", out)
    return ""
end

-- return bool
function Osquery:is_installed()
    local osquery_service_name = self:get_service_name()
    if osquery_service_name == "" then
        return false
    end

    return true
end

-- return string like '5.5.1'
function Osquery:get_version()
    local binary_path = self:get_console_binary_path()
    local cmd = binary_path .. " --version"

    local out = helpers.exec_cmd(cmd)
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local result = out:match("%d+.%d+.%d+") or ""

    return result
end

function Osquery:get_msi_version()
    local out = osquery_msi_name:match("%d+.%d+.%d+")

    return out
end

-- return bool
function Osquery:is_version_correct()
    local version = self:get_version()
    __log.infof("found osquery version '%s'", version)

    return version == self:get_msi_version()
end

-- return string contaned raw config by installed osquery
function Osquery:get_config()
    return helpers.get_file_content(self:get_config_path())
end

-- return string contaned raw flagfile by installed osquery
function Osquery:get_flagfile()
    return helpers.get_file_content(self:get_flagfile_path())
end

-- return boolean: boolean, string
function Osquery:update_config_file()
    return helpers.update_file("osquery.conf", self:get_config_path(), helpers.get_option_config("osquery_config"))
end

-- return 2 args: boolean, string
function Osquery:update_flag_file()
    return helpers.update_file("osquery.flags", self:get_flagfile_path(), helpers.get_option_config("osquery_flagfile"))
end

function Osquery:is_exist_as_service()
    local cmd = [[wmic service where Name="osqueryd" Get Name]]
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local exist = out:find("osquery")

    return exist ~= nil
end

-- returns 2 agrs: bool, string (reason)
function Osquery:install()
    local log_path = tostring(__tmpdir) .. "\\install-osquery.log"
    local cmd = "msiexec /i " .. helpers.normalize_path(data_osquery_msi_path) .. " /quiet /log " .. helpers.normalize_path(log_path)

    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local success = self:is_installed()
    local exist = self:is_exist_as_service()

    __log.debugf("osquery installation info, success: %s, exist: %s", success, exist)

    if success and exist then
        return true, ""
    end

    if not success and exist then
        return false, "unknown error, osquery exist as a service but not found"
    end

    local binary_path = self:get_bypass_daemon_binary_path()

    if binary_path == '' then
        return false, 'binary path to osqueryd.exe is unknown'
    end

    local create_service_cmd = 'sc.exe create osqueryd binPath= ' .. binary_path .. ' DisplayName= "osqueryd" start= auto'
    local create_service_out = helpers.exec_cmd(create_service_cmd) or ""

    __log.debugf("out of cmd '%s': %s", create_service_cmd, create_service_out)

    if not self:is_exist_as_service() then
        return false, "error creating osquery as a service"
    end

    local start_service_cmd = 'wmic service where Name="osqueryd" startservice'
    local create_service_out = helpers.exec_cmd(start_service_cmd) or ""
    __log.debugf("out of cmd '%s': %s", create_service_cmd, create_service_out)

    success = self:is_installed()

    local reason = ""
    if not success then
        reason = "osquery created as service but can not started"
    end

    return success, reason

    --local ps_manage_path = self:get_ps_manage_path()
    --
    --if not success and ps_manage_path == "" then return success, "osquery can not installed using msiexec" end
    --
    --local cmd = "powershell -executionpolicy bypass -File " .. ps_manage_path .. " -install"
    --local out = helpers.exec_cmd(cmd) or ""
    --__log.debugf("out of cmd '%s': %s", cmd, out)
    --
    --success = self:is_installed()
    --
    --local reason = ""
    --if not success then reason = "osquery can not installed using powershell" end
    --
    --return success, reason
end

-- return: string of running, stopped, unknown
function Osquery:state()
    local cmd = "sc query osqueryd"
    local regex_en = "STATE[^A-Z]+([^\r\n ]+)"
    local regex_ru = "Состояние[^A-Z]+([^\r\n ]+)"

    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local state = string.match(out, regex_en) or string.match(encoding.convert(out), regex_ru)
    if state == nil then
        __log.errorf("can not find osquery state by cmd '%s' in output: %s", cmd, out)
        return "unknown"
    end

    return string.find(state, "RUNNING") ~= nil and "running" or "stopped"
end

-- remove osquery from machine as a service
-- returns
-- * bool: result of uninstalation
-- * string: reason of failed uninstalation
function Osquery:uninstall()
    local osquery_dir_path = self:get_dir_path()

    if osquery_dir_path == "" then
        return false, "can't uninstall osquery, dir path is empty"
    end

    if not self:is_exist_as_service() then
        return false, "osquery is no installed as a service"
    end

    local osqueryd_service_stop_cmd = [[wmic service where name="osqueryd" stopservice]]
    local osqueryd_service_stop_out = helpers.exec_cmd(osqueryd_service_stop_cmd)
    __log.debugf("out of cmd '%s': %s", osqueryd_service_stop_cmd, osqueryd_service_stop_out)

    socket.sleep(5)

    local osqueryd_service_del_cmd = [[wmic service where name="osqueryd" delete]]
    local osqueryd_service_del_out = helpers.exec_cmd(osqueryd_service_del_cmd)
    __log.debugf("out of cmd '%s': %s", osqueryd_service_del_cmd, osqueryd_service_del_out)

    local state = self:state()
    if state ~= "unknown" then
        return false, "can't uninstall osquery, current state is " .. state
    end

    local result = helpers.remove_dir(osquery_dir_path)
    if result then
        return true, ""
    end

    return false, osquery_dir_path .. " wasn't remove"
end

-- return true/false
function Osquery:start()
    local cmd = "sc start osqueryd"
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local state = self:state()
    if state == "running" then
        return true
    end

    return false
end

-- return true/false
function Osquery:stop()
    local cmd = "sc stop osqueryd"

    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local state = self:state()
    if state ~= "stopped" then
        return false
    end

    return true
end

-- return
-- * true/false
-- * reason for false
function Osquery:restart()
    if not self:stop() then
        return false, "can not stop osquery"
    end

    if not self:start() then
        return false, "can not start osquery"
    end

    return true, ""
end

return Osquery
