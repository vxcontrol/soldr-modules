require("yaci")
local fs_notify = {}
local path = require("path")
local lfs = require("lfs")
local ffi = require("ffi")

if ffi.os == "Windows" then
    local lk32 = require("waffi.windows.kernel32")
    function fs_notify.multiByteToWideChar(str)
        local ptr, size = ffi.cast("const char*", str), #str

        local nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, nil, 0)
        if nsize <= 0 then
            return nil, 0
        end

        local wstr = ffi.new("wchar_t[?]", nsize + 1)
        nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, wstr, nsize)
        return wstr, nsize
    end

    local shlw = require("waffi.windows.shlwapi")
    function fs_notify.filename_matching_pattern(filename, pattern)
        assert(type(filename) == "string", "filename must be a string")
        assert(type(pattern) == "string", "pattern must be a string")
        if pattern == "" then
            return true
        end
        local wfilename, _ = fs_notify.multiByteToWideChar(filename)
        local wpattern, _ = fs_notify.multiByteToWideChar(pattern)
        return shlw.PathMatchSpecW(wfilename, wpattern) ~= 0
    end
else
    function ifs_notify.filename_matching_pattern(filename, pattern)
        return false
    end
end

function fs_notify.is_glob_pattern(str)
    assert(type(str) == "string", "str must be a string")
    if path.file(str):find("[*?]") then
        return true
    end
    return false
end

function fs_notify.find_all_files(pattern)
    assert(type(pattern) == "string", "pattern must be a string")
    local pattern_dir = path.dir(pattern) or "."
    local pattern_file = path.file(pattern)
    local files = {}
    for file in lfs.dir(pattern_dir) do
        if fs_notify.filename_matching_pattern(file, pattern_file) then
            table.insert(files, path.combine(pattern_dir, file))
        end
    end
    return files
end

fs_notify.DirectoryWatcher = newclass("DirectoryWatcher")

