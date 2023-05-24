require("yaci")
require("strict")
require("ptys.pty")

local ffi      = require("ffi")
local kernel32 = require("waffi.windows.kernel32")


ffi.cdef[[
    /* Error handling. */
    typedef struct winpty_error_s winpty_error_t;
    typedef winpty_error_t* winpty_error_ptr_t;
    typedef DWORD winpty_result_t;

    winpty_result_t winpty_error_code(winpty_error_ptr_t err);

    LPCWSTR winpty_error_msg(winpty_error_ptr_t err);

    void winpty_error_free(winpty_error_ptr_t err);

    /* Configuration of a new agent. */
    typedef struct winpty_config_s winpty_config_t;

    winpty_config_t* winpty_config_new(UINT64 agentFlags, winpty_error_ptr_t *err /*OPTIONAL*/);

    void winpty_config_free(winpty_config_t *cfg);

    void winpty_config_set_initial_size(winpty_config_t *cfg, int cols, int rows);

    void winpty_config_set_mouse_mode(winpty_config_t *cfg, int mouseMode);

    void winpty_config_set_agent_timeout(winpty_config_t *cfg, DWORD timeoutMs);

    /* Start the agent. */
    typedef struct winpty_s winpty_t;

    winpty_t* winpty_open(const winpty_config_t *cfg, winpty_error_ptr_t *err /*OPTIONAL*/);

    HANDLE winpty_agent_process(winpty_t *wp);

    /* I/O pipes. */

    LPCWSTR winpty_conin_name(winpty_t *wp);
    LPCWSTR winpty_conout_name(winpty_t *wp);
    LPCWSTR winpty_conerr_name(winpty_t *wp);

    /* winpty agent RPC call: process creation. */
    typedef struct winpty_spawn_config_s winpty_spawn_config_t;

    winpty_spawn_config_t* winpty_spawn_config_new(
        UINT64 spawnFlags,
        LPCWSTR appname /*OPTIONAL*/,
        LPCWSTR cmdline /*OPTIONAL*/,
        LPCWSTR cwd /*OPTIONAL*/,
        LPCWSTR env /*OPTIONAL*/,
        winpty_error_ptr_t *err /*OPTIONAL*/);

    void winpty_spawn_config_free(winpty_spawn_config_t *cfg);

    BOOL winpty_spawn(winpty_t *wp,
        const winpty_spawn_config_t *cfg,
        HANDLE *process_handle /*OPTIONAL*/,
        HANDLE *thread_handle /*OPTIONAL*/,
        DWORD *create_process_error /*OPTIONAL*/,
        winpty_error_ptr_t *err /*OPTIONAL*/);

    /* winpty agent RPC calls: everything else */
    BOOL winpty_set_size(winpty_t *wp, int cols, int rows, winpty_error_ptr_t *err /*OPTIONAL*/);

    int winpty_get_console_process_list(winpty_t *wp, int *processList, const int processCount,
        winpty_error_ptr_t *err /*OPTIONAL*/);

    void winpty_free(winpty_t *wp);

    HANDLE CreateFileW(
        LPCWSTR lpFileName,
        DWORD dwDesiredAccess,
        DWORD dwShareMode,
        LPSECURITY_ATTRIBUTES lpSecurityAttributes,
        DWORD dwCreationDisposition,
        DWORD dwFlagsAndAttributes,
        HANDLE hTemplateFile
    );
]]


CWinPty = newclass("CWinPty", CPty)

local function wcs(s)
    local sz = #s + 1
    local c_str = ffi.new("char[?]", sz)
    ffi.copy(c_str, s)

    local w_sz = ffi.C.MultiByteToWideChar(ffi.C.CP_UTF8, 0, c_str, -1, nil, 0);
    local w_str = ffi.new("WCHAR[?]", w_sz)
    ffi.C.MultiByteToWideChar(ffi.C.CP_UTF8, 0, c_str, -1, w_str, w_sz);
    return w_str, w_sz
end

function CWinPty:init()
    __log.debug("init CWinPty")
    -- this this load winpty dll.
    self.winpty = ffi.load("winpty")
    self.wp = nil
    self.stdoutPipe = nil
    self.stdinPipe = nil
    self.stderrPipe = nil
    self.closed = false
    self.proc_handle = nil
end

function CWinPty:GetWinPtyErrorMessage(error_pointer)
    local msgPtr = self.winpty.winpty_error_msg(error_pointer)

    local error_str = ""

    local val = msgPtr[0]
    while (val > 0)
    do
        -- this one may works bad with utf16 non-en chars.
        error_str = error_str .. string.char(val)
        msgPtr = msgPtr + 1
        val = msgPtr[0]
    end
    return error_str
end

