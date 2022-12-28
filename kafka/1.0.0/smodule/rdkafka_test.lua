local rdkafka = require "rdkafka"

local conf = rdkafka.Config.new{
	["bootstrap.servers"]  = "127.0.0.1",
	["message.timeout.ms"] = "3000",
	["retries"]            = "1",
}
conf:on_error(function(code, msg)
	error(string.format("code=%s msg=%s", code, msg))
end)

local prod = rdkafka.Producer.new(conf)
local topic = prod:topic("test")

for i = 1,3 do
	assert(prod:produce(topic, "message_" .. i))
	assert(prod:poll())
end

assert(prod:flush(3000))
prod:destroy()
