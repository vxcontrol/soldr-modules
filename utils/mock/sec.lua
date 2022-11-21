---------------------------------------------------
local sec = {}
---------------------------------------------------

function sec.get(key)
    __mock.trace("__sec.get")
    local value = __mock.sec[key]
    return value or "", value ~= nil
end

return sec
