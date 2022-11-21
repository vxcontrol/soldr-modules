for idx, item in ipairs(arg) do
    print(string.format("ARG[%d] %s", idx, item))
end

local lua_path = os.getenv("LUA_PATH")
if lua_path then package.path = lua_path end

local lua_cpath = os.getenv("LUA_CPATH")
if lua_cpath then package.cpath = lua_cpath end

-- Busted command-line runner
require 'busted.runner' ({ standalone = false })
