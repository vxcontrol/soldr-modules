require("engine")
local M = {}

local event_engine
local action_engine

function M.update_config()
	local prefix_db     = __gid .. "."
	local fields_schema = __config.get_fields_schema()
	local event_config  = __config.get_current_event_config()
	local module_info   = __config.get_module_info()

	event_engine = CEventEngine(fields_schema, event_config, module_info, prefix_db, false)
	action_engine = CActionEngine({}, false)
end
M.update_config()

local function send_event(name, data)
	local result, list = event_engine:push_event{
		name = name,
		data = data or {},
	}
	if result then action_engine:exec(__aid, list) end
end

function M.error(err)
	__log.error(err)
	send_event("cyberok_auditd_error", {message=tostring(err)})
end

return M
