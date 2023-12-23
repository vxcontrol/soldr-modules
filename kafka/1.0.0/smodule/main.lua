local cjson = require "cjson"
local uuid  = require "uuid"

local producer = require("producer").new()

local function update_config()
	local c = cjson.decode(__config.get_current_config())
	producer:configure{
		brokers        = c.a1_brokers,
		topic          = c.a2_topic,
		user           = c.b1_user,
		password       = c.b2_password,
		sasl_mechanism = c.b3_sasl_mechanism,
		ssl            = c.c1_ssl,
		ca_cert        = c.c2_ca_cert,
		timeout        = c.d1_timeout,
		retries        = c.d2_retries,
		on_error       = __log.error,
	}
end
update_config()

-- Handle the main action `produce`.
local function produce(src, data, name)
	producer:poll()

	local m = cjson.decode(data)
	local payload = cjson.encode{
		id    = m.data.id or m.data.uuid or uuid(),
		aid   = m.aid,
		event = m.name,
		data  = m.data,
	}
	return producer:produce(payload)
end

__api.add_cbs{
	action = produce,
	data   = produce,

	control = function(cmtype, data)
		if cmtype == "update_config" then update_config() end
		return true
	end,
}

__api.await(-1)
producer:close()

return 'success'
