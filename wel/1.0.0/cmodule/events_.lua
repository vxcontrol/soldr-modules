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

function M._emit(event)
	local result, list = event_engine:push_event(event)
	if result then action_engine:exec(__aid, list) end
end

function M.entry(data)
	M._emit{name="cyberok_wel_entry", data=data}
end

function M.error(message)
	M._emit{name="cyberok_wel_error", message=message}
end

return M