if ffi.os == "Windows" then
    ffi.cdef([[
        typedef void(*LpoverlappedCompletionRoutine)(DWORD, DWORD, LPOVERLAPPED);
        DWORD SleepEx(DWORD,BOOL);
        typedef struct _FILE_NOTIFY_INFORMATION {
            DWORD NextEntryOffset;
            DWORD Action;
            DWORD FileNameLength;
            WCHAR FileName[1];
        } FILE_NOTIFY_INFORMATION, *PFILE_NOTIFY_INFORMATION;
    ]])
    local lk32 = require("waffi.windows.kernel32")
    local bit = require("bit")
    local FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
    local FILE_FLAG_OVERLAPPED = 0x40000000
    local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
    local FILE_SHARE_DELETE = 0x00000004
    local FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001
    local FILE_ACTION_ADDED = 0x00000001

    function fs_notify.wideCharToMultiByte(wstr, wsize)
        local nsize = lk32.WideCharToMultiByte(lk32.CP_UTF8, 0, wstr, wsize, nil, 0, nil, nil)
        if nsize <= 0 then
            return nil, 0
        end
        local str = ffi.new("unsigned char[?]", nsize + 1)
        nsize = lk32.WideCharToMultiByte(lk32.CP_UTF8, 0, wstr, wsize, str, nsize, nil, nil)
        return ffi.string(str, nsize), nsize
    end

    function fs_notify.DirectoryWatcher:init()
        self.entries = {}
        self.entries_num = 0
    end

    function fs_notify.DirectoryWatcher:addDirectory(pattern, callback)
        assert(type(pattern) == "string", "pattern must be a string")
        local pattern_dir = path.dir(pattern) or "."
        local pattern_dirw, _ = fs_notify.multiByteToWideChar(pattern_dir)
        local entry = { callback = callback }
        entry.dir_handle = lk32.CreateFileW(
            pattern_dirw,
            lk32.GENERIC_READ,
            bit.bor(lk32.FILE_SHARE_READ, lk32.FILE_SHARE_WRITE, FILE_SHARE_DELETE),
            nil,
            lk32.OPEN_EXISTING,
            bit.bor(FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OVERLAPPED),
            nil
        )
        if entry.dir_handle == INVALID_HANDLE_VALUE then
            return false
        end
        entry.stopped = false
        entry.dir = pattern_dir
        entry.pattern = pattern
        entry.changes_buffer = ffi.new("BYTE[?]", 65536)
        entry.read_buffer = ffi.new("BYTE[?]", 65536)
        entry.changes_buffer_size = ffi.sizeof("BYTE[?]", 65536)
        entry.lpOverlapped = ffi.new("struct OVERLAPPED[1]")
        entry.c_callback = ffi.cast(
            "LpoverlappedCompletionRoutine",
            function(dwErrorCode, dwNumberOfBytesTransferred, lpOverlapped)
                self:changes_detected(entry, dwErrorCode, dwNumberOfBytesTransferred, lpOverlapped)
            end
        )
        self.entries[pattern] = entry
        local res = lk32.ReadDirectoryChangesW(
            entry.dir_handle,
            entry.changes_buffer,
            entry.changes_buffer_size,
            0,
            FILE_NOTIFY_CHANGE_FILE_NAME,
            nil,
            entry.lpOverlapped,
            entry.c_callback
        )
        if res ~= 1 then
            lk32.CloseHandle(entry.dir_handle)
            self.entries[pattern] = nil
            return false
        end
        self.entries_num = self.entries_num + 1

        return true
    end

    function fs_notify.DirectoryWatcher:removeDirectory(pattern)
        assert(type(pattern) == "string", "pattern must be a string")
        local entry = self.entries[pattern]
        if entry ~= nil then
            entry.stopped = true
            assert(lk32.CancelIo(entry.dir_handle) == 1)
            self:wait(10)
        end
    end

    function fs_notify.DirectoryWatcher:removeAll()
        while self.entries_num > 0 do
            for _, entry in pairs(self.entries) do
                entry.stopped = true
                assert(lk32.CancelIo(entry.dir_handle) == 1)
            end
            self:wait(10)
        end
    end

    function fs_notify.DirectoryWatcher:changes_detected(entry, dwErrorCode, dwNumberOfBytesTransferred, lpOverlapped)
        if dwErrorCode == ffi.C.ERROR_OPERATION_ABORTED then
            lk32.CloseHandle(entry.dir_handle)
            entry.c_callback:free()
            self.entries[entry.pattern] = nil
            self.entries_num = self.entries_num - 1
            return
        end
        ffi.copy(entry.read_buffer, entry.changes_buffer, dwNumberOfBytesTransferred)

        local res = lk32.ReadDirectoryChangesW(
            entry.dir_handle,
            entry.changes_buffer,
            entry.changes_buffer_size,
            0,
            FILE_NOTIFY_CHANGE_FILE_NAME,
            nil,
            entry.lpOverlapped,
            entry.c_callback
        )
        local files = {}
        local current = entry.read_buffer
        local ntf = ffi.cast("PFILE_NOTIFY_INFORMATION", current)
        repeat
            ntf = ffi.cast("PFILE_NOTIFY_INFORMATION", current)
            local filename = fs_notify.wideCharToMultiByte(ntf.FileName, ntf.FileNameLength / ffi.sizeof("WCHAR[?]", 1))
            local fullpath = path.combine(entry.dir, filename)
            if fs_notify.filename_matching_pattern(fullpath, entry.pattern) and ntf.Action == FILE_ACTION_ADDED then
                table.insert(files, fullpath)
            end
            current = current + ntf.NextEntryOffset
        until ntf.NextEntryOffset == 0
        if next(files) ~= nil and not entry.stopped then
            entry.callback(files)
        end
    end

    function fs_notify.DirectoryWatcher:wait(milliseconds)
        ffi.C.SleepEx(milliseconds, true)
    end
else
    function fs_notify.DirectoryWatcher:init() end
    function fs_notify.DirectoryWatcher:addDirectory(pattern, callback)
        return true
    end
    function fs_notify.DirectoryWatcher:removeDirectory(pattern) end
    function fs_notify.DirectoryWatcher:removeAll() end
end
return fs_notify
