export LUA_PATH = smodule/?.lua;test/?.lua;;

.PHONY: test
test:
	luajit smodule/rdkafka.test.lua
	luajit smodule/producer.test.lua
