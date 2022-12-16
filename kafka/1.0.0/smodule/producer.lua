local rdkafka = require "rdkafka"

local Producer = {}; Producer.__index = Producer

--:: () -> Producer
function Producer.new()
	return setmetatable({}, Producer)
end

--:: {
--::   brokers  :: string
--::   topic    :: string
--::   user     :: string?
--::   password :: string?
--::   timeout  :: number, seconds
--::   retries  :: number
--:: } -> ()
function Producer:configure(c)
	self:close()

	local props = {
		["bootstrap.servers"]  = c.brokers,
		["message.timeout.ms"] = tostring(c.timeout * 1000),
		["retries"]            = tostring(c.retries),
	}
	if c.user and c.user ~= "" and c.password and c.password ~= "" then
		props["security.protocol"] = "sasl_plaintext"
		props["sasl.mechanisms"]   = "PLAIN"
		props["sasl.username"]     = c.user
		props["sasl.password"]     = c.password
	end

	local conf = rdkafka.Config.new(props)
	conf:on_error(function(err, msg)
		__log.errorf("rdkafka: err=%d: %s", err, msg)
	end)

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
		-- self._prod:flush(self.timeout_ms or 0)
		self._prod:flush(1000)
		self._prod:destroy()
		self._prod = nil
	end
end

return Producer
