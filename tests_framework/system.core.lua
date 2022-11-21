local system_core = {}

local socket = require 'socket'
local ffi = require("ffi")

system_core._VERSION = "LuaSystem 0.2.1"

if ffi.os == "Windows" then

    ffi.cdef[[
        typedef unsigned long DWORD;
        typedef struct _FILETIME {
            DWORD dwLowDateTime;
            DWORD dwHighDateTime;
        } FILETIME, *PFILETIME, *LPFILETIME;

        void GetSystemTimeAsFileTime(LPFILETIME lpSystemTimeAsFileTime);
        uint64_t GetTickCount64();
    ]]

    function system_core.gettime()
        local ft = ffi.new("FILETIME")
        local GetSystemTimeAsFileTime = assert(ffi.C.GetSystemTimeAsFileTime, "GetSystemTimeAsFileTime not found")

        GetSystemTimeAsFileTime(ft);
        -- Windows file time (time since January 1, 1601 (UTC))
        local t = ft.dwLowDateTime * 1.0e-7 + ft.dwHighDateTime * (4294967296.0 * 1.0e-7)
        -- convert to Unix Epoch time (time since January 1, 1970 (UTC))
        return (t - 11644473600.0)
    end

    function system_core.monotime()
        local GetTickCount64 = assert(ffi.C.GetTickCount64, "GetSystemTimeAsFileTime not found")
        return tonumber(GetTickCount64()) / 1000
    end

else

    ffi.cdef[[
        typedef long time_t;
        typedef int clockid_t;

        typedef struct timespec {
            time_t   tv_sec;
            long     tv_nsec;
        } nanotime;

        typedef struct timeval {
            time_t   tv_sec;
            time_t   tv_usec;
        } timeval;

        int clock_gettime(clockid_t clk_id, struct timespec *tp);
        int gettimeofday(struct timeval* t, void* tzp);
    ]]

    function system_core.gettime()
        -- NOTE: need separate implementation for Mac OS < 10.12
        local gettimeofday = assert(ffi.C.gettimeofday, "gettimeofday not found")
        local t = ffi.new("timeval")
        gettimeofday(t, nil)
        return tonumber(t.tv_sec) + tonumber(t.tv_usec)*1.0e-6
    end

    function system_core.monotime()
        -- NOTE: need separate implementation for Mac OS < 10.12
        local clock_gettime = assert(ffi.C.clock_gettime, "clock_gettime not found")
        local t = ffi.new("nanotime")
        clock_gettime(0, t)
        return tonumber(t.tv_sec) + tonumber(t.tv_nsec) * 1.0e-9
    end

end

function system_core.sleep(n)
    socket.sleep(n)
end

return system_core