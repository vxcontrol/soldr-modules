require("yaci")
require("strict")
local ffi      = require("ffi")
local kernel32 = require("waffi.windows.kernel32")

CProcess = newclass("CProcess")

ffi.cdef[[
    typedef struct _JOBOBJECT_BASIC_LIMIT_INFORMATION {
        LARGE_INTEGER PerProcessUserTimeLimit;
        LARGE_INTEGER PerJobUserTimeLimit;
        DWORD         LimitFlags;
        SIZE_T        MinimumWorkingSetSize;
        SIZE_T        MaximumWorkingSetSize;
        DWORD         ActiveProcessLimit;
        ULONG_PTR     Affinity;
        DWORD         PriorityClass;
        DWORD         SchedulingClass;
    } JOBOBJECT_BASIC_LIMIT_INFORMATION, *PJOBOBJECT_BASIC_LIMIT_INFORMATION;

    typedef struct _JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        IO_COUNTERS                       IoInfo;
        SIZE_T                            ProcessMemoryLimit;
        SIZE_T                            JobMemoryLimit;
        SIZE_T                            PeakProcessMemoryUsed;
        SIZE_T                            PeakJobMemoryUsed;
    } JOBOBJECT_EXTENDED_LIMIT_INFORMATION, *PJOBOBJECT_EXTENDED_LIMIT_INFORMATION;

    HANDLE CreateJobObjectW(
        LPSECURITY_ATTRIBUTES lpJobAttributes,
        LPCWSTR               lpName
    );

    BOOL CreateProcessW(
        LPCWSTR               lpApplicationName,
        LPWSTR                lpCommandLine,
        LPSECURITY_ATTRIBUTES lpProcessAttributes,
        LPSECURITY_ATTRIBUTES lpThreadAttributes,
        BOOL                  bInheritHandles,
        DWORD                 dwCreationFlags,
        LPVOID                lpEnvironment,
        LPCWSTR               lpCurrentDirectory,
        LPSTARTUPINFOW        lpStartupInfo,
        LPPROCESS_INFORMATION lpProcessInformation
    );

    int MultiByteToWideChar(
        UINT     CodePage,
        DWORD    dwFlags,
        LPCSTR   lpMultiByteStr,
        int      cbMultiByte,
        LPWSTR   lpWideCharStr,
        int      cchWideChar
    );
]]

local function wcs(s)
    if type(s) ~= 'string' then return s end
    local sz = #s + 1
    local c_str = ffi.new("char[?]", sz)
    ffi.copy(c_str, s)
    local w_str = ffi.new("WCHAR[?]", sz)
    sz = ffi.C.MultiByteToWideChar(65001, 0, c_str, sz, w_str, sz)
    return w_str, sz
end

--[[
    cfg top keys:
    * cmd - string command line to execute file with arguments
    * debug - boolean to run it in debug mode
]]
function CProcess:init(cfg)
    self.cmd = wcs(assert(cfg.cmd, "command is not defined"))
    self.is_debug = false
    self.hProc = nil
    self.hJob = nil
    self.stdoutReadPipe  = nil
    self.stdoutWritePipe = nil
    self.stdinReadPipe   = nil
    self.stdinWritePipe  = nil

    if type(cfg.debug) == "boolean" then
        self.is_debug = cfg.debug
    end
    if type(cfg.cwd) == "string" then
        self.cwd = wcs(cfg.cwd)
    end
end

function CProcess:free()
    __log.debug("finalize CProcess object")
    self:kill()
end

