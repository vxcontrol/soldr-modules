---------------------------------------------------
local log = {}
---------------------------------------------------

local levels = {
    error = 1,
    warn  = 2,
    info  = 3,
    debug = 4,
    trace = 5,
}

local function error(...)
    print("[ERROR] ", ...)
end

local function warn(...)
    print("[WARN]  ", ...)
end

local function info(...)
    print("[INFO]  ", ...)
end

local function debug(...)
    print("[DEBUG] ", ...)
end

local function get_log_level()
    return levels[__mock.log_level]
end

function log.error(...)
    __mock.trace("__log.error", ...)
    if get_log_level() >= levels["error"] then
        error(...)
    end
end

function log.warn(...)
    __mock.trace("__log.warn", ...)
    if get_log_level() >= levels["warn"] then
        warn(...)
    end
end

function log.info(...)
    __mock.trace("__log.info", ...)
    if get_log_level() >= levels["info"] then
        info(...)
    end
end

function log.debug(...)
    __mock.trace("__log.debug", ...)
    if get_log_level() >= levels["debug"] then
        debug(...)
    end
end

function log.errorf(fmt, ...)
    local msg = string.format(fmt, ...)
    __mock.trace("__log.errorf", msg)
    if get_log_level() >= levels["error"] then
        error(msg)
    end
end

function log.warnf(fmt, ...)
    local msg = string.format(fmt, ...)
    __mock.trace("__log.warnf", msg)
    if get_log_level() >= levels["warn"] then
        warn(msg)
    end
end

function log.infof(fmt, ...)
    local msg = string.format(fmt, ...)
    __mock.trace("__log.infof", msg)
    if get_log_level() >= levels["info"] then
        info(msg)
    end
end

function log.debugf(fmt, ...)
    local msg = string.format(fmt, ...)
    __mock.trace("__log.debugf", msg)
    if get_log_level() >= levels["debug"] then
        debug(msg)
    end
end

return log
