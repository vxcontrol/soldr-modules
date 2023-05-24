---------------------------------------------------
-- MOCK API description
--[===============================================[
__mock            - global object which contains internal fields to mock vxlua API and must be initialize before
__mock.is_closed  - tells if module need to be closed
__mock.vars       - table (dict) is a local storage between scenario and all receive callbacks
__mock.stage      - table (dict) is a state machine storage to use it between scenario and all receive callbacks
__mock.stage.ctx  - table (dict) is storage of collected date from send_* api call from the module side
__mock.stage.time - number is a last time (number of seconds) when the state machine changed its step
__mock.stage.coro - coroutine for main scenario of the test script
__mock.timeout    - number is a maximum number of seconds in step before the state machine will raise timeout error
__mock.module     - string is the module name which going to load into the lua state for testing (module/version)
__mock.version    - string is the module version which going to load into the lua state for testing (module/version)
__mock.side       - string is the module code folder with main lua (must be "server" or "agent")
__mock.cwd        - string is a path to temporary current directory to which cwd will be changed after loading MOCK API
__mock.tmpdir     - string is a path to temporary/flushable directory which contains "data" and "clibs" files
__mock.base_path  - string is a path modules folder where going to looking for module path; default is current dir
__mock.log_level  - string is logging level which will use for testing: ["error", "warn", "info", "debug", "trace"]
__mock.scenario   - function is a main script other side which can check the state and can send packets into the state
__mock.module_callbacks - registered list of module callbacks (populated by __api.add_cbs)
__mock.callbacks  - table (list) of functions which will called from the lua state to notify scenario side
    data(self, dst, src, data)         - function to notify scenario when module want to send data to another side
    file(self, dst, src, path, name)   - function to notify scenario when module want to send file to another side
    text(self, dst, src, text, name)   - function to notify scenario when module want to send text to another side
    msg(self, dst, src, msg, mtype)    - function to notify scenario when module want to send msg to another side
    action(self, dst, src, data, name) - function to notify scenario when module want to send action to another side
    push_event(self, aid, event)       - function to notify scenario when module want to log event into local DB
    trace(func_name, ...)              - function to notify scenario when module called some method from vxapi
__mock.os         - table (dict) is a config OS for loading the module (i.e. clibs libraries will use its)
    type - string is enum of values ["windows", "linux", "darwin"] (current OS type by default)
    name - string is a OS type and version (mock OS name by type by default)
    arch - string is enum of values ["386", "amd64"] (current OS/interpreter arch by default)
__mock.agents     - table (list) of tables (dict) are agents list which will be connected to the module state
                    the list will be automatically enriched to the local connection from other side (mock side)
    id      - string is the agent ID in MD5 hash format (rand ID by default)
    ip      - string is the IP address with port which show in connection as a source (127.0.0.1:RAND by default)
    ips     - table (list) of strings which each string must be in CIDR format ([ {IP}/24 ] by default)
    gid     - string is a group ID of the agent in MD5 hash format (__mock.group_id by default)
    ver     - string is a version of the agent binary (v1.0.0.0 by default)
    src     - srting is a source token of the agent connection (rand ID by default)
    dst     - srting is a destination token of the agent connection (rand ID by default)
    type    - string is enum of values ["VXAgent", "Browser", "External"] (VXAgent by default)
    host    - string is a hostname of the agent ({ID}.local by default)
    os_type - string is enum of values ["windows", "linux", "darwin"] (windows by default)
    os_name - string is a OS type and version ("Microsoft Windows 10.0" by default)
    os_arch - string is enum of values ["386", "amd64"] (amd64 by default)
__mock.modules    - table (list) of tables (dict) are modules list which will be registered into imc for the api
                    the list will be automatically enriched to the current module state
    name  - string is a module name without spaces (it's required key)
    gid   - string is a group ID of the module in MD5 hash format (__mock.group_id by default)
    token - string is imc token for the module (preferably not to use and will use rand imc token)
__mock.routes     - table (list) of tables (dict) are routes list which will be registered into routes for the api
    src - srting is a source token of the agent connection (it's required key)
    dst - srting is a destination token of the agent connection (it's required key)
__mock.policy_id   - string is the current policy ID in MD5 hash format (rand ID by default)
__mock.group_id    - string is the current group ID in MD5 hash format (rand ID by default)
__mock.agent_id    - string is the current agent ID in MD5 hash format (rand ID by default)
__mock.agent_conn  - table (dict) is a connection structure from mock side as the same of __mock.agents[1] struct
__mock.server_conn - table (dict) is a structure of connection to the server for mocking on the agent side
    scheme - string is enum of values ["ws", "wss"] (wss by default)
    host   - string is the IP address or domain which show in connection as a destination (server.local by default)
    port   - string is the port number which show in connection as a destination (8443 by default)
    ips    - table (list) of strings are IP addresses to which resolve server host ([127.0.0.1] by default)
__mock.sec         - table (dict) is the secure storage state key-value which would was loaded from policy config
---------------------------------------------------
-- auto generated keys
---------------------------------------------------
__mock.module_info      - table (dict) is a combination for info.json file and module item from config.json file
__mock.module_type      - string is a reference to __mock.side: "smodule" or "cmodule"; res path: "module/version/type"
__mock.module_path      - string is the path to "module/version" folder
__mock.module_conf_path - string is the path to "module/version/config" folder; folder contains *.json files
__mock.module_code_path - string is the path to "module/version/type" folder; end of dir is "smodule" or "cmodule"
__mock.mock_token       - string is a vxproto token which identify other side (mock side)
__mock.module_token     - string is a vxproto token which identify module side
__mock.module_imc_token - string is a imc token of the module which builded from __mock.module and __mock.group_id
__mock.groups           - table (list) of group hashes which builded from __mock.modules list and their gid field
__mock.trace            - function is a tracing method to control using of MOCK API from the module code
__mock.args             - table (dict) is a reflection of the args.json file and parse it from json file
__mock.cbs              - table (dict) is a map to store internal callbacks from module to send vxproto packets
__mock.is_closed        - boolean is a flag of stopping the module to pass it the module via api
---------------------------------------------------
-- private methods or validators after initialize
---------------------------------------------------
__mock.rand_hash()
__mock.rand_imc_token()
__mock.rand_token()
__mock.rand_uuid()
__mock.make_imc_token(mname, gid)
__mock.check_hash(hash)
__mock.check_imc_token(imc_token)
__mock.check_token(token)
__mock.check_domain(domain)
__mock.check_ipv4(ip)
__mock.check_ipv4_with_port(tuple)
__mock.check_port(sport)
__mock.check_cidr(cidr)
__mock.test(name, func) - wrapper function for coroutine starting
__mock.tmppath(name) - function that generates full path of file named by "name" within tmp directory
---------------------------------------------------
-- public methods after initialize; use in self too
---------------------------------------------------
__mock:expect(etype, filter)
__mock:add_context(etype, data)
__mock:pop_from_context(etype, filter)
__mock:module_start()
__mock:module_stop()
__mock:module_update_config(conf, act_conf, ev_conf)
__mock:disconnect()
__mock:connect()
__mock:send_data(src, dst, data)
__mock:send_file(src, dst, path, name)
__mock:send_text(src, dst, text, name)
__mock:send_msg(src, dst, msg, mtype)
__mock:send_action(src, dst, data, name)
--]===============================================]

local ffi     = require("ffi")
local lfs     = require("lfs")
local md5     = require("md5")
local glue    = require("glue")
local crc32   = require("crc32")
local cjson   = require("cjson.safe")
local luapath = require("path")
math.randomseed(crc32(tostring({})))

local function combine_path(...)
    local t = glue.pack(...)
    local path = t[1] or ""
    for i = 2, #t do
        path = luapath.combine(path, t[i])
    end
    return path
end

local function check_file(path)
    return lfs.attributes(path, "mode") == "file"
end

local function check_dir(path)
    return lfs.attributes(path, "mode") == "directory"
end

local check_lua_files_in_dir
check_lua_files_in_dir = function(dir)
    for file in lfs.dir(dir) do
        local result
        local file_path = combine_path(dir, file)
        if not glue.indexof(file, { ".", "..", ".gitkeep" }) then
            if lfs.attributes(file_path, "mode") == "file" then
                result = luapath.ext(file) == "lua"
            elseif lfs.attributes(file_path, "mode") == "directory" then
                result = check_lua_files_in_dir(file_path)
            end
        end
        if result then
            return true
        end
    end
    return false
end

local clean_dir
clean_dir = function(dir)
    for file in lfs.dir(dir) do
        local file_path = combine_path(dir, file)
        if not glue.indexof(file, { ".", "..", ".gitkeep" }) then
            if lfs.attributes(file_path, "mode") == "file" then
                os.remove(file_path)
            elseif lfs.attributes(file_path, "mode") == "directory" then
                clean_dir(file_path)
                lfs.rmdir(file_path)
            end
        end
    end
end

---------------------------------------------------
-- MOCK chack general __mock object to use API
---------------------------------------------------
assert(type(__mock) == "table", "__mock must be initialized")
---------------------------------------------------

---------------------------------------------------
__mock.is_closed = false
__mock.vars = __mock.vars or {}
assert(type(__mock.vars) == "table", "__mock.vars must be table type")
---------------------------------------------------

---------------------------------------------------
__mock.cbs = {}
__mock.is_closed = false

__mock.stage = __mock.stage or {}
assert(type(__mock.stage) == "table", "__mock.stage must be table type")
__mock.stage.time = __mock.stage.time or os.time()
assert(type(__mock.stage.time) == "number", "__mock.stage.time must be number type")
__mock.stage.ctx = __mock.stage.ctx or {}
assert(type(__mock.stage.ctx) == "table", "__mock.stage.ctx must be table type")

__mock.timeout = __mock.timeout or 60
assert(type(__mock.timeout) == "number", "__mock.timeout must be number type")
assert(__mock.timeout >= 0 and __mock.timeout <= 3600, "__mock.timeout must be [0, 3600]")
---------------------------------------------------

---------------------------------------------------
assert(type(__mock.module) == "string", "__mock.module must be string type")
assert(type(__mock.version) == "string", "__mock.version must be string type")

assert(__mock.side == "server" or __mock.side == "agent",
    "__mock.side must be server or agent value")
__mock.module_type = __mock.side == "server" and "smodule" or "cmodule"
---------------------------------------------------

---------------------------------------------------
__mock.tmpdir = __mock.tmpdir or combine_path(lfs.currentdir(), "tmpdir")
assert(type(__mock.tmpdir) == "string", "__mock.tmpdir must be string type")
lfs.mkdir(__mock.tmpdir)
assert(check_dir(__mock.tmpdir), "__mock.tmpdir must be exist in FS")
assert(not check_dir(combine_path(__mock.tmpdir, __mock.module)),
    "__mock.tmpdir must not contains folder with module name")
assert(not check_file(combine_path(__mock.tmpdir, "config.json")),
    "__mock.tmpdir must not contains config.json file")
assert(not check_lua_files_in_dir(__mock.tmpdir),
    "__mock.tmpdir must not contains *.lua files inside")
clean_dir(__mock.tmpdir)
lfs.mkdir(combine_path(__mock.tmpdir, "data"))
---------------------------------------------------

---------------------------------------------------
-- MOCK build module paths to key folders
---------------------------------------------------
__mock.base_path = __mock.base_path or lfs.currentdir()
assert(type(__mock.base_path) == "string", "__mock.base_path must be string type")
assert(check_dir(__mock.base_path), "__mock.base_path must be exist in FS")
assert(check_file(combine_path(__mock.base_path, "config.json")),
    "__mock.base_path must contains config.json file")

__mock.module_path = combine_path(__mock.base_path, __mock.module, __mock.version)
assert(check_dir(__mock.module_path), "__mock.module_path must be exist in FS: " .. __mock.module_path)

__mock.module_conf_path = combine_path(__mock.module_path, "config")
assert(check_dir(__mock.module_conf_path), "__mock.module_conf_path must be exist in FS: " .. __mock.module_conf_path)

__mock.module_code_path = combine_path(__mock.module_path, __mock.module_type)
assert(check_dir(__mock.module_code_path), "__mock.module_code_path must be exist in FS: " .. __mock.module_code_path)

__mock.tmppath = function(...) return combine_path(__mock.tmpdir, ...) end
---------------------------------------------------

---------------------------------------------------
-- MOCK change current directory to tmp folder
---------------------------------------------------
__mock.initial_cwd = lfs.currentdir()
__mock.cwd = __mock.cwd or combine_path(__mock.initial_cwd, "tmpcwd")
assert(type(__mock.cwd) == "string", "__mock.cwd must be string type")
lfs.mkdir(__mock.cwd)
lfs.mkdir(combine_path(__mock.cwd, "data"))
lfs.chdir(__mock.cwd)
---------------------------------------------------

---------------------------------------------------
-- MOCK logging settings
---------------------------------------------------
__mock.log_level = __mock.log_level or os.getenv("LOG_LEVEL") or "error"
assert(glue.indexof(__mock.log_level, { "error", "warn", "info", "debug", "trace" }),
    "__mock.log_level must be in [error, warn, info, debug, trace]")

__mock.trace = function(func_name, ...) -- return nil
    assert(type(func_name) == "string", "trace function name unknown")
    if __mock.log_level == "trace" then
        print(string.format("[TRACE] mock function '%s'", func_name), ...)
    end
    if type(__mock.callbacks.trace) == "function" then
        __mock.callbacks.trace(func_name, ...)
    end
end
---------------------------------------------------

---------------------------------------------------

local function repl(value)
    return string.gsub(value, "[0123456789abcdef]", "x")
end

local function rand(template)
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

__mock.rand_hash = function()
    return rand("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
end

__mock.rand_imc_token = function()
    return rand("ffffffffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
end

__mock.rand_token = function()
    return rand("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
end

__mock.rand_uuid = function()
    return rand("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx")
end

__mock.make_imc_token = function(mname, gid)
    assert(type(mname) == "string", "module name must be string type")
    assert(type(gid) == "string", "module group ID must be string type")
    local salt = "thisisimcsaltexamplefortest"
    local data = string.format("%s:%s:%s", gid, mname, salt)
    return string.format("ffffffff%s", glue.tohex(md5.sum(data)))
end

__mock.check_hash = function(hash)
    if type(hash) ~= "string" then return false end
    return repl(hash) == "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
end

__mock.check_imc_token = function(imc_token)
    if type(imc_token) ~= "string" then return false end
    if not string.find(imc_token, "^ffffffff") then return false end
    return repl(imc_token) == "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
end

__mock.check_token = function(token)
    if type(token) ~= "string" then return false end
    return repl(token) == "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
end

---------------------------------------------------
__mock.policy_id = __mock.policy_id or __mock.rand_hash()
assert(__mock.check_hash(__mock.policy_id), "__mock.policy_id must be hash format")
__mock.group_id = __mock.group_id or __mock.rand_hash()
assert(__mock.check_hash(__mock.group_id), "__mock.group_id must be hash format")
__mock.agent_id = __mock.agent_id or __mock.rand_hash()
assert(__mock.check_hash(__mock.agent_id), "__mock.agent_id must be hash format")
---------------------------------------------------

---------------------------------------------------
__mock.mock_token = __mock.rand_token()
__mock.module_token = __mock.rand_token()
__mock.module_imc_token = __mock.make_imc_token(__mock.module, __mock.group_id)
__mock.module_callbacks = {}
---------------------------------------------------

local function check_os_type(os_type)
    if type(os_type) ~= "string" then return false end
    return glue.indexof(os_type, { "windows", "linux", "darwin" }) ~= nil
end

local function check_os_name(os_name)
    if type(os_name) ~= "string" then return false end
    return os_name ~= ""
end

local function check_os_arch(os_arch)
    if type(os_arch) ~= "string" then return false end
    return glue.indexof(os_arch, { "386", "amd64" }) ~= nil
end

local function get_os_name_by_type(os_type)
    assert(check_os_type(os_type), "os_type must be valid")
    return ({
        windows = "Microsoft Windows 10.0",
        linux = "Ubuntu 20.04",
        darwin = "macOS 12.4",
    })[os_type]
end

---------------------------------------------------
__mock.os = __mock.os or {}
assert(type(__mock.os) == "table", "__mock.os must be table type")
__mock.os.type = __mock.os.type or ({
    Windows = "windows",
    Linux = "linux",
    OSX = "darwin",
})[ffi.os]
assert(check_os_type(__mock.os.type), "__mock.os.type must be in [windows, linux, darwin]")
__mock.os.name = __mock.os.name or get_os_name_by_type(__mock.os.type)
assert(check_os_name(__mock.os.name), "__mock.os.name must be valid string")
__mock.os.arch = __mock.os.arch or ({
    x86 = "386",
    x64 = "amd64",
})[ffi.arch]
assert(check_os_arch(__mock.os.arch), "__mock.os.arch must be in [386, amd64]")
---------------------------------------------------

__mock.check_domain = function(domain)
    if type(domain) ~= "string" then return false end
    return domain:match("^(%a%w+)%.?(%w+)$") ~= nil
end

__mock.check_ipv4 = function(ip)
    if type(ip) ~= "string" then return false end
    return ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") ~= nil
end

__mock.check_ipv4_with_port = function(tuple)
    if type(tuple) ~= "string" then return false end
    if tuple:match("^(%d+)%.(%d+)%.(%d+)%.(%d+):(%d+)$") == nil then return false end
    local port = tonumber(glue.collect(glue.gsplit(tuple, ":"))[2])
    return type(port) == "number" and port > 0 and port < 65536
end

__mock.check_port = function(sport)
    if type(sport) ~= "string" then return false end
    if sport:match("^(%d+)$") == nil then return false end
    local port = tonumber(sport)
    return type(port) == "number" and port > 0 and port < 65536
end

__mock.check_cidr = function(cidr)
    if type(cidr) ~= "string" then return false end
    return cidr:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)$") ~= nil
end

local function check_agent_version(aver)
    if type(aver) ~= "string" then return false end
    return aver:match("^v(%d+)%.(%d+)%.(%d+)%.(%d+)") ~= nil
end

local function check_agent_type(atype)
    if type(atype) ~= "string" then return false end
    return glue.indexof(atype, { "VXAgent", "Browser", "External" }) ~= nil
end

local function check_agent_host(ahost)
    if type(ahost) ~= "string" then return false end
    return ahost ~= ""
end

local function check_agent_conn(conn)
    assert(type(conn) == "table", "agent conn must be table type")
    assert(__mock.check_hash(conn.id), "agent conn id must be hash format")
    assert(__mock.check_ipv4_with_port(conn.ip), "agent conn ip must be IPv4 with port format")
    assert(type(conn.ips) == "table", "agent conn ips must be table type")
    assert(glue.indexof(false, glue.map(conn.ips, function(_, ip)
        return __mock.check_cidr(ip)
    end)) == nil, "agent conn ips each record must be CIDR format")
    assert(__mock.check_hash(conn.gid), "agent conn group id must be hash format")
    assert(check_agent_version(conn.ver), "agent conn version must be semver format")
    assert(__mock.check_token(conn.src), "agent conn src must be vxproto token format")
    assert(__mock.check_token(conn.dst), "agent conn dst must be vxproto token format")
    assert(check_agent_type(conn.type), "agent conn type must be in [VXAgent, Browser, External]")
    assert(check_agent_host(conn.host), "agent conn host name must be valid format")
    assert(check_os_type(conn.os_type), "agent conn os type must be in [windows, linux, darwin]")
    assert(check_os_name(conn.os_name), "agent conn os name must be valid string")
    assert(check_os_arch(conn.os_arch), "agent conn os arch must be in [386, amd64]")
    return true
end

---------------------------------------------------
__mock.agent_conn = __mock.agent_conn or {}
assert(type(__mock.agent_conn) == "table", "__mock.agent_conn must be table type")
__mock.agent_conn = {
    id      = __mock.agent_conn.id or __mock.agent_id,
    ip      = __mock.agent_conn.ip or string.format("127.0.0.1:%d", math.random(32768, 65535)),
    ips     = __mock.agent_conn.ips or { "127.0.0.1/8" },
    gid     = __mock.agent_conn.gid or __mock.group_id,
    ver     = __mock.agent_conn.ver or "v1.0.0.0",
    src     = __mock.agent_conn.src or __mock.module_token,
    dst     = __mock.agent_conn.dst or __mock.mock_token,
    type    = __mock.agent_conn.type or "VXAgent",
    host    = __mock.agent_conn.host or "mock.local",
    os_type = __mock.agent_conn.os_type or "windows",
    os_name = __mock.agent_conn.os_name or get_os_name_by_type(__mock.agent_conn.os_type or "windows"),
    os_arch = __mock.agent_conn.os_arch or "amd64",
}
assert(check_agent_conn(__mock.agent_conn), "__mock.agent_conn must be valid conn structure")
---------------------------------------------------

local function check_server_conn(conn)
    assert(type(conn) == "table", "server conn must be table type")
    assert(glue.indexof(conn.scheme, { "ws", "wss" }),
        "server conn scheme must be in [ws, wss]")
    assert(__mock.check_ipv4(conn.host) or __mock.check_domain(conn.host),
        "server conn host must be IPv4 or Domain format")
    assert(__mock.check_port(conn.port), "server conn port must be number format")
    assert(type(conn.ips) == "table", "server conn ips must be table type")
    assert(glue.indexof(false, glue.map(conn.ips, function(_, ip)
        return __mock.check_ipv4(ip)
    end)) == nil, "server conn ips each record must be IPv4 format")
    return true
end

---------------------------------------------------
__mock.server_conn = __mock.server_conn or {}
assert(type(__mock.server_conn) == "table", "__mock.server_conn must be table type")
__mock.server_conn = {
    scheme = __mock.server_conn.scheme or "wss",
    host   = __mock.server_conn.host or "server.local",
    port   = __mock.server_conn.port or "8443",
    ips    = __mock.server_conn.ips or { "127.0.0.1" },
}
assert(check_server_conn(__mock.server_conn), "__mock.server_conn must be valid conn structure")
---------------------------------------------------

local function patch_agent_conn(conn)
    assert(type(conn) == "table", "agent conn must be table type")
    local id = conn.id or __mock.rand_hash()
    local ip = conn.ip or string.format("127.0.0.1:%d", math.random(32768, 65535))
    local os_type = get_os_name_by_type(conn.os_type or "windows")
    return {
        id      = id,
        ip      = ip,
        ips     = conn.ips or { string.format("%s/8", glue.gsplit(tostring(ip) or "127.0.0.1", ":")()) },
        gid     = conn.gid or __mock.group_id,
        ver     = conn.ver or "v1.0.0.0",
        src     = conn.src or __mock.rand_token(),
        dst     = conn.dst or __mock.rand_token(),
        type    = conn.type or "VXAgent",
        host    = conn.host or string.format("%s.local", id),
        os_type = conn.os_type or "windows",
        os_name = conn.os_name or os_type,
        os_arch = conn.os_arch or "amd64",
    }
end

local function check_agent_route(route)
    assert(type(route) == "table", "agent route must be table type")
    assert(__mock.check_token(route.src), "agent route src must be vxproto token format")
    assert(__mock.check_token(route.dst), "agent route dst must be vxproto token format")
    return true
end

local function check_module_name(mname)
    if type(mname) ~= "string" then return false end
    return mname ~= ""
end

local function check_module(module)
    assert(type(module) == "table", "module struct must be table type")
    assert(check_module_name(module.name), "module name must be valid string")
    assert(__mock.check_hash(module.gid), "module group id must be hash format")
    assert(__mock.check_imc_token(module.token), "module token must be imc token format")
    return true
end

local function patch_module(module)
    assert(type(module) == "table", "module struct must be table type")
    local name = module.name
    local gid = module.gid or __mock.group_id
    return {
        name = name,
        gid = gid,
        token = __mock.make_imc_token(name, gid),
    }
end

---------------------------------------------------
__mock.agents = __mock.agents or {}
assert(type(__mock.agents) == "table", "__mock.agents must be table type")
__mock.agents = glue.map(__mock.agents, function(_, conn)
    return patch_agent_conn(conn)
end)
assert(glue.indexof(false, glue.map(__mock.agents, function(_, conn)
    return check_agent_conn(conn)
end)) == nil, "__mock.agents each record must be valid conn structure")
table.insert(__mock.agents, 1, __mock.agent_conn)

__mock.routes = __mock.routes or {}
assert(type(__mock.routes) == "table", "__mock.routes must be table type")
assert(glue.indexof(false, glue.map(__mock.routes, function(_, route)
    return check_agent_route(route)
end)) == nil, "__mock.routes each record must be valid route structure")

__mock.modules = __mock.modules or {}
assert(type(__mock.modules) == "table", "__mock.modules must be table type")
__mock.modules = glue.map(__mock.modules, function(_, module)
    return patch_module(module)
end)
assert(glue.indexof(false, glue.map(__mock.modules, function(_, module)
    return check_module(module)
end)) == nil, "__mock.modules each record must be valid module structure")
table.insert(__mock.modules, 1, {
    name  = __mock.module,
    gid   = __mock.group_id,
    token = __mock.module_imc_token,
})

local groups = {}
glue.map(__mock.modules, function(_, k)
    groups[k.gid] = true
end)
__mock.groups = {}
glue.map(groups, function(tk)
    table.insert(__mock.groups, tk)
end)
---------------------------------------------------

local function copy_file(src, dst, force)
    local f, err = io.open(src, 'rb')
    if not f then return nil, err end

    local t, ok
    if not force then
        t = io.open(dst, 'rb')
        if t then
            f:close()
            t:close()
            return nil, "file alredy exists"
        end
    end

    t, err = io.open(dst, 'w+b')
    if not t then
        f:close()
        return nil, err
    end

    local CHUNK_SIZE = 4096
    while true do
        local chunk = f:read(CHUNK_SIZE)
        if not chunk then break end
        ok, err = t:write(chunk)
        if not ok then
            t:close()
            f:close()
            return nil, err or "can not write"
        end
    end

    t:close()
    f:close()
    collectgarbage("collect")
    return true
end

local copy_dir
copy_dir = function(base, src, dst)
    if lfs.attributes(src, "mode") ~= "directory" then return end
    for file in lfs.dir(src) do
        local file_path = combine_path(src, file)
        if not glue.indexof(file, { ".", ".." }) then
            if lfs.attributes(file_path, "mode") == "file" then
                copy_file(combine_path(src, file), combine_path(dst, file), true)
            elseif lfs.attributes(file_path, "mode") == "directory" then
                local base_dir = combine_path(base, file)
                local src_dir = combine_path(src, file)
                local dst_dir = combine_path(dst, file)
                lfs.mkdir(dst_dir)
                copy_dir(base_dir, src_dir, dst_dir)
            end
        end
    end
end

local function read_file(file_path)
    local file_data
    local fhandle = io.open(file_path, "rb")
    if nil ~= fhandle then
        file_data = fhandle:read("*all")
        fhandle:close()
    end
    return file_data
end

local read_dir
read_dir = function(files, base, dir)
    for file in lfs.dir(dir) do
        local file_path = combine_path(dir, file)
        if not glue.indexof(file, { ".", "..", "data", "clibs" }) then
            if lfs.attributes(file_path, "mode") == "file" then
                files[combine_path(base, file)] = read_file(file_path)
            elseif lfs.attributes(file_path, "mode") == "directory" then
                read_dir(files, combine_path(base, file), file_path)
            end
        end
    end
    return files
end

---------------------------------------------------
-- MOCK load files into memory and copy it into tmp
---------------------------------------------------
__mock.files = read_dir({}, "", __mock.module_code_path)
copy_dir("", combine_path(__mock.module_code_path, "data"), combine_path(__mock.tmpdir, "data"))
local clibs = combine_path(__mock.module_code_path, "clibs", __mock.os.type, __mock.os.arch)
copy_dir("", clibs, __mock.tmpdir)
---------------------------------------------------

---------------------------------------------------
-- MOCK load config files into memory as a strings
---------------------------------------------------
local config = read_dir({}, "", __mock.module_conf_path)
__mock.config = {}
glue.map(config, function(name, conf)
    __mock.config[glue.gsplit(name, "%.")()] = conf
end)

__mock.module_info = cjson.decode(__mock.info) or {}
__mock.module_info.tags = nil
__mock.module_info.system = nil
__mock.module_info.name = __mock.module
__mock.module_info.version = __mock.version
__mock.module_info.group_id = __mock.group_id
__mock.module_info.policy_id = __mock.policy_id
local config_json = cjson.decode(read_file(combine_path(__mock.base_path, "config.json")))
glue.map(config_json, function(_, mod)
    local name = mod.name
    local version = string.format("%d.%d.%d", mod.version.major, mod.version.minor, mod.version.patch)
    if name == __mock.module and version == __mock.version then
        glue.merge(__mock.module_info, mod)
    end
end)
local current_date = os.date("%Y-%m-%d %H:%M:%S", os.time())
glue.merge(__mock.module_info, {
    state              = "draft",
    last_module_update = current_date,
    last_update        = current_date,
})
__mock.config.module_info = cjson.encode(__mock.module_info)

__mock.sec = __mock.sec or {}
assert(type(__mock.sec) == "table", "__mock.sec must be table type")
assert(glue.indexof(false, glue.map(__mock.sec, function(tk)
    return type(tk) == "string"
end)) == nil, "__mock.sec each record key must be string type")
assert(glue.indexof(false, glue.map(__mock.sec, function(_, tv)
    return type(tv) == "string"
end)) == nil, "__mock.sec each record value must be string type")
---------------------------------------------------

---------------------------------------------------
-- MOCK load and parse args.json file into memory
---------------------------------------------------
local args_file_path = combine_path(__mock.module_code_path, "args.json")
local args_file_data = read_file(args_file_path)
assert(type(args_file_data) == "string", "args.json file must be exist")
local args_file_json = cjson.decode(args_file_data)
assert(type(args_file_json) == "table", "args.json file must be JSON format")
for k, v in pairs(args_file_json) do
    assert(type(k) == "string", "args.json root object must contain string keys")
    assert(type(v) == "table", "args.json root object must contain table values")
    for i, vv in ipairs(v) do
        assert(type(i) == "number" and type(vv) == "string", "args.json values must contain array of strings")
    end
end
__mock.args = args_file_json
---------------------------------------------------

---------------------------------------------------
-- MOCK setup package path to load module libraries
---------------------------------------------------
__mock.initial_path = package.path
package.path = table.concat({
    package.path,
    combine_path(__mock.module_code_path, "?.lua"),
    combine_path(__mock.module_code_path, "?", "init.lua"),
}, ";")
---------------------------------------------------

---------------------------------------------------
-- MOCK user code section and vars to test module
---------------------------------------------------
local function require_module()
    local module_main = 'main'
    local module_name = __mock.module .. '.' .. __mock.version

    local searchers, loaded = package.searchers, package.loaded
    local module = loaded[module_name]
    if module then
        return module
    end

    local msg = {}
    local loader, param
    for _, searcher in ipairs(searchers) do
        loader, param = searcher(module_main)
        if type(loader) == "function" then
            break
        end
        if type(loader) == "string" then
            -- `loader` is actually an error message
            msg[#msg + 1] = loader
        end
        loader = nil
    end
    if loader == nil then
        local error_message = ("couldn't find '%s'.lua of '%s' module: %s"):format(module_main, module_name,
            table.concat(msg))
        error(error_message, 2)
    end
    local res = loader(module_name, param)
    if res ~= nil then
        loaded[module_name] = res
    elseif not loaded[module_name] then
        loaded[module_name] = true
    end

    return loaded[module_name]
end

__mock.stage.coro = __mock.stage.coro or coroutine.create(
    function()
        local result = require_module()

        package.path = __mock.initial_path
        __mock.cwd = __mock.initial_cwd
        lfs.chdir(__mock.cwd)

        assert("success" == result, "module failed: " .. result)
    end
)
__mock.callbacks = __mock.callbacks or {
    data = function(self, dst, src, data)
        self:add_context("data", { dst = dst, src = src, data = cjson.decode(data) or data })
        return true
    end,
    file = function(self, dst, src, path, name)
        self:add_context("file", { dst = dst, src = src, path = path, data = glue.readfile(path), name = name })
        return true
    end,
    text = function(self, dst, src, data, name)
        self:add_context("text", { dst = dst, src = src, data = cjson.decode(data) or data, name = name })
        return true
    end,
    msg = function(self, dst, src, data, mtype)
        self:add_context("msg", { dst = dst, src = src, data = cjson.decode(data) or data, mtype = mtype })
        return true
    end,
    action = function(self, dst, src, data, name)
        self:add_context("action", { dst = dst, src = src, data = cjson.decode(data) or data, name = name })
        return true
    end,
    push_event = function(self, aid, event)
        self:add_context("event", { aid = aid, event = cjson.decode(event) })
        return true
    end,
}
assert(type(__mock.callbacks) == "table", "__mock.callbacks must be table type")
for name, callback in pairs(__mock.callbacks) do
    assert(glue.indexof(name, { "data", "file", "text", "msg", "action", "push_event", "trace" }),
        "__mock.callbacks table key must be in [data, file, text, msg, action, push_event, trace]")
    assert(type(callback) == "function", "__mock.callbacks table value must be function type")
end
---------------------------------------------------

---------------------------------------------------
-- MOCK public API which can be using in scenario
---------------------------------------------------
__mock.test = function(name, f)
    print(string.rep("-", 50))
    print("-- TEST " .. name)
    print(string.rep("-", 50))
    local scenario_co = coroutine.create(f)
    -- NOTE: coroutine is needed here cause api.send_* calls in the main execution
    -- can lead to await's from module logic that need to be handled
    while coroutine.status(scenario_co) == "suspended" do
        local result, err = coroutine.resume(scenario_co)
        assert(result, err)
    end
    print(string.rep("-", 50))
    print()
end

__mock.module_stop = function(self)
    self.is_closed = true
    while coroutine.status(self.stage.coro) == "suspended" do
        local result, err = coroutine.resume(self.stage.coro, self)
        assert(result, err)
    end
end

__mock.module_start = function(self)
    self.is_closed = false
    if coroutine.status(self.stage.coro) == "suspended" then
        local result, err = coroutine.resume(self.stage.coro, self)
        assert(result, err)
        return true
    end
    return false
end

__mock.module_update_config = function(self, conf)
    local _, _ = self, conf
end

__mock.add_context = function(self, etype, data)
    local _ = self
    self.trace("__mock.add_context", etype, data)
    self.stage.ctx[etype] = self.stage.ctx[etype] or {}
    table.insert(self.stage.ctx[etype], data)
end

__mock.pop_from_context = function(self, etype, filter)
    self.trace("__mock.get_from_context", etype)
    if not self.stage.ctx[etype] then return nil end

    for i, data in ipairs(self.stage.ctx[etype]) do
        local no_errors, is_correct = pcall(filter, data)
        if no_errors and is_correct then
            table.remove(self.stage.ctx[etype], i)
            return data
        end
    end
end

__mock.clear_expectations = function(self)
    self.stage.ctx = {}
end

__mock.expect = function(self, etype, filter)
    self.trace("__mock.expect", etype)
    local start_time = os.time()
    while true do
        local obj = self:pop_from_context(etype, filter)
        if obj ~= nil then
            self.stage.time = os.time()
            return true
        end

        local elapsed_time = os.difftime(os.time(), self.stage.time)
        local check_elapsed_time = os.difftime(os.time(), start_time)
        -- TODO: need to have global timeout but also check local for each expectation waiting period
        if self.timeout ~= 0 and elapsed_time >= self.timeout then
            return false, "expectation timed out after " .. check_elapsed_time .. " seconds"
        end
        if coroutine.status(self.stage.coro) == "dead" then
            return false, "coroutine is dead"
        end
        local status, _ = coroutine.resume(self.stage.coro, self)
        if not status then
            return false, "failed to resume coroutine"
        end
    end
end

__mock.disconnect = function(self)
    local _ = self
end

__mock.connect = function(self)
    local _ = self
end

__mock.send_data = function(self, src, dst, data)
    local _ = dst
    if self.module_callbacks.data ~= nil then
        return self.module_callbacks.data(src, data)
    end
    return false
end

__mock.send_file = function(self, src, dst, path, name)
    local _ = dst
    if self.module_callbacks.file ~= nil then
        return self.module_callbacks.file(src, path, name)
    end
    return false
end

__mock.send_text = function(self, src, dst, text, name)
    local _ = dst
    if self.module_callbacks.text ~= nil then
        return self.module_callbacks.text(src, text, name)
    end
    return false
end

__mock.send_msg = function(self, src, dst, msg, mtype)
    local _ = dst
    if self.module_callbacks.msg ~= nil then
        return self.module_callbacks.msg(src, msg, mtype)
    end
    return false
end

__mock.send_action = function(self, src, dst, data, name)
    local _ = dst
    if self.module_callbacks.action ~= nil then
        return self.module_callbacks.action(src, data, name)
    end
    return false
end

__mock.send_control = function(self, cmtype, data)
    if self.module_callbacks.control ~= nil then
        return self.module_callbacks.control(cmtype, data)
    end
    return false
end
---------------------------------------------------
