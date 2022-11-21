require("yaci")
require("strict")
local ffi = require("ffi")

ffi.cdef [[
    // Сигнатура колбэка для возврата ошибок
    typedef void(*Module__Error_Ptr)(const char* descr, void* userData);

    // Структура для возврата ошибок
    typedef struct _Module__ErrorHandler
    {
        Module__Error_Ptr OnError; // колбэк
        void* UserData; // произвольные данные, юзер может их использовать для проброса в колбэк доп. инфы
    } Module__ErrorHandler;

    // Результат модуля
    typedef struct _Module__ResultInfo
    {
        int Type;       // тип результата
        int Format;     // формат результата
        int Encoding;   // кодировка
    } Module__ResultInfo;

    // Результат завершения модуля
    typedef struct _Module__FinishResult
    {
        int     FinishCode;         // код завершения
        bool    RestartMePlease;    // сообщить агенту, что модуль надо рестартануть
    } Module__FinishResult;

    typedef struct Module_I Module_I;

    typedef void(*Module__Init_Ptr)(Module_I* module, const void* profile, size_t profileSize, const void* savepoint, size_t savepointSize, const Module__ErrorHandler* eh);
    typedef Module__FinishResult(*Module__Run_Ptr)(Module_I* module, const Module__ErrorHandler* eh);
    typedef void(*Module__Stop_Ptr)(Module_I* module, const Module__ErrorHandler* eh);
    typedef void(*Module__Pause_Ptr)(Module_I* module, const Module__ErrorHandler* eh);
    typedef void(*Module__Resume_Ptr)(Module_I* module, const Module__ErrorHandler* eh);
]]
if ffi.arch == 'x86' then
    ffi.cdef [[
    // Параметр info оригинальной сигнатуры раскладывается на стек по элементно
    typedef bool(*Module__OnResult_Ptr)(Module_I* module, const char* jobId, int type, int format, int encoding, const void* data, size_t size, const Module__ErrorHandler* eh);
]]
end
if ffi.arch == 'x64' then
    ffi.cdef [[
    // Параметр info оригинальной сигнатуры передаётся через указатель, чтобы не кастовать каждый элемент в отдельности, заранее определяем его как указатель на int
    typedef bool(*Module__OnResult_Ptr)(Module_I* module, const char* jobId, int info, const void* data, size_t size, const Module__ErrorHandler* eh);
]]
end
ffi.cdef [[
  typedef const char*(*Module__GetName_Ptr)(Module_I* module, const Module__ErrorHandler* eh);

  // Интерфейс модуля
  struct Module_I
    {
        // Указатель на функцию, которая вызывается при получении пакета "Старт" от агента
        Module__Init_Ptr Init;

        /** Указатель на функцию, реализующую логику модуля.
            Вызов этой функции происходит в отдельном потоке после вызова функции "Init"
        */
        Module__Run_Ptr Run;

        // Указатель на функцию, реализающую остановку модуля
        Module__Stop_Ptr Stop;

        // Указатель на функцию, реализающую паузу модуля
        Module__Pause_Ptr Pause;

        // Указатель на функцию, реализающую возобновление работы модуля
        Module__Resume_Ptr Resume;

        // Указатель на функцию, которая будет вызвана для результатов, пришедших от других модулей
        Module__OnResult_Ptr OnResult;

        // Указатель на функцию, возвращающую уникальный идентификатор модуля
        Module__GetName_Ptr GetName;
    };

    typedef struct ModuleTransport_I ModuleTransport_I;

    typedef void(*ModuleTransport__SendKeepAlive_Ptr)(ModuleTransport_I* transport, const Module__ErrorHandler* eh);
    typedef void(*ModuleTransport__SendProgress_Ptr)(ModuleTransport_I* transport, uint32_t progress, const Module__ErrorHandler* eh);
]]
if ffi.os == "Windows" then
    if ffi.arch == 'x86' then
        ffi.cdef [[
        // Параметр info оригинальной сигнатуры раскладывается на стек по элементно
        typedef void(*ModuleTransport__SendResult_Ptr)(ModuleTransport_I* transport, int type, int format, int encoding, const void* data, size_t size, const Module__ErrorHandler* eh);
    ]]
    end
    if ffi.arch == 'x64' then
        ffi.cdef [[
        // Параметр info оригинальной сигнатуры передаётся через указатель, чтобы не кастовать каждый элемент в отдельности, заранее определяем его как указатель на int
        typedef void(*ModuleTransport__SendResult_Ptr)(ModuleTransport_I* transport, int *info, const void* data, size_t size, const Module__ErrorHandler* eh);
    ]]
    end
