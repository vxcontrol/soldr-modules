local SAVEPOINT_PATH = "cyberok_wel_savepoint.xml"

local cjson  = require "cjson"
local events = require "events_"

local reader = require("reader_").new()
local receivers = require("receivers").new()

local function update_config()
	local c = cjson.decode(__config.get_current_config())
	events.update_config()
	reader:configure(c.log_channels, SAVEPOINT_PATH)
	receivers:configure(c.receivers)
end
update_config()

__api.add_cbs{
	control = function(cmtype, data)
		if cmtype == "update_config" then update_config() end
		return true
	end,
}

while not __api.is_close() do
	local entries = reader:read()
	if not entries then
		__api.await(100)
		goto continue
	end

	for _, entry in ipairs(entries) do
		events.entry(entry)
	end
	receivers:receive(cjson.encode(entries))

	::continue::
end

reader:close()
return 'success'
