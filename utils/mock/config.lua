local cjson = require("cjson.safe")
---------------------------------------------------
local config = {}
---------------------------------------------------

function config.get_secure_config_schema()
    __mock.trace("__config.get_secure_config_schema")
    return __mock.config.secure_config_schema
end

function config.get_secure_default_config()
    __mock.trace("__config.get_secure_default_config")
    return __mock.config.secure_default_config
end

function config.get_secure_current_config()
    __mock.trace("__config.get_secure_current_config")
    return __mock.config.secure_current_config
end

function config.get_config_schema()
    __mock.trace("__config.get_config_schema")
    return __mock.config.config_schema
end

function config.get_default_config()
    __mock.trace("__config.get_default_config")
    return __mock.config.default_config
end

function config.get_current_config()
    __mock.trace("__config.get_current_config")
    return __mock.config.current_config
end

function config.get_static_dependencies()
    __mock.trace("__config.get_static_dependencies")
    return __mock.config.static_dependencies
end

function config.get_dynamic_dependencies()
    __mock.trace("__config.get_dynamic_dependencies")
    return __mock.config.dynamic_dependencies
end

function config.get_fields_schema()
    __mock.trace("__config.get_fields_schema")
    return __mock.config.fields_schema
end

function config.get_action_config_schema()
    __mock.trace("__config.get_action_config_schema")
    return __mock.config.action_config_schema
end

function config.get_default_action_config()
    __mock.trace("__config.get_action_config")
    return __mock.config.action_config
end

function config.get_current_action_config()
    __mock.trace("__config.get_current_action_config")
    return __mock.config.current_action_config
end

function config.get_event_config_schema()
    __mock.trace("__config.get_event_config_schema")
    return __mock.config.event_config_schema
end

function config.get_default_event_config()
    __mock.trace("__config.get_default_event_config")
    return __mock.config.default_event_config
end

function config.get_current_event_config()
    __mock.trace("__config.get_current_event_config")
    return __mock.config.current_event_config
end

-- TODO: here need notify module
function config.set_current_config(cfg)
    __mock.trace("__config.set_current_config")
    __mock.config.current_config = cfg
    return true
end

-- TODO: here need notify module
function config.set_current_action_config(cfg)
    __mock.trace("__config.set_current_action_config")
    __mock.config.current_action_config = cfg
    return true
end

-- TODO: here need notify module
function config.set_current_event_config(cfg)
    __mock.trace("__config.set_current_event_config")
    __mock.config.current_event_config = cfg
    return true
end

function config.get_module_info()
    __mock.trace("__config.get_module_info")
    return cjson.encode(__mock.module_info)
end

config.ctx = __mock.module_info

return config
