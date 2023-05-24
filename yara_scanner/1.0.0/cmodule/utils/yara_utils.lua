require("yaci")

local YaraUtils = newclass("YaraUtils")

local MINUTE_SECONDS = 60

function YaraUtils:init()
end

function YaraUtils:get_UTC_time()
    return os.time(os.date("!*t"))
end

function YaraUtils:to_seconds(minutes)
    assert((type(minutes) == "number"), "YaraUtils:to_seconds() ~ invalid minutes parameter")
    return minutes * MINUTE_SECONDS
end

return YaraUtils
