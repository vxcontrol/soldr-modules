require("yaci")
require("engines.db_engine")
local cjson = require("cjson")

local ScanResultsCache = newclass("ScanResultsCache")

function ScanResultsCache:init(db_engine)
    self.db_engine = db_engine
end

function ScanResultsCache:add(process_id, process_image, scan_results)
    if not self.db_engine then
        __log.error("ScanResultsCache:add ~ db_engine is not initialized")
        return false
    end

    if (type(process_id) ~= "number") then
        __log.error("ScanResultsCache:add ~ non-valid process_id parameter")
        return false
    end

    if (type(process_image) ~= "string") then
        __log.error("ScanResultsCache:add ~ non-valid process_image parameter")
        return false
    end

    if not scan_results then
        __log.error("ScanResultsCache:add ~ non-valid scan_results parameter")
        return false
    end

    if not scan_results.yara_scan_results then
        __log.error("ScanResultsCache:add ~ non-valid scan_results.yara_scan_results")
        return false
    end

    local yara_scan_results = scan_results.yara_scan_results

    if type(yara_scan_results) ~= "table" then
        __log.error("ScanResultsCache:add ~ non-table scan_results.yara_scan_results")
        return false
    end

    yara_scan_results = cjson.encode(yara_scan_results)

    return self.db_engine:add_to_process_cache(process_id, process_image, scan_results.last_scan_time, yara_scan_results)
end

function ScanResultsCache:get(process_id, process_image)
    if not self.db_engine then
        __log.error("ScanResultsCache:get ~ db_engine is not initialized")
        return nil
    end

    if (type(process_id) ~= "number") then
        __log.error("ScanResultsCache:add ~ non-valid process_id parameter")
        return nil
    end

    if (type(process_image) ~= "string") then
        __log.error("ScanResultsCache:add ~ non-valid process_image parameter")
        return nil
    end

    local query_scan_results = self.db_engine:get_from_process_cache(process_id, process_image)

    if not query_scan_results then
        __log.debug("ScanResultsCache:get ~ no scan results in process cache")
        return nil
    end

    if type(query_scan_results) ~= "table" then
        __log.error("ScanResultsCache:get ~ non-valid scan results ~ process cache")
        return nil
    end

    query_scan_results.scan_results = cjson.decode(query_scan_results.scan_results)

    return query_scan_results
end

function ScanResultsCache:remove(process_id, process_image)
    -- TODO return success \ failure
    if not self.db_engine then
        __log.error("ScanResultsCache:remove ~ db_engine is not initialized")
        return
    end

    if (type(process_id) ~= "number") then
        __log.error("ScanResultsCache:add ~ non-valid process_id parameter")
        return
    end

    if (type(process_image) ~= "string") then
        __log.error("ScanResultsCache:add ~ non-valid process_image parameter")
        return
    end

    self.db_engine:delete_from_process_cache(process_id, process_image)
end

function ScanResultsCache:cleanup()
    self.db_engine = nil
end

return ScanResultsCache
