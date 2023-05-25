require("yaci")
require("strict")
local ffi = require("ffi")
local lfs = require("lfs")

ffi.cdef [[
    typedef long (*Module__transport_data_Ptr)(void *transport,
                                               int type, void *data, long size);

    typedef struct _api_module_transport {
        Module__transport_data_Ptr to_module;
        void *module_ptr;
        Module__transport_data_Ptr to_client;
        void *client_ptr;
    } api_module_transport;

    typedef bool (*Module__Init_Ptr)(api_module_transport *transport, const void *profile,
                                     size_t profileSize);
    typedef void (*Module__Void_Ptr)(api_module_transport *transport);

    typedef struct _api_module_interface {

        Module__Init_Ptr init;
        Module__Void_Ptr start;
        Module__Void_Ptr stop;
        Module__Void_Ptr pause;
        Module__Void_Ptr resume;

    } api_module_interface;

    typedef api_module_interface *(*Module_Create_Ptr)(api_module_transport *transport,
                                                       int argc, const char **argv);
    typedef void(*Module_Destroy_Ptr)(api_module_transport *transport);
    typedef int(*Module_Version_Ptr)();

    api_module_interface* module_create(api_module_transport *transport, int argc, const char **argv);
    void module_destroy(api_module_transport *transport);
    int module_version();
]]

CModule = newclass("CModule")

function CModule:init(moduleName)
    -- dependencies loading for linux agent because there is use custom folder for libs
    if ffi.os == "Linux" then
        self.deps = {}
        local ld_lib_dir = __tmpdir .. "/lib"
        for file in lfs.dir(ld_lib_dir) do
            if file ~= "." and file ~= ".." then
                table.insert(self.deps, ffi.load(ld_lib_dir .. "/" .. file))
            end
        end
    end

    self.wrap_load(function ()
        self.module = ffi.load(moduleName)
    end)

    self.api = {
        create = self.module.module_create,
        destroy = self.module.module_destroy,
        version = nil, --self.module.Module__Version,
        is_inited = false,
    }
    self.transport = ffi.new("api_module_transport[1]", {})
end

function CModule:free()
    __log.info("call CModule:free")
    self:unregister()
end

function CModule:unregister()
    __log.info("call CModule:unregister")
    if self.module_i then
        self.module_i.stop(self.transport)
        self.api.destroy(self.transport)
        __log.info("destroy successful")
    end

    if self.functions then
        self.functions["receive"] = nil
    end
    self.functions = nil
    self.transport = nil

    if self.api then
        self.api.create = nil
        self.api.destroy = nil
        self.api.version = nil
        self.api.is_inited = nil
    end
    self.api = nil

    self.module_i = nil
    self.module = nil
    self.profile = nil
    collectgarbage("collect")
    self.deps = nil
    collectgarbage("collect")
end

function CModule:register(profile, callbacks)
    __log.info("call CModule:register")
    assert(type(profile) == "string", "module profile is invalid")
    assert(type(callbacks) == "table", "callbacks is invalid")

    if self.module == nil then
        return false, "module not loaded"
    end

    self.functions = {}

    self.functions["receive"] = function (transport, type, data, size)
        if callbacks and transport == self.transport and callbacks["receive"] then
            return callbacks["receive"](type, data, size)
        end
        return -1
    end

    self.transport[0].to_client = ffi.cast("Module__transport_data_Ptr", self.functions["receive"])

    self.module_i = self.api.create(self.transport, 0, nil)
    self.profile = ffi.new("const char[?]", #profile + 1, profile)

    self.wrap_load(function ()
        self.api.is_inited = self.module_i.init(self.transport, self.profile, #profile)
    end)

    return self.api.is_inited, ""
end

function CModule:start()
    __log.info("call CModule:start")
    if self.api.is_inited == false then
        return
    end

    self.module_i.start(self.transport)
end

function CModule:send(type, data)
    if self.transport[0].to_module == nil then
        return
    end

    local _data
    if #data ~= 0 then
        _data = ffi.cast("void*", data)
    end

    return self.transport[0].to_module(self.transport, type, _data, #data)
end

if ffi.os == "Linux" then
    function CModule.wrap_load(callback)
        callback()
    end
end

if ffi.os == "Windows" then
    function CModule.wrap_load(callback)
        local lk32 = require("waffi.windows.kernel32")
        local ctmpdir = ffi.new("char[?]", 256)
        lk32.GetDllDirectoryA(256, ctmpdir)
        lk32.SetDllDirectoryA(__tmpdir)
        callback()
        lk32.SetDllDirectoryA(ctmpdir)
    end
end
