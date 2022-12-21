export LUA_PATH = smodule/?.lua;test/?.lua;;
export LD_LIBRARY_PATH = smodule/clibs/linux/amd64

.PHONY: test
test:
	luajit smodule/rdkafka.test.lua
	luajit smodule/producer.test.lua
