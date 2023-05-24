local bit = require("bit")
local ffi = require("ffi")
local glue = require("glue")
local lk32 = require("waffi.windows.kernel32")

local process_api = {}

local win_const = {
    TH32CS_SNAPPROCESS = 0x00000002,
    SYNCHRONIZE = 0x00100000,
    INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1),
}

ffi.cdef [[
    typedef struct tagPROCESSENTRY32W {
        DWORD     dwSize;
        DWORD     cntUsage;
        DWORD     th32ProcessID;
        ULONG_PTR th32DefaultHeapID;
        DWORD     th32ModuleID;
        DWORD     cntThreads;
        DWORD     th32ParentProcessID;
        LONG      pcPriClassBase;
        DWORD     dwFlags;
        WCHAR     szExeFile[MAX_PATH];
    } PROCESSENTRY32W;

    BOOL Process32FirstW( HANDLE hSnapshot, LPPROCESSENTRY32W lppe);
    BOOL Process32NextW(  HANDLE hSnapshot, LPPROCESSENTRY32W lppe);
]]

local function run_callback_safe(callback, args)
    local result, retval1 = glue.pcall(callback, args)
    if not result then
        __log.error("callback failure: " .. retval1)
        return false
    end
    return retval1
end

function process_api.create_buffer(size)
    return size > 0 and
        { ptr = ffi.new("char[?]", size), size = size } or
        { ptr = nil, size = 0 }
end

function process_api.to_utf8(wstr, buffer)
    if wstr == ffi.NULL then return "" end
    buffer = buffer ~= nil and buffer or process_api.create_buffer(0)
    local size = buffer.ptr and ffi.C.WideCharToMultiByte(lk32.CP_UTF8, 0, wstr, -1, buffer.ptr, buffer.size, nil, nil) or 0
    if size == 0 then
        size = ffi.C.WideCharToMultiByte(lk32.CP_UTF8, 0, wstr, -1, nil, 0, nil, nil)
        if size == 0 then return "" end
        buffer = process_api.create_buffer(size)
        size = ffi.C.WideCharToMultiByte(lk32.CP_UTF8, 0, wstr, -1, buffer.ptr, buffer.size, nil, nil)
    end
    local utf8_string = size > 0 and ffi.string(buffer.ptr) or ""
    return utf8_string, size
end

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
function process_api.for_each_process(callback)
    if not callback then
        __log.error("no callback provided")
        return
    end

    local proc_entry = ffi.new("PROCESSENTRY32W[1]")
    proc_entry[0].dwSize = ffi.sizeof("PROCESSENTRY32W")
    local snap_handle = lk32.CreateToolhelp32Snapshot(win_const.TH32CS_SNAPPROCESS, 0)
    assert(snap_handle ~= win_const.INVALID_HANDLE_VALUE, "failed to get list of processes")

    local name_buffer = process_api.create_buffer(1024)

    if (lk32.Process32FirstW(snap_handle, proc_entry[0]) == 1) then
        while (lk32.Process32NextW(snap_handle, proc_entry[0]) == 1) do
            local pid = tonumber(proc_entry[0].th32ProcessID)
            local args = {
                pid = pid,
                name = process_api.to_utf8(proc_entry[0].szExeFile, name_buffer),
                parent_pid = tonumber(proc_entry[0].th32ParentProcessID),
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

function process_api.get_last_error()
    local err = lk32.GetLastError()
    __log.debugf("winapi last err: %d", tonumber(err))
    return err
end

function process_api.get_process_handle(pid)
    local flags = bit.bor(lk32.PROCESS_QUERY_LIMITED_INFORMATION, lk32.PROCESS_TERMINATE, lk32.PROCESS_VM_READ, win_const.SYNCHRONIZE)
    local handle = lk32.OpenProcess(flags, false, pid)
    if handle == ffi.NULL then
        return nil, process_api.get_last_error()
    end
    return handle, nil
end

function process_api.kill_process(pid)
    local handle, error = process_api.get_process_handle(pid)
    if error then
        return false
    end
    if lk32.TerminateProcess(handle, 0) == 0 then
        return false
    end
    lk32.WaitForSingleObject(handle, lk32.INFINITE)
    return true
end

-- by using less priveleged handle we can get path for any process
-- GetModuleFileNameExA didn't work on w7x64
function process_api.get_process_path(pid)
    local process_handle, err = lk32.OpenProcess(lk32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
    if process_handle == nil then
        return "", err
    end
    local max_path = lk32.MAX_PATH
    local filename = ffi.new("wchar_t[?]", max_path)
    local filename_buffer = process_api.create_buffer(1024)
    local size = ffi.new("DWORD[1]", 2048)
    if lk32.QueryFullProcessImageNameW(process_handle, 0, filename, size) ~= 1 then
        lk32.CloseHandle(process_handle)
        return "", "failed to get process path"
    end
    lk32.CloseHandle(process_handle)
    local path = process_api.to_utf8(filename, filename_buffer)
    return path, nil
end

function process_api.update_agent_info()
    local aid, apath
    aid = tonumber(lk32.GetCurrentProcessId())
    apath = process_api.get_process_path(aid):lower()
    return aid, apath
end

return process_api
