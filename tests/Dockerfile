FROM ubuntu:20.04

RUN apt update; apt install -y --no-install-recommends systemctl

ENV APP_PATH=/soldr-modules \
    LUAPOWER_PLATFORM=linux64

ENV LUA_PATH=$APP_PATH/tests_framework/lua/?.lua;$APP_PATH/tests_framework/lua/?/init.lua;$APP_PATH/luapower/?.lua;$APP_PATH/luapower/?/init.lua;$APP_PATH/utils/?.lua;$APP_PATH/utils/?/init.lua \
    LUA_CPATH=$APP_PATH/luapower/bin/$LUAPOWER_PLATFORM/lib?.dylib;$APP_PATH/luapower/bin/$LUAPOWER_PLATFORM/clib/?.so; \
    LUA_BIN=$APP_PATH/luapower/bin/$LUAPOWER_PLATFORM/luajit-bin

ENTRYPOINT ["/bin/bash"]
