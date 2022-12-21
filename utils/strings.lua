local ffi = require('ffi')

local strings = {}

function strings.named_format(String, Args)
    local i = 1
    local result = ""
    while (true) do
        local start_i, end_i, arg_key = String:find("%%{(.-)}", i)
        if (start_i == nil) then
            break
        end
        local arg_value = Args[arg_key]
        if (arg_value == nil) then
            assert(arg_value ~= nil, ("Format error: no argument '%s' found"):format(arg_key))
        end
        result = result..String:sub(i, start_i - 1)..tostring(arg_value)
        i = end_i + 1
    end
    result = result..String:sub(i, String:len())
    return result
end

function strings.escape_path(p)
    return ffi.os == "Windows" and p:gsub('\\', '\\\\') or p
end

return strings
