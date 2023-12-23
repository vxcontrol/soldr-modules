export LUA_PATH = smodule/?.lua;test/?.lua;;

.PHONY: test
test:
	luajit smodule/rdkafka_test.lua
	luajit smodule/producer_test.lua