function CWinPty:start(cmd_string)
    __log.debug("start CWinPty")

    local winpty_error = ffi.new('winpty_error_ptr_t [1]')

    local config_pointer = self.winpty.winpty_config_new(0, winpty_error)
    if config_pointer == nil then
        __log.errorf("cWinPty: failed to create winpty config: %s", self:GetWinPtyErrorMessage(winpty_error[0]))
        return false
    end

    self.winpty.winpty_config_set_initial_size(config_pointer, 120, 35)

    local wp = self.winpty.winpty_open(config_pointer, winpty_error)
    if wp == nil then
        __log.errorf("cWinPty: failed to open winpty: %s", self:GetWinPtyErrorMessage(winpty_error[0]))
        return false
    end
    self.wp = wp

    self.winpty.winpty_config_free(config_pointer)
    local stdin_name = self.winpty.winpty_conin_name(wp)
    local stdout_name = self.winpty.winpty_conout_name(wp)

    local stdin_handle = kernel32.CreateFileW(stdin_name, ffi.C.GENERIC_WRITE, 0, nil, ffi.C.OPEN_EXISTING, 0, nil)
    if stdin_handle == -1 then
        __log.errorf("cWinPty: failed to open stdin pipe: %d", tonumber(kernel32.GetLastError()))
        return false
    end
    self.stdinPipe = stdin_handle

    local stdout_handle = kernel32.CreateFileW(stdout_name, ffi.C.GENERIC_READ, 0, nil, ffi.C.OPEN_EXISTING, 0, nil)
    if stdout_handle == -1 then
        __log.errorf("cWinPty: failed to open stdin pipe: %d", tonumber(kernel32.GetLastError()))
        return false
    end
    self.stdoutPipe = stdout_handle


    local WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN = 1
    local cmd = wcs(cmd_string)
    local spawnConfig = self.winpty.winpty_spawn_config_new(WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN, nil, cmd, nil, nil, winpty_error)
    if spawnConfig == nil then
        __log.errorf("cWinPty: failed to create new spawn config: %s", self:GetWinPtyErrorMessage(winpty_error[0]))
        return false
    end

    local procHandle = ffi.new("HANDLE[1]")
    local lastErr = ffi.new("uint32_t[1]")

    local spawned = self.winpty.winpty_spawn(wp, spawnConfig, procHandle, nil, lastErr, winpty_error)
    if spawned == 0 then
        __log.errorf("cWinPty: failed to spawn winpty: %s", self:GetWinPtyErrorMessage(winpty_error[0]))
        return false
    end
    self.proc_handle = procHandle[0]

    self.winpty.winpty_spawn_config_free(spawnConfig)

    __log.debugf("cWinPty: spawned: %d", spawned)
    return true
end

function CWinPty:close()
    if self.closed then
        __log.infof("cWinPty: attempt to close winpty that is already closed")
        return
    end

    if self.wp ~= nil then
        self.winpty.winpty_free(self.wp)
        self.wp = nil
    end

    if self.stdinPipe ~= nil then
        kernel32.CloseHandle(self.stdinPipe)
    end
    if self.stdoutPipe ~= nil then
        kernel32.CloseHandle(self.stdoutPipe)
    end
    if self.proc_handle ~= nil then
        kernel32.CloseHandle(self.proc_handle)
    end

    self.closed = true
end

function CWinPty:get_data(timeout)
    local ERROR_BUSY = 170
    local as = ffi.new("DWORD[1]")

    local slept = 0
    local bytesToRead = 0

    while slept < timeout do
        if kernel32.PeekNamedPipe(self.stdoutPipe, nil, 0, nil, as, nil) == 0 then
            local last_error = tonumber(kernel32.GetLastError())
            __log.errorf("cWinPty: peek pipe failed: %d", last_error)

            if last_error ~= ERROR_BUSY then
                return '', false
            end
        end

        bytesToRead = as[0]
        if bytesToRead ~= 0 then
            break
        end
        if timeout == 0 then
            break
        end
        __api.await(10)
        slept = slept + 10
    end

    if bytesToRead == 0 then
        return '', true
    end

    local buffer=ffi.new("char[?]", bytesToRead + 1)
    local bytesRead=ffi.new("unsigned long[1]")
    if kernel32.ReadFile(self.stdoutPipe, buffer, bytesToRead, bytesRead, nil) == 0 then
        __log.errorf("cWinPty: read from pipe failed: %d", tonumber(kernel32.GetLastError()))
        return '', false
    end

    return ffi.string(buffer, bytesRead[0]), true
end

function CWinPty:send_input(s)
    local c_str = ffi.new("char[?]", #s + 1)
    local bytesWritten=ffi.new("unsigned long[1]")
    c_str[#s] = 0
    ffi.copy(c_str, s)
    if kernel32.WriteFile(self.stdinPipe, c_str, #s, bytesWritten, nil) == 0 then
        __log.errorf("cWinPty: failed to write in pipe : %d", tonumber(kernel32.GetLastError()))
        return
    end
end