-- in: nil
-- out: boolean, string (or nil)
--      result of run the process
--      error string if process failed to run
function CProcess:run()
    __log.debug("run CProcess")
    if self.hJob and self.hProc then
        kernel32.TerminateProcess(self.hProc, 0)
        kernel32.CloseHandle(self.hProc)
        kernel32.CloseHandle(self.hJob)
        self.hProc = nil
        self.hJob = nil
    end

    local HANDLE_FLAG_INHERIT = 0x00000001
    -- local pipe
    local stdoutReadPipe  = ffi.new("HANDLE[1]")
    local stdoutWritePipe = ffi.new("HANDLE[1]")
    local stdinReadPipe   = ffi.new("HANDLE[1]")
    local stdinWritePipe  = ffi.new("HANDLE[1]")

    local pipeSec=ffi.new("SECURITY_ATTRIBUTES",ffi.sizeof("SECURITY_ATTRIBUTES"),nil,true)

    local prc = kernel32.CreatePipe(stdoutReadPipe, stdoutWritePipe, pipeSec, 0)
    if prc == 0 then
        __log.errorf("create pipe failed with error: %d", tonumber(kernel32.GetLastError()))
        return false, "can't create output pipe"
    end

    prc = kernel32.CreatePipe(stdinReadPipe, stdinWritePipe, pipeSec, 0)
    if prc == 0 then
        __log.errorf("create pipe failed with error: %d", tonumber(kernel32.GetLastError()))
        return false, "can't create input pipe"
    end

    local hirc = kernel32.SetHandleInformation(stdoutReadPipe[0], HANDLE_FLAG_INHERIT, 0)
    if hirc == 0 then
        __log.errorf("set handle info failed with error: %d", tonumber(kernel32.GetLastError()))
        return false, "can't set stdout read pipe handle info"
    end

    hirc = kernel32.SetHandleInformation(stdinWritePipe[0], HANDLE_FLAG_INHERIT, 0)
    if hirc == 0 then
        __log.errorf("set handle info failed with error: %d", tonumber(kernel32.GetLastError()))
        return false, "can't set stdin write pipe handle info"
    end

    
    local StartfUsesStdHandles = 0x00000100
    local CREATE_NO_WINDOW=0x8000000

    local pi = ffi.new("PROCESS_INFORMATION", {})
    local si = ffi.new("STARTUPINFOW")
    si.cb = ffi.sizeof(si) 
    si.hStdInput = stdinReadPipe[0]
    si.hStdOutput = stdoutWritePipe[0]
    si.hStdError = stdoutWritePipe[0]
    si.dwFlags = StartfUsesStdHandles


    local iRc = kernel32.CreateProcessW(
        nil,
        self.cmd,
        nil, nil,
        true,
        CREATE_NO_WINDOW,
        nil,
        nil, -- self.cwd,
        si, pi
    )
    if iRc == 0 then
        __log.errorf("process run failed with error: %d", tonumber(kernel32.GetLastError()))
        kernel32.CloseHandle(self.hJob)
        self.hJob = nil
        return false, "can't create process"
    end

    self.hProc = pi.hProcess
    self.stdoutReadPipe = stdoutReadPipe[0]
    self.stdoutWritePipe = stdoutWritePipe[0]
    self.stdinReadPipe = stdinReadPipe[0]
    self.stdinWritePipe = stdinWritePipe[0]
    kernel32.CloseHandle(stdoutWritePipe[0])
    kernel32.CloseHandle(stdinReadPipe[0])
    kernel32.CloseHandle(pi.hThread)
    return true
end

function CProcess:check_data()
    local as = ffi.new("DWORD[1]")
    if kernel32.PeekNamedPipe(self.stdoutReadPipe, nil, 0, nil, as, nil) == 0 then
        __log.errorf("peek named pipe failed: %d", tonumber(kernel32.GetLastError()))
        return ''
    end
    local bytesToRead = as[0]
    if (bytesToRead == 0) then
        return ''
    end
    print(bytesToRead)

    local buffer=ffi.new("char[?]",bytesToRead + 1) 
    local bytesRead=ffi.new("unsigned long[1]")
    if kernel32.ReadFile(self.stdoutReadPipe, buffer, bytesToRead, bytesRead, nil) == 0 then
        __log.errorf("read from pipe failed: %d", tonumber(kernel32.GetLastError()))
        return ''
    end
    -- print(bytesRead[0])

    return ffi.string(buffer, bytesRead[0])
end

function CProcess:send_input(s)
    local c_str = ffi.new("char[?]", #s + 1)
    local bytesWritten=ffi.new("unsigned long[1]")
    c_str[#s] = 0
    ffi.copy(c_str, s)
    if kernel32.WriteFile(self.stdinWritePipe, c_str, #s, bytesWritten, nil) == 0 then
        __log.errorf("failed to write in pipe : %d", tonumber(kernel32.GetLastError()))
        return
    end
end

-- in: nil
-- out: boolean, string (or nil)
--      result of wait the process by handle
--      error string if process failed to wait
function CProcess:wait(timeout)
    if timeout == -1 then timeout = kernel32.INFINITE end
    local wait_result = kernel32.WaitForSingleObject(self.hProc, timeout)
    if wait_result == kernel32.WAIT_TIMEOUT then
        return "timeout"
    elseif wait_result == kernel32.WAIT_OBJECT_0 then
        return "ok"
    end
    return nil, "unxpected wait return code: " .. tostring(wait_result)
end

-- in: nil
-- out: boolean
--      result of waiting on the process handle
function CProcess:is_running()
    return self:wait(0) == "timeout"
end

-- in: nil
-- out: boolean, string (or nil)
--      result of killing the process by handle
--      error string if process failed to kill
function CProcess:kill()
    __log.debug("kill CProcess", tonumber(self.hProc), tonumber(self.hJob))
    if self.hJob and self.hProc then
        kernel32.TerminateProcess(self.hProc, 0)
        kernel32.CloseHandle(self.hProc)
        kernel32.CloseHandle(self.hJob)
        self.hProc = nil
        self.hJob = nil
        return true
    end
    return false, "process not running"
end