end

if ffi.os == "Linux" then
    if ffi.arch == 'x86' then
        ffi.cdef [[
        // Параметр info оригинальной сигнатуры раскладывается на стек по элементно
        typedef void(*ModuleTransport__SendResult_Ptr)(ModuleTransport_I* transport, int type, int format, int encoding, const void* data, size_t size, const Module__ErrorHandler* eh);
    ]]
    end
    if ffi.arch == 'x64' then
        ffi.cdef [[
        // Параметр info оригинальной сигнатуры передаётся через указатель, чтобы не кастовать каждый элемент в отдельности, заранее определяем его как указатель на int
        typedef void(*ModuleTransport__SendResult_Ptr)(ModuleTransport_I* transport, int *info, int i, const void* data, size_t size, const Module__ErrorHandler* eh);
    ]]
    end
end
ffi.cdef [[
    typedef void(*ModuleTransport__SendSavePoint_Ptr)(ModuleTransport_I* transport, const void* data, size_t size, const Module__ErrorHandler* eh);
    typedef void(*ModuleTransport__SendState_Ptr)(ModuleTransport_I* transport, int state, const Module__ErrorHandler* eh);
    typedef void(*ModuleTransport__SendError_Ptr)(ModuleTransport_I* transport, const void* data, size_t size, const Module__ErrorHandler* eh);

    // Интерфейс транспорта модуля
    struct ModuleTransport_I
    {
        ModuleTransport__SendKeepAlive_Ptr SendKeepAlive;
        ModuleTransport__SendProgress_Ptr SendProgress;
        ModuleTransport__SendResult_Ptr SendResult;
        ModuleTransport__SendSavePoint_Ptr SendSavePoint;
        ModuleTransport__SendState_Ptr SendState;
        ModuleTransport__SendError_Ptr SendError;
    };

    // Экспортируемые функции из dll-ки модуля

    /** Создать модуль.
    ** @param transport
    **     Указатель на транспорт, который модуль должен использовать для отправки сообщений.
    **     Модуль не должен удалять этот указатель!
    ** @param argc, argv
    **     Аргументы, с которыми был запущен агентом модуль.
    ** @param eh
    **     Структура для возврата ошибок.
    */
    Module_I* Module__Create(ModuleTransport_I* transport, int argc, const char** argv, const Module__ErrorHandler* eh);

    // Удалить ранее созданный модуль
    void Module__Destroy(Module_I* module);

    // Вернуть версию модуля
    int Module__Version();

    // Вернуть версию API, которую реализует модуль
    int Module__API_Version();
]]


CModule = newclass("CModule")

function CModule:init(moduleName, libdir, fprint)
    assert(type(moduleName) == "string", "module name is invalid")
    assert(type(libdir) == "string", "library directory path is invalid")
    self.print = type(print) == "function" and fprint or print
    self:unregister()
    self.libdir = libdir
    if ffi.os == "Linux" then self:load_depends() end
    self:wrap_load(function()
        if ffi.os == "Linux" then
            self.module = ffi.load(moduleName .. ".so")
        else
            self.module = ffi.load(moduleName .. ".dll")
        end
    end)
    self.api = {
        create = self.module.Module__Create,
        destroy = self.module.Module__Destroy,
        version = self.module.Module__Version,
        api_version = self.module.Module__API_Version,
    }
    self.sd = ""
