local producer = require "producer"

-- Anonymous producer

local prod = producer.new()
prod:configure{
	brokers = "127.0.0.1:9092",
	topic   = "test",
	timeout = 1,
	retries = 1,
	on_error = function(...) error(...) end,
}
for i = 1,3 do
	prod:produce("anon_" .. i)
	prod:poll()
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
	on_error = function(...) error(...) end,
}
for i = 1,3 do
	prod:produce("sasl_plain_" .. i)
	prod:poll()
end
prod:close()
