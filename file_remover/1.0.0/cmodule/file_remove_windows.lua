local ffi  = require("ffi")
local lk32 = require("waffi.windows.kernel32")

local function multiByteToWideChar(str)
    local ptr, size = ffi.cast("const char*", str), #str

    local nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, nil, 0)
    if nsize <= 0 then
        return nil, 0
    end

    local wstr = ffi.new("wchar_t[?]", nsize + 1)
    nsize = lk32.MultiByteToWideChar(lk32.CP_UTF8, 0, ptr, size, wstr, nsize)
    return wstr, nsize
end

local function win_remove_file(file_path)
    local wpath, _ = multiByteToWideChar(file_path)
    local result = lk32.DeleteFileW(wpath) ~= 0
    if result then
        return true
    end

    local err = tonumber(lk32.GetLastError())
    local msg = "Failed to delete file, Errno: " .. err
    if err == 2 then -- ERROR_FILE_NOT_FOUND
        msg = file_path .. ": No such file or directory"
    end
    return nil, msg
end

return {
    remove_file = win_remove_file
}
