require("system")
require("engine")

local lfs = require("lfs")
local cjson = require("cjson.safe")

-- variables to initialize event and action engines
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()

-- event and action engines initialization
local action_engine = CActionEngine(
        {},
        __args["debug"][1] == "true"
)

local event_engine = CEventEngine(
        fields_schema,
        current_event_config,
        module_info,
        prefix_db,
        __args["debug"][1] == "true"
)

local function exec_cmd(cmd, raw)
    __log.debugf("cmd to exec: %s", tostring(cmd))
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    __log.debugf("cmd output: %s", tostring(s))
    if raw or raw == nil then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end

local module_config = cjson.decode(__config.get_current_config())

local function reread_module_info()
    module_config = cjson.decode(__config.get_current_config())
end

local function get_opt_cfg__osquery_config()
    return module_config["osquery_config"]
end

local function get_opt_cfg__replace_current_osquery_config()
    return module_config["replace_current_osquery_config"]
end

-- return string with raw content of file (use if agent run with admin permissions)
local function get_file_content(path)
    local content = ''
    local file = io.open(path, "r")
    if file then
        content = file:read("*a")
        file:close()
    end

    return content
end

-- events executor by event name and data
local function push_event(event_name, event_data)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(event_data) == "table", "event_data must be a table")

    -- push the event to the engine
    local info = {
        ["name"] = event_name,
        ["data"] = event_data,
        ["actions"] = {},
    }
    local result, list = event_engine:push_event(info)
    -- check result return variable as marker is there need to execute actions
    if result then
        local data = action_engine:exec(__aid, list)
        for action_id, action_result in ipairs(data) do
            __log.debugf("action '%s' was requested: '%s'", action_id, action_result)
        end
    end
end

local function push_event__osquery_already_installed(event_data)
    return push_event("osquery_linux_already_installed", event_data)
end

local function push_event__osquery_already_started(event_data)
    return push_event("osquery_linux_already_started", event_data)
end

local function push_event__osquery_config_updated_error(event_data)
    return push_event("osquery_linux_config_updated_error", event_data)
end

local function push_event__osquery_config_updated_success(event_data)
    return push_event("osquery_linux_config_updated_success", event_data)
end

local function push_event__osquery_installed_error(event_data)
    return push_event("osquery_linux_installed_error", event_data)
end

local function push_event__osquery_installed_success(event_data)
    return push_event("osquery_linux_installed_success", event_data)
end

local function push_event__osquery_started_error(event_data)
    return push_event("osquery_linux_started_error", event_data)
end

local function push_event__osquery_started_success(event_data)
    return push_event("osquery_linux_started_success", event_data)
end

local function push_event__osquery_unexpected_stopped(event_data)
    return push_event("osquery_linux_unexpected_stopped", event_data)
end

local function push_event__osquery_unexpected_uninstalled(event_data)
    return push_event("osquery_linux_unexpected_uninstalled", event_data)
end

local function push_event__osquery_uninstalled_error(event_data)
    return push_event("osquery_linux_uninstalled_error", event_data)
end

local function push_event__osquery_uninstalled_success(event_data)
    return push_event("osquery_linux_uninstalled_success", event_data)
end

-- arguments:
-- *  path - path to removed dir
-- return bool
local function is_file_exist(path)
    return lfs.attributes(path, "mode") == "file"
end

-- return true or false
local function create_file(path)
    local f, err, errcode = io.open(path, 'w+')
    if not f then
        __log.errorf("error creating file (errcode %s) %s: %s", errcode, path, err)
        return false
    end
    f:close()

    return true
end

-- return 'deb' or 'rpm' or ''
local function detect_package_manager()
    local cmd = "which dpkg"
    local out = exec_cmd(cmd)
    __log.debugf("out of cmd '%s': %s", cmd, out)

    if out ~= "" then
        return "deb"
    end

    cmd = "which rpm"
    out = exec_cmd(cmd)
    __log.debugf("out of cmd '%s': %s", cmd, out)

    if out ~= "" then
        return "rpm"
    end

    return ""
end

local package_manager = detect_package_manager()

local function data_osquery_pkg_path()
    local osquery_pkg_prefix = "osquery."
    return tostring(__tmpdir) .. "/data/binaries/" .. package_manager .. '/' .. osquery_pkg_prefix .. package_manager
end

-- TODO: remake for package manager
local function get_provided_version_osquery()
    local cmd = "dpkg -f " .. data_osquery_pkg_path() .. " version"
    if package_manager == 'rpm' then
        cmd = 'rpm -qip ' .. data_osquery_pkg_path()
    end

    local out = exec_cmd(cmd)
    __log.debugf("out of cmd '%s': %s", cmd, out)

    local result = out:match("%d+.%d+.%d+") or ""

    if result == "" then __log.warnf("provided version osquery: %s", result) end

    return result
end

return {
    exec_cmd = exec_cmd,
    get_opt_cfg__osquery_config = get_opt_cfg__osquery_config,
    get_opt_cfg__replace_current_osquery_config = get_opt_cfg__replace_current_osquery_config,

    push_event__osquery_already_installed = push_event__osquery_already_installed,
    push_event__osquery_already_started = push_event__osquery_already_started,
    push_event__osquery_config_updated_error = push_event__osquery_config_updated_error,
    push_event__osquery_config_updated_success = push_event__osquery_config_updated_success,
    push_event__osquery_installed_error = push_event__osquery_installed_error,
    push_event__osquery_installed_success = push_event__osquery_installed_success,
    push_event__osquery_started_error = push_event__osquery_started_error,
    push_event__osquery_started_success = push_event__osquery_started_success,
    push_event__osquery_unexpected_stopped = push_event__osquery_unexpected_stopped,
    push_event__osquery_unexpected_uninstalled = push_event__osquery_unexpected_uninstalled,
    push_event__osquery_uninstalled_error = push_event__osquery_uninstalled_error,
    push_event__osquery_uninstalled_success = push_event__osquery_uninstalled_success,

    create_file = create_file,
    get_file_content = get_file_content,
    is_file_exist = is_file_exist,
    reread_module_info = reread_module_info,
    package_manager = package_manager,
    data_osquery_pkg_path = data_osquery_pkg_path,
    get_provided_version_osquery = get_provided_version_osquery,
}