end

function CModule:free()
    self.print("call CModule:free")
    self.deps = nil
    self:unregister()
end

function CModule:unregister()
    self.print("call CModule:unregister")
    if self.module_i then
        self:destroy()
        self.print("destroy successful")
    end

    if self.functions then
        self.functions["SendKeepalive"] = nil
        self.functions["SendProgress"] = nil
        self.functions["SendResult"] = nil
        self.functions["SendSavepoint"] = nil
        self.functions["SendState"] = nil
        self.functions["SendError"] = nil
        self.functions["HandleError"] = nil
    end
    self.functions = nil
    self.error = nil

    if self.transport then
        self.transport.SendKeepAlive = nil
        self.transport.SendProgress = nil
        self.transport.SendResult = nil
        self.transport.SendSavePoint = nil
        self.transport.SendState = nil
        self.transport.SendError = nil
    end
    self.transport = nil

    if self.api then
        self.api.create = nil
        self.api.destroy = nil
        self.api.version = nil
        self.api.api_version = nil
    end
    self.api = nil

    self.module_i = nil
    self.module = nil

    self.profile = nil
    self.argv_type = nil
    self.argc = nil
    self.argv = nil
    self.sp_filename = nil
    self.sd = nil
    collectgarbage("collect")
end

function CModule:register(profile, callbacks, sp_filename)
    self.print("call CModule:register")
    assert(type(profile) == "string", "module profile is invalid")
    assert(type(callbacks) == "table", "callbacks is invalid")
    assert(type(sp_filename) == "string", "savepoint file path is invalid")

    if self.module == nil then
        return false, "module not loaded"
    end

    local function get_argv(...)
        local nargs = select("#", ...)
        local argv = {...}

        for i = 1, nargs do
            local v = tostring(argv[i])
            argv[i] = v
        end

        return nargs, self.argv_type(nargs, argv)
    end

    self.functions = {}

    self.functions["SendKeepalive"] = function(transport, _)
        if callbacks and transport == self.transport and callbacks["keep_alive"] then
            callbacks["keep_alive"]()
        end
    end

    self.functions["SendProgress"] = function(transport, progress, _)
        if callbacks and transport == self.transport and callbacks["progress"] then
            callbacks["progress"](progress)
        end
    end

    if ffi.os == "Windows" then
        if ffi.arch == 'x86' then
            self.functions["SendResult"] = function(transport, _, _, _, data, size, _)
                if callbacks and transport == self.transport and callbacks["result"] and data then
                    callbacks["result"](ffi.string(data, size))
                end
            end
        end
        if ffi.arch == 'x64' then
            self.functions["SendResult"] = function(transport, _, data, size, _)
                if callbacks and transport == self.transport and callbacks["result"] and data then
                    callbacks["result"](ffi.string(data, size))
                end
            end
        end
    end

    if ffi.os == "Linux" then
        if ffi.arch == 'x86' then
            self.functions["SendResult"] = function(transport, _, _, _, data, size, _)
                if callbacks and transport == self.transport and callbacks["result"] and data then
                    callbacks["result"](ffi.string(data, size))
                end
            end
        end
        if ffi.arch == 'x64' then
            self.functions["SendResult"] = function(transport, _, _, data, size, _)
                if callbacks and transport == self.transport and callbacks["result"] and size and data then
                    callbacks["result"](ffi.string(data, size))
                end
            end
        end
    end

    self.functions["SendSavepoint"] = function(transport, data, size, _)
        if data and size ~= 0 then
            local sd = ffi.string(data, size)
            if callbacks and transport == self.transport and callbacks["save_point"] and size and data then
                callbacks["save_point"](sd)
            end
            if self.sp_filename and sd and (#self.sd == 0 or self.sd ~= sd) then
                self.sd = sd
                local file = io.open(self.sp_filename, "wb+")
                if file then
                    file:write(sd)
                    file:flush()
                    file:close()
                end
                return
            end
        end
    end

    self.functions["SendState"] = function(transport, state, _)
        if callbacks and transport == self.transport and callbacks["state"] then
            callbacks["state"](state)
        end
    end

    self.functions["SendError"] = function(transport, data, size, _)
        if callbacks and transport == self.transport and callbacks["error"] then
            callbacks["error"](ffi.string(data, size))
        end
    end

    self.functions["HandleError"] = function(descr, _)
        self.print("file reader library handled error: ", ffi.string(descr))
    end

    self.error = ffi.new("Module__ErrorHandler", {ffi.cast("Module__Error_Ptr", self.functions["HandleError"]), nil})
    self.transport = ffi.new("ModuleTransport_I", {
        ffi.cast("ModuleTransport__SendKeepAlive_Ptr", self.functions["SendKeepalive"]),
        ffi.cast("ModuleTransport__SendProgress_Ptr", self.functions["SendProgress"]),
        ffi.cast("ModuleTransport__SendResult_Ptr", self.functions["SendResult"]),
        ffi.cast("ModuleTransport__SendSavePoint_Ptr", self.functions["SendSavepoint"]),
        ffi.cast("ModuleTransport__SendState_Ptr", self.functions["SendState"]),
        ffi.cast("ModuleTransport__SendError_Ptr", self.functions["SendError"])
    })
    self.argv_type = ffi.typeof("const char* [?]")
    self.argc, self.argv = get_argv("--id", "692db8c2-9d54-11eb-a8b3-0242ac130003")

    self.module_i = self.api.create(self.transport, self.argc, self.argv, self.error)
    self.sp_filename = sp_filename

    -- SAVEPOINT--
    local svp = ""

    if sp_filename then
        local file = io.open(self.sp_filename, "rb")
        if file then
            svp = file:read("*a")
            file:close()
        end
    end

    self.module_i.Init(self.module_i,
        ffi.cast("const void*", profile),
        #profile, svp, #svp, self.error)
    return true, ""
end

function CModule:destroy()
    self.print("call CModule:destroy")
    assert(self.module, "module library is not exist")
    assert(self.module_i, "instance module is not exist")
    self.api.destroy(self.module_i)
end

function CModule:registered()
    self.print("call CModule:registered")
    return self.transport ~= nil
end

function CModule:run()
    self.print("call CModule:run")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Run(self.module_i, self.error)
end

function CModule:stop()
    self.print("call CModule:stop")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Stop(self.module_i, self.error)
end

function CModule:pause()
    self.print("call CModule:pause")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Pause(self.module_i, self.error)
end

function CModule:resume()
    self.print("call CModule:resume")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Resume(self.module_i, self.error)
end

function CModule:version()
    self.print("call CModule:version")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Module__Version()
end

function CModule:version_api()
    self.print("call CModule:version_api")
    assert(self.module_i, "instance module is not exist")
    return self.module_i.Module__API_Version()
end

if ffi.os == "Linux" then
    function CModule:load_depends()
        local lfs   = require("lfs")
        local lpath = require("path")
        self.deps = {}
        for file in lfs.dir(self.libdir) do
            if file ~= "." and file ~= ".." then
                table.insert(self.deps, ffi.load(lpath.combine(self.libdir, file)))
            end
        end
    end

    function CModule:wrap_load(callback)
        local _ = self
        callback()
    end
end

if ffi.os == "Windows" then
    function CModule:wrap_load(callback)
        local lk32 = require("waffi.windows.kernel32")
        local ctmpdir = ffi.new("char[?]", 256)
        local stmpdir = ffi.new("char[?]", #self.libdir + 1)
        ffi.copy(stmpdir, self.libdir)
        lk32.GetDllDirectoryA(256, ctmpdir)
        lk32.SetDllDirectoryA(stmpdir)
        callback()
        lk32.SetDllDirectoryA(ctmpdir)
    end
end
