local _ffi = require("ffi")
local _lfs = require("lfs")
local _path = require("path")
local _thread = require("thread")
local _load = _ffi.load
local _init_state = _thread.init_state
local _get_clib_path = function(name)
    local prev, i = _lfs.currentdir(), 0
    while arg[i] do prev = _path.dir(arg[i]); i=i-1 end
    local ext = _ffi.os == "Windows" and ".dll" or ".so"
    return _path.combine(_path.combine(prev, "clib"), name..ext)
end
_ffi.load = function(name, global)
    local clib_path = _get_clib_path(name)
    clib_path = _lfs.attributes(clib_path, "size") or name
    return _load(clib_path, global)
end
_thread.init_state = function(state)
    _init_state(state)
	state:getglobal("package")
	state:pushstring(package.path)
	state:setfield(-2, "path")
	state:getglobal("package")
	state:pushstring(package.cpath)
	state:setfield(-2, "cpath")
    state:push(function()
        local function do_lua_file(filename, ...)
            local f = assert(io.open(filename))
            local str = f:read "a"
            f:close()
            return assert(load(str, "=(debugger.lua)"), "failed to load debugger.lua")(...)
        end

        local debug_path = os.getenv("LUA_DEBUG_PATH")
        if debug_path then
            return do_lua_file(debug_path .. "/script/debugger.lua", debug_path)
                :attach({})
                :event("wait")
        end
    end)
    state:pcall()
end
