require("engine")
local bit     = require("bit")
local ffi     = require("ffi")
local lfs     = require("lfs")
local luapath = require("path")

local lk32
if ffi.os == "Windows" then
    lk32 = require("waffi.windows.kernel32")
else
    ffi.cdef[[
        typedef uint32_t pid_t;

        int kill( pid_t proc_id, int sig );

        pid_t getpid();
    ]]
end

-- API for different OS types
local api = {windows = {}, linux = {}, osx = {}}
-- API for current OS type
local process_api

local function run_callback_safe(callback, args)
    local result, need_stop = pcall(callback, args)
    if not result then
        __log.error("callback failure")
        return false
    end
    return need_stop
end

if ffi.os == "Windows" then

    --[[
        Call given callback for each process
        Callback arg table: {
            pid - process id
            name - process name
            parent_pid - process parent id
            path - process image path
        }
        Callback return value:
            bool - whether to stop iteration
    --]]
    function api.windows.for_each_process(callback)
        if not callback then
            __log.error("no callback provided")
            return
        end

        local proc_entry = ffi.new("PROCESSENTRY32[1]")
        proc_entry[0].dwSize = ffi.sizeof("PROCESSENTRY32")

        local TH32CS_SNAPPROCESS = 0x00000002
        local snap_handle = lk32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)

        if (lk32.Process32First(snap_handle, proc_entry[0]) == 1) then
            while (lk32.Process32Next(snap_handle, proc_entry[0]) == 1) do
                local pid = tonumber(proc_entry[0].th32ProcessID)
                local args = {
                    pid = pid,
                    name = ffi.string(proc_entry[0].szExeFile),
                    parent_pid = tonumber(proc_entry[0].th32ParentProcessID),
                    path = api.windows.get_process_path(pid),
                }

                if (run_callback_safe(callback, args)) then
                    break
                end
            end
        else
            __log.error("failed to get info from snapshot")
        end
        if snap_handle ~= ffi.NULL then
            lk32.CloseHandle(snap_handle)
        end
    end

    function api.windows.get_last_error()
        local err = lk32.GetLastError()
        __log.debugf("winapi last err: %d", tonumber(err))
        return err
    end

    function api.windows.get_process_handle(pid)
        local SYNCHRONIZE = 0x00100000
        local handle = lk32.OpenProcess(bit.bor(lk32.PROCESS_QUERY_LIMITED_INFORMATION, lk32.PROCESS_TERMINATE,
            lk32.PROCESS_VM_READ, SYNCHRONIZE
        ), false, pid)
        if handle == ffi.NULL then
            return nil, api.windows.get_last_error()
        end
        return handle, nil
    end

    function api.windows.kill_process(pid)
        local handle, error = api.windows.get_process_handle(pid)
        if error then
            return false
        end
        if lk32.TerminateProcess(handle, 0) == 0 then
            return false
        end
        lk32.WaitForSingleObject(handle, 0)
        return true
    end

    -- by using less priveleged handle we can get path for any process
    -- GetModuleFileNameExA didn't work on w7x64
    function api.windows.get_process_path(pid)
        local proc_handle, err = lk32.OpenProcess(lk32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
        if proc_handle == nil then
            return "", err
        end
        local max_path = lk32.MAX_PATH
        local filename = ffi.new("char[?]", max_path)
        local size = ffi.new("DWORD[1]", 2048)
        if lk32.QueryFullProcessImageNameA(proc_handle, 0, filename, size) ~= 1 then
            lk32.CloseHandle(proc_handle)
            __log.errorf("failed to get process path for pid '%d'", pid)
            return "", "failed to get process path"
        end
        lk32.CloseHandle(proc_handle)
        local path = ffi.string(filename, size[0])
        return path, nil
    end

    function api.windows.update_agent_info()
        local aid, apath
        aid = tonumber(lk32.GetCurrentProcessId())
        apath = api.windows.get_process_path(aid):lower()
        return aid, apath
    end

else

    function api.linux.get_process_path(pid)
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

    function api.linux.kill_process(pid)
        return ffi.C.kill(pid, 9) == 0
    end

    -- might be a number or "self"
    local function get_process_info_linux(proc_id_str)
        assert(type(proc_id_str) == "string")
        local file = io.open("/proc/" .. proc_id_str .. "/stat", "r")
        if file ~= nil then
            local info = file:read()
            local _pid, _ppid = info:match("(%S+) %S+ %S+ (%S+)")
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

    function api.linux.for_each_process(callback)
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

            imagepath, err = api.linux.get_process_path(file)
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

    function api.linux.update_agent_info()
        local aid, apath
        aid = get_process_info_linux("self")
        apath = api.linux.get_process_path("self")
        return aid, apath
    end

    function api.osx.get_process_path(pid)
        assert(type(pid) == "number", "PID should a number")
        local cmd =  "/bin/ps o comm=\"\" " .. tostring(pid) -- comm for osx, command for linux
        local cmd_handle = assert(io.popen(cmd, "r"), "failed to call io.popen")
        local imagepath = assert(cmd_handle:read("*all"), "failed to read from pipe")
        imagepath = string.gsub(imagepath, '^%s*(.-)%s*$', '%1')
         __log.debugf("handlers.osx.get_process_path for '%d' -> '%s'", pid, imagepath)
        cmd_handle:close()
        if imagepath ~= nil and imagepath ~= "" then
            return imagepath, nil
        else
            return nil, "Not found"
        end
    end

    function api.osx.kill_process(pid)
        return api.linux.kill_process(pid)
    end

    function api.osx.for_each_process(callback)
        -- TODO move this to sysctl syscall to retrieve the process table.
        local cmd = "/bin/ps axo pid=\"\",ppid=\"\",comm=\"\""  -- comm for osx, command for linux
        local cmd_handle = assert(io.popen(cmd, "r"), "failed to call io.popen")
        local cmd_res = assert(cmd_handle:read("*all"), "failed to read from pipe")
        cmd_handle:close()
        for str in string.gmatch(cmd_res, "([^"..'\n'.."]+)") do
            local pid, parent_pid, imagepath = str:match("%s*(%S+)%s+(%S+) ([^.]+)")
            if (imagepath ~= nil) then
                imagepath = imagepath:gsub('^%s*(.-)%s*$', '%1')
            end
            __log.debugf("api.osx.for_each_process PID -> '%s' PPID -> '%s' IMAGE -> '%s", pid, parent_pid , imagepath)
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

    function api.osx.update_agent_info()
        local aid, apath
        aid = ffi.C.getpid()
        apath = api.osx.get_process_path(aid)
        return aid, apath
    end

end

if ffi.os == "Windows" then
    process_api = api.windows
elseif ffi.os == "Linux" then
    process_api = api.linux
elseif ffi.os == "OSX" then
    process_api = api.osx
else
    __log.error("unsupported OS")
    return
end

return process_api
