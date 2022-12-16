local rdkafka = require "rdkafka"
local sleep = require "sleep"

function log(...)
	print(...)
	io.flush()
end

local conf = rdkafka.Config.new{
	["bootstrap.servers"] = "127.0.0.1",
	["message.timeout.ms"] = "3000",
	-- ["retries"] = "1",
}
conf:on_error(function(code, msg)
	log("rdkafka: err="..code..": "..msg)
end)

local prod = rdkafka.Producer.new(conf)
local topic = prod:topic("test")

for i = 1,3 do
	log("produce:",
		prod:produce(topic, "message_" .. i))
	prod:poll()
	sleep(1000)
end

prod:flush(3000)
prod:destroy()
