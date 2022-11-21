local term_core = {}

local ffi = require("ffi")

if ffi.os == "Windows" then
    ffi.cdef[[
        int _isatty(int fd);
    ]]
else
    ffi.cdef[[
        int isatty(int fd);
    ]]
end

function term_core.isatty()
    local isatty = assert(ffi.os == "Windows" and ffi.C._isatty or ffi.C.isatty, "isatty not found")
    -- "1" - STDOUT
    return isatty(1) ~= 0
end

return term_core

