require("yaci")
local thread = require("thread")
local luapath = require("path")

CFileReader = newclass("CFileReader")

local worker_safe = function (ctx, q_in, q_out, e_stop, e_quit)
    local pp = require("pp")
    local glue = require("glue")
    local lpath = require("path")
    local socket = require("socket")

    -- custom module loader to take module from __files valiable per module
    local function load(modulename)
        local errmsg = ""
        local modulepath = string.gsub(modulename, "%.", "/")
        local filenames = { modulepath .. "/init.lua", modulepath .. ".lua" }
        for _, filename in ipairs(filenames) do
            local filedata = ctx.__files[filename]
            if filedata then
                return assert(loadstring(filedata, filename), "can't load " .. tostring(modulename))
            end
            errmsg = errmsg .. "\n\tno file '" .. filename .. "' (checked with custom loader)"
        end
        return errmsg
    end
    table.insert(package.loaders, 2, load)

    local print = function (...)
        if ctx.__debug then
            local t = glue.pack(...)
            for i, v in ipairs(t) do
                t[i] = pp.format(v)
            end
            q_out:push({
                type = "debug",
                data = t,
            })
        end
    end

    local function worker()
        require("strict")
        require("module")

        -- INIT --
        local is_close = false
        local mdl = CModule(lpath.combine(ctx.tmpdir, "SysLog"), lpath.combine(ctx.tmpdir, "lib"), print)
        local callbacks = {
            result = function (data)
                if not data then return end
                while q_out:length() == q_out:maxlength() do e_stop:wait(os.time() + 0.1) end
                q_out:push({
                    type = "result",
                    data = data,
                })
            end,
            keep_alive = function ()
                local status, msg
                if e_stop:isset() then
                    print("want to stop file reader library")
                    if not is_close then
                        mdl:stop()
                        is_close = true
                        return
                    end
                end
                repeat
                    status, msg = q_in:shift(os.time())
                    if status and type(msg) == "table" then
                        print("new incoming message to worker", msg.type)
                    end
                until not status
            end,
        }

        mdl:register(ctx.profile, callbacks, ctx.svp_filename)

        -- RUN --
        local res = mdl:run()
        print("run is unlocked: ", res.FinishCode, res.RestartMePlease)
        mdl:unregister()
        collectgarbage("collect")
        print("quit from worker")
    end

    local status, err
    repeat
        status, err = glue.pcall(worker)
        if not status then
            print("failed to execute file reader worker: ", err)
            q_out:push({
                type = "error",
                data = "unexpected exit from worker",
                err = err,
            })
            socket.sleep(5)
        end
        print("quit from worker loop", status, err, e_stop:isset())
        collectgarbage("collect")
    until status or not e_stop:isset()

    -- notify main lua state about library was exited
    e_quit:set()
end

function CFileReader:init(q_in, q_out, e_stop, e_quit, profile, store_dir)
    self.wrth = thread.new(worker_safe, {
        tmpdir = __tmpdir,
        profile = profile,
        svp_filename = luapath.combine(store_dir, "frd_sp"),
        __files = __files,
        __debug = __args["debug_engine"][1] == "true",
        __module_id = tostring(__config.ctx.name),
    }, q_in, q_out, e_stop, e_quit)
end

function CFileReader:wait()
    if self.wrth ~= nil then
        self.wrth:join()
        self.wrth = nil
    end
end
