require("yaci")
require("strict")
local pp    = require("pp")
local glue  = require("glue")

CSystemInfo = newclass("CSystemInfo")

function CSystemInfo:print(...)
    if self.is_debug then
        local t = glue.pack(...)
        for i, v in ipairs(t) do
            t[i] = pp.format(v)
        end
        print(glue.unpack(t))
    end
end

function CSystemInfo:init(is_debug)
    self.is_debug = false

    if type(is_debug) == "boolean" then
        self.is_debug = is_debug
    end
    self:print("intialize CSystemInfo object")
end

function CSystemInfo:exec_cmd(cmd, raw)
    self:print("cmd to exec: " .. tostring(cmd))
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    self:print("cmd output: " .. tostring(s))
    if raw or raw == nil then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end
