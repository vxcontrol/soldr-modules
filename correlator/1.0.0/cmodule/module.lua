require("yaci")
require("strict")
require("waffi.windows.common")
local ffi = require("ffi")
local lk32 = require("waffi.windows.kernel32")

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
    local ctmpdir = ffi.new("char[?]", 256)
    lk32.GetDllDirectoryA(256, ctmpdir)
    lk32.SetDllDirectoryA(__tmpdir)
    self.module = ffi.load(moduleName)
    lk32.SetDllDirectoryA(ctmpdir)
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

    local ctmpdir = ffi.new("char[?]", 256)
    lk32.GetDllDirectoryA(256, ctmpdir)
    lk32.SetDllDirectoryA(__tmpdir)
    self.api.is_inited = self.module_i.init(self.transport, self.profile, #profile)
    lk32.SetDllDirectoryA(ctmpdir)

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
