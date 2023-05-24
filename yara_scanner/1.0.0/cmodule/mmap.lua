local ffi = require("ffi")

local M = {}

local function init_if_linux()
    if ffi.os ~= "Linux" then
        return
    end
    ffi.cdef [[
        typedef int64_t off64_t;

        int open(const char *pathname, int flags);
        int close(int fd);

        void* mmap(void *addr, size_t length, int prot, int flags, int fd, off64_t offset);
        int munmap(void *addr, size_t length);
    ]]

    local function try_to_cdef_stat_x64()
        if ffi.arch ~= "x64" then
            return false
        end
        if pcall(ffi.typeof, "struct stat") then
            -- struct "stat" was already defined
            return false
        end
        ffi.cdef [[
            struct stat {
                uint64_t st_dev;
                uint64_t st_ino;
                uint64_t st_nlink;
                uint32_t st_mode;
                uint32_t st_uid;
                uint32_t st_gid;
                uint32_t __pad0;
                uint64_t st_rdev;
                int64_t  st_size;
                int64_t  st_blksize;
                int64_t  st_blocks;
                uint64_t st_atime;
                uint64_t st_atime_nsec;
                uint64_t st_mtime;
                uint64_t st_mtime_nsec;
                uint64_t st_ctime;
                uint64_t st_ctime_nsec;
                int64_t  __unused[3];
            };
        ]]
        return true
    end

    local function try_to_cdef_stat_non_x64()
        if ffi.arch == "x64" then
            return false
        end
        if pcall(ffi.typeof, "struct stat") then
            -- struct "stat" was already defined
            return false
        end
        ffi.cdef [[
            struct stat {
                uint64_t st_dev;
                uint8_t  __pad0[4];
                uint32_t __st_ino;
                uint32_t st_mode;
                uint32_t st_nlink;
                uint32_t st_uid;
                uint32_t st_gid;
                uint64_t st_rdev;
                uint8_t  __pad3[4];
                int64_t  st_size;
                uint32_t st_blksize;
                uint64_t st_blocks;
                uint32_t st_atime;
                uint32_t st_atime_nsec;
                uint32_t st_mtime;
                uint32_t st_mtime_nsec;
                uint32_t st_ctime;
                uint32_t st_ctime_nsec;
                uint64_t st_ino;
            };
        ]]
        return true
    end

    if not try_to_cdef_stat_x64() then
        try_to_cdef_stat_non_x64()
    end

    ffi.cdef [[
        int fstat(int fd, struct stat *buf);
    ]]

    local MAP_FAILED = -1;

    local O_RDONLY = 0
    local PROT_READ = 1
    local MAP_PRIVATE = 2

    function M.mmap_ro(filepath)
        local fd = ffi.C.open(filepath, O_RDONLY)
        if fd < 0 then
            return nil
        end

        local st = ffi.new("struct stat[1]")

        local ret = ffi.C.fstat(fd, st)
        if ret < 0 then
            ffi.C.close(fd)
            return nil;
        end

        local size = st[0].st_size

        local addr = ffi.C.mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if addr == MAP_FAILED then
            ffi.C.close(fd)
            return nil;
        end

        return { fd = fd, addr = addr, size = size }
    end

    function M.munmap(map)
        assert(ffi.C.munmap(map.addr, map.size) == 0)
        assert(ffi.C.close(map.fd))
    end
end

local function init_if_windows()
    if not (ffi.abi "win") then
        return
    end

    local lk32 = require("waffi.windows.kernel32")

    local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1);

    local FILE_ATTRIBUTE_NORMAL = 0x00000080
    local PAGE_READONLY = 0x02
    local FILE_MAP_READ = 0x0004

    local function wcs(str)
        local ptr, size = ffi.cast("const char*", str), #str

        local nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, nil, 0)
        if nsize <= 0 then
            return nil, 0
        end

        local wstr = ffi.new("wchar_t[?]", nsize + 1)
        nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, wstr, nsize)
        return wstr, nsize
    end

    function M.mmap_ro(filepath)
        local hFile = lk32.CreateFileW(
            wcs(filepath),
            lk32.GENERIC_READ,
            lk32.FILE_SHARE_READ,
            nil,
            lk32.OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            nil
        )

        if hFile == INVALID_HANDLE_VALUE then
            return nil
        end

        local info = ffi.new("BY_HANDLE_FILE_INFORMATION[1]")

        local ret = lk32.GetFileInformationByHandle(hFile, info)
        if ret == 0 then
            lk32.CloseHandle(hFile)
            return nil;
        end

        local ul = ffi.new("ULARGE_INTEGER")
        ul.u.LowPart = info[0].nFileSizeLow
        ul.u.HighPart = info[0].nFileSizeHigh

        local size = ul.QuadPart

        local hMap = lk32.CreateFileMappingW(hFile, nil, PAGE_READONLY, 0, 0, nil);
        lk32.CloseHandle(hFile)

        if hMap == INVALID_HANDLE_VALUE then
            return nil
        end

        local addr = lk32.MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0);
        if addr == nil then
            lk32.CloseHandle(hMap)
            return nil;
        end

        return { hMap = hMap, addr = addr, size = size }
    end

    function M.munmap(map)
        assert(lk32.UnmapViewOfFile(map.addr))
        assert(lk32.CloseHandle(map.hMap))
    end
end

-- TODO extract separate script files for Windows, Linux

init_if_linux()
init_if_windows()

return M
