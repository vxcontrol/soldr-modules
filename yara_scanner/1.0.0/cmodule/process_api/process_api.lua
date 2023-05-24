local ffi = require("ffi")
local os = string.lower(ffi.os)
local os_specific_process_api = ("process_api_%s"):format(os)
return require(os_specific_process_api)
