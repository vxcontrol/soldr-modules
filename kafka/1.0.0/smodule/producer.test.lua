local producer = require "producer"
local sleep = require "sleep"

function log(...)
	print(...)
	io.flush()
end

-- Anonymous producer

local prod = producer.new()
prod:configure{
	brokers = "127.0.0.1:9092",
	topic   = "test",
	timeout = 1,
	retries = 1,
}
for i = 1,3 do
	log("anon:", prod:produce("anon_" .. i))
	prod:poll()
	sleep(1000)
end
prod:close()

-- SASL-plain producer

local prod = producer.new()
prod:configure{
	brokers  = "127.0.0.1:9093",
	topic    = "test",
	user     = "user",
	password = "password",
	timeout  = 1,
	retries  = 1,
}
for i = 1,3 do
	log("sasl_plain:", prod:produce("sasl_plain_" .. i))
	prod:poll()
	sleep(1000)
end
prod:close()
