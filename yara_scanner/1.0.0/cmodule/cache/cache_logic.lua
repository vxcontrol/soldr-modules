require("yaci")
local glue = require("glue")

local CacheLogic = newclass("CacheLogic")

local DEFAULT_YARA_PROCESS_CACHING_TIME = 60.0

function CacheLogic:init()
    local YaraUtils = require("utils.yara_utils")
    self.yara_utils = YaraUtils()
end

function CacheLogic:set_yara_process_caching_time(minutes)
    assert((type(minutes) == "number"), "CacheLogic:set_yara_process_caching_time ~ invalid minutes parameter")
    self.yara_process_caching_time = minutes
end

function CacheLogic:get_yara_process_caching_time()
    assert((type(self.yara_process_caching_time) == "number"), "CacheLogic:get_yara_process_caching_time ~ invalid yara_process_caching_time")
    return self.yara_process_caching_time
end

function CacheLogic:get_yara_process_caching_time_in_seconds()
    return self.yara_utils:to_seconds(self:get_yara_process_caching_time())
end

function CacheLogic:get_default_yara_process_caching_time()
    return DEFAULT_YARA_PROCESS_CACHING_TIME
end

function CacheLogic:is_make_scan( --[[proc_id, proc_image, ]] scan_results)
    if not scan_results then
        return true
    end
    if not scan_results.yara_scan_results then
        return true
    end
    local last_scan_time = scan_results.last_scan_time
    if type(last_scan_time) ~= "number" then
        __log.error("Non-valid last_scan_time type: " .. type(last_scan_time))
        return true
    end

    if self:get_yara_process_caching_time_in_seconds() <= 0 then
        return true
    end

    local elapsed_time = os.difftime(self.yara_utils:get_UTC_time(), last_scan_time)
    __log.info("CacheLogic:is_make_scan ~ elapsed time between scans: " .. elapsed_time)
    if elapsed_time > self:get_yara_process_caching_time_in_seconds() then
        return true
    end

    return false
end

function CacheLogic:is_make_caching(yara_scan_results)
    if not yara_scan_results then
        return false
    end
    if self:is_yara_error(yara_scan_results) then
        return false
    end
    if self:get_yara_process_caching_time_in_seconds() <= 0 then
        return false
    end
    return true
end

function CacheLogic:is_yara_error(yara_scan_results)
    if type(yara_scan_results) ~= "table" then
        return false
    end
    if glue.count(yara_scan_results) ~= 1 then
        return false
    end
    for _, item in ipairs(yara_scan_results) do
        if not item then
            return false
        end
        if not item.error then
            return false
        end
    end
    return true
end

function CacheLogic:is_use_cached_results(action_name)
    if type(action_name) ~= "string" then
        return false
    end
    if action_name == "yr_subject_scan_proc_non_cached" then
        return false
    end
    if action_name == "yr_object_scan_proc_non_cached" then
        return false
    end
    return true
end

function CacheLogic:cleanup()
    self.yara_utils = nil
end

return CacheLogic
