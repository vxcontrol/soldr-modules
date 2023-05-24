require("system")
local helpers = require("helpers")

--local sysinfo = CSystemInfo({})

-- Module immutable global variables
local osquery_config_name = "osquery.conf"
local path_to_dumped_config = tostring(__tmpdir) .. "/" .. osquery_config_name

local Osquery = {}

-- linux
-- return string with path to config of installed osquery
function Osquery:get_config_path()
    local path = '/etc/osquery/osquery.conf'

    if helpers.is_file_exist(path) or helpers.create_file(path) then return path end

    return ''
end

-- linux
-- return bool
function Osquery:is_installed()
    return self:get_version() ~= ""
end

-- linux
-- return string like '5.5.1'
function Osquery:get_version()
    local cmd = "osqueryd --version"
    local out = helpers.exec_cmd(cmd)
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local result = out:match("%d+.%d+.%d+") or ""

    return result
end

-- linux
-- return bool
function Osquery:is_version_correct()
    local version = self:get_version()
    __log.infof("found osquery version '%s'", version)

    return version == helpers.get_provided_version_osquery()
end

-- linux
-- return string contaned raw config by installed osquery
function Osquery:get_config()
    local path = self:get_config_path()

    if path == '' then return '' end

    return helpers.get_file_content(path)
end

-- linux
-- return boolean
function Osquery:update_config_file()
    local config_path = self:get_config_path()
    local file = io.open(config_path, "w+")
    if not file then
        return false
    end

    local _ = file:write(helpers.get_opt_cfg__osquery_config())
    file:close()

    return self:get_config() == helpers.get_opt_cfg__osquery_config()
end

-- linux
-- returns 2 agrs: bool, string (reason)
function Osquery:install()
    local cmd = "dpkg -i " .. helpers.data_osquery_pkg_path()
    if helpers.package_manager == 'rpm' then
        cmd = 'rpm -i ' .. helpers.data_osquery_pkg_path()
    end

    local out = helpers.exec_cmd(cmd) or ""
    __log.infof("out of cmd '%s': %s", cmd, out)

    local success = self:is_installed()

    local reason = ""
    if not success then reason = "osquery can not installed" end

    return success, reason
end

-- linux
-- remove osquery from machine
-- returns
-- * bool: result of uninstalation
-- * string: reason of failed uninstalation
function Osquery:uninstall()
    local cmd = 'systemctl stop osqueryd'
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    cmd = 'dpkg --force-all -P osquery'
    if helpers.package_manager == 'rpm' then
        cmd = 'rpm -e osquery'
    end

    out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    os.execute("sleep 2")
    if not self:is_installed() then return true, "" end

    local state = self:state()
    return false, "error uninstalation osquery, current state: " .. state
end

-- linux
-- return: string of running, stopped, unknown
function Osquery:state()
    if not self:is_installed() then return 'unknown' end

    local cmd = 'systemctl is-active osqueryd'
    local out = helpers.exec_cmd(cmd) or ''
    __log.debugf("out of cmd '%s': %s", cmd, out)

    if out == "unknown\n" then return "unknown" end
    if out == "active\n" then return "running" end

    return "stopped"
end

-- linux
-- return true/false
function Osquery:start()
    local cmd = 'systemctl start osqueryd'
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local state = self:state()
    if state == 'running' then return true end

    cmd = 'systemctl enable osqueryd'
    out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    state = self:state()
    if state == 'running' then return true end

    return false
end

-- linux
-- return true/false
function Osquery:stop()
    local cmd = 'systemctl stop osqueryd'
    local out = helpers.exec_cmd(cmd) or ""
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local state = self:state()
    if state ~= 'stopped' then return false end

    return true
end

return Osquery
