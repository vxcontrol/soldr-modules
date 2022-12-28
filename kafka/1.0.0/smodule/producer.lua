local rdkafka = require "rdkafka"

local Producer = {}; Producer.__index = Producer

--:: () -> Producer
function Producer.new()
	return setmetatable({}, Producer)
end

--:: {
--::   brokers        :: string
--::   topic          :: string
--::   user           :: string?
--::   password       :: string?
--::   sasl_mechanism :: string?
--::   ssl            :: boolean
--::   ca_cert        :: string?
--::   timeout        :: number, seconds
--::   retries        :: number
--::   on_error       :: (err::string -> ())?
--:: } -> ()
function Producer:configure(c)
	self:close()

	local props = {
		["bootstrap.servers"]  = c.brokers,
		["security.protocol"]  = (c.ssl and "ssl") or "plaintext",
		["message.timeout.ms"] = tostring(c.timeout * 1000),
		["retries"]            = tostring(c.retries),
	}
	if c.user and c.user ~= "" and c.password and c.password ~= "" then
		props["security.protocol"] = (c.ssl and "sasl_ssl") or "sasl_plaintext"
		props["sasl.mechanism"]    = c.sasl_mechanism or "PLAIN"
		props["sasl.username"]     = c.user
		props["sasl.password"]     = c.password
	end

	local conf = rdkafka.Config.new(props)
	if c.ca_cert and c.ca_cert ~= "" then
		conf:set_ca_cert(c.ca_cert)
	end
	if c.on_error then
		conf:on_error(function(err, msg)
			c.on_error(string.format("rdkafka: err=%d: %s", err, msg))
		end)
	end

	self._prod = rdkafka.Producer.new(conf)
	self._topic = self._prod:topic(c.topic)
end

--:: string, string? -> ()
function Producer:produce(payload, key)
	return self._prod:produce(self._topic, payload or "", key)
end

function Producer:poll()
	if self._prod then self._prod:poll() end
end

function Producer:close()
	if self._prod then
		-- TODO: What timeout shall be used to not lock the module?
		self._prod:flush(10e3)
		self._prod:destroy()
		self._prod = nil
	end
end

return Producer
