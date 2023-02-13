local path = require("path")
local lfs = require("lfs")
local ffi = require("ffi")

local fs_notify = {}

-- returns true if the filename mathes pattern
function fs_notify.is_filename_match_pattern(filename, pattern)
    assert(type(filename) == "string", "filename must be a string")
    assert(type(pattern) == "string", "pattern must be a string")
    if ffi.os ~= "Windows" then
        return false
    end
    local lk32 = require("waffi.windows.kernel32")
    local shlw = require("waffi.windows.shlwapi")
    local multiByteToWideChar = function(str)
        local ptr, size = ffi.cast("const char*", str), #str

        local nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, nil, 0)
        if nsize <= 0 then
            return nil, 0
        end

        local wstr = ffi.new("wchar_t[?]", nsize + 1)
        nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, wstr, nsize)
        return wstr, nsize
    end
    if pattern == "" then
        return true
    end
    local wfilename, _ = multiByteToWideChar(filename)
    local wpattern, _ = multiByteToWideChar(pattern)
    return shlw.PathMatchSpecW(wfilename, wpattern) ~= 0
end

-- returns true if the string `str` is a glob pattern
function fs_notify.is_glob_pattern(str)
    assert(type(str) == "string", "str must be a string")
    if path.file(str):find("[*?]") then
        return true
    end
    return false
end

-- returns all files matching glob pattern
function fs_notify.find_all_files(pattern)
    assert(type(pattern) == "string", "pattern must be a string")
    if ffi.os ~= "Windows" then
        return {}
    end
    local pattern_dir = path.dir(pattern) or "."
    local pattern_file = path.file(pattern)
    local files = {}
    for file in lfs.dir(pattern_dir) do
        if fs_notify.is_filename_match_pattern(file, pattern_file) then
            table.insert(files, path.combine(pattern_dir, file))
        end
    end
    return files
end

return fs_notify
