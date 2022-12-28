print("<<< KAFKA EXAMPLE")

require("engine")

local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()

local event_engine = CEventEngine(fields_schema, current_event_config, module_info, prefix_db, true)
local action_engine = CActionEngine({}, true)

local function emit_event(event)
	local result, list = event_engine:push_event(event)
	if result then action_engine:exec(__aid, list) end
end

while not __api.is_close() do
	print("<<< NOTIFY")
	emit_event{name="notify", data={one="One", two="200"}}
	__api.await(3000)
end

return 'success'
