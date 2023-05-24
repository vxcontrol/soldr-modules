local ffi = require("ffi")
local luapath = require("path")
local glue = require("glue")

local process_api_linux = require("process_api_linux")

local process_api = {}

local function run_callback_safe(callback, args)
    local result, retval1 = glue.pcall(callback, args)
    if not result then
        __log.error("callback failure: " .. retval1)
        return false
    end
    return retval1
end

function process_api.get_process_path(pid)
    assert(type(pid) == "number", "PID should a number")
    local cmd = "/bin/ps o comm=\"\" " .. tostring(pid) -- comm for osx, command for linux
    local cmd_handle = assert(io.popen(cmd, "r"), "failed to call io.popen")
    local imagepath = assert(cmd_handle:read("*all"), "failed to read from pipe")
    imagepath = string.gsub(imagepath, "^%s*(.-)%s*$", "%1")
    __log.debugf("handlers.osx.get_process_path for '%d' -> '%s'", pid, imagepath)
    cmd_handle:close()
    if imagepath ~= nil and imagepath ~= "" then
        return imagepath, nil
    else
        return nil, "Not found"
    end
end

function process_api.for_each_process(callback)
    -- TODO move this to sysctl syscall to retrieve the process table.
    local cmd = "/bin/ps axo pid=\"\",ppid=\"\",comm=\"\"" -- comm for osx, command for linux
    local cmd_handle = assert(io.popen(cmd, "r"), "failed to call io.popen")
    local cmd_res = assert(cmd_handle:read("*all"), "failed to read from pipe")
    cmd_handle:close()
    for str in string.gmatch(cmd_res, "([^" .. "\n" .. "]+)") do
        local pid, parent_pid, imagepath = str:match("%s*(%S+)%s+(%S+) ([^.]+)")
        if (imagepath ~= nil) then
            imagepath = imagepath:gsub("^%s*(.-)%s*$", "%1")
        end
        __log.debugf("process_api.for_each_process PID -> '%s' PPID -> '%s' IMAGE -> '%s", pid, parent_pid, imagepath)
        if pid ~= nil and parent_pid ~= nil and imagepath ~= nil then
            local args = {
                pid = tonumber(pid),
                name = luapath.file(imagepath),
                parent_pid = tonumber(parent_pid),
                path = imagepath,
            }

            if (run_callback_safe(callback, args)) then
                return
            end
        end
    end
end

function process_api.update_agent_info()
    local aid, apath
    aid = ffi.C.getpid()
    apath = process_api.get_process_path(aid)
    return aid, apath
end

process_api.kill_process = process_api_linux.kill_process

return process_api
