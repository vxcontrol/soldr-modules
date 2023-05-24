local ffi = require("ffi")
local lfs = require("lfs")
local luapath = require("path")
local glue = require("glue")

local process_api = {}

local wait_kill_sleep = 300

ffi.cdef [[
    typedef uint32_t pid_t;
    int kill(pid_t proc_id, int sig);
    pid_t getpid();

    typedef struct pollfd
    {
        int fd;
        short events;
        short revents;
    } pollfd_t;

    typedef uint32_t nfds_t;
    int poll(struct pollfd *fds, nfds_t nfds, int timeout);
]]

local function run_callback_safe(callback, args)
    local result, retval1 = glue.pcall(callback, args)
    if not result then
        __log.error("callback failure: " .. retval1)
        return false
    end
    return retval1
end

function process_api.get_process_path(pid)
    local attrs = lfs.symlinkattributes(string.format("/proc/%s/exe", pid))
    if type(attrs) ~= "table" then
        return "", "not found"
    elseif attrs["mode"] ~= "link" then
        return "", "invalid process id"
    elseif type(attrs["target"]) ~= "string" then
        return "", "permission deny"
    end
    return attrs["target"]
end

function process_api.kill_process(pid)
    local SIGNOP = 0
    local SIGKILL = 9

    if ffi.C.kill(pid, SIGKILL) ~= 0 then
        return false
    end

    while ffi.C.kill(pid, SIGNOP) == 0 do
        ffi.C.poll(nil, 0, wait_kill_sleep)
    end

    return true
end

-- might be a number or "self"
local function get_process_info_linux(proc_id_str)
    assert(type(proc_id_str) == "string")
    local file = io.open("/proc/" .. proc_id_str .. "/stat", "r")
    if file ~= nil then
        local info = file:read()
        local _pid, _ppid = string.match(info or "", "(%S+) %S+ %S+ (%S+)")
        local pid = tonumber(_pid)
        local parent_pid = tonumber(_ppid)
        file:close()
        if pid ~= nil and parent_pid ~= nil then
            return pid, parent_pid, false
        else
            return nil, nil, true
        end
    end

    return nil, nil, true
end

function process_api.for_each_process(callback)
    if not callback then
        error("no callback provided")
    end

    local imagepath, err
    for file in lfs.dir("/proc") do
        if file == "." or file == ".." or tonumber(file) == nil then
            goto continue
        end

        local attrs = lfs.attributes(string.format("/proc/%s", file))
        if type(attrs) ~= "table" or attrs["mode"] ~= "directory" then
            -- __log.debugf("Wrong attributes for '%s'", file)
            goto continue
        end

        imagepath, err = process_api.get_process_path(file)
        if err then
            -- __log.debugf("Failed to get process path for '%s': %s", file, err)
            goto continue
        end

        local pid, parent_pid
        local name = luapath.file(imagepath)
        pid, parent_pid, err = get_process_info_linux(file)
        if err then
            -- __log.debugf("Failed to get process info for '%s': %s", file, err)
            goto continue
        end

        if pid == nil or parent_pid == nil then
            __log.info("Invalid PID: -> " .. pid .. " expected ->" .. file)
        end

        local args = {
            pid = tonumber(pid),
            name = name,
            parent_pid = tonumber(parent_pid),
            path = imagepath,
        }

        if (run_callback_safe(callback, args)) then
            return
        end

        ::continue::
    end
end

function process_api.update_agent_info()
    local aid, apath
    aid = get_process_info_linux("self")
    apath = process_api.get_process_path("self")
    return aid, apath
end

return process_api
