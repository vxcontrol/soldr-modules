require("yaci")
local thread = require("thread")
local luapath = require("path")
local cjson = require("cjson.safe")

CFileReader = newclass("CFileReader")

local worker_safe = function(ctx, q_in, q_out, e_stop, e_quit)
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

    local print = function(...)
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
            result = function(data)
                if not data then
                    return
                end
                while q_out:length() == q_out:maxlength() do
                    e_stop:wait(os.time() + 0.1)
                end
                q_out:push({
                    type = "result",
                    data = data,
                })
            end,

            keep_alive = function()
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

local function get_profile(log_entries)
    local params = {
        scope_id = "00000000-0000-0000-0000-000000000005",
        tenant_id = "00000000-0000-0000-0000-000000000000",
    }
    local config_json = string.format(
        [[{
        "servers": {
            "tcp_and_udp": {
                "tcp": {
                    "binding": {
                        "FQDN": "0.0.0.0"
                    },
                    "port": 0,
                    "message_size_max": 1048576
                },
                "udp": {
                    "binding": {
                        "IP4": "0.0.0.0"
                    },
                    "port": 0,
                    "read_buffer_size": 65536
                }
            }
        },
        "event_buffer_size": 512,
        "output_format": "JSON",
        "special_events_assembly_settings": {
            "assembly_interval": 1,
            "event_record_groups": {
                "auditd": {
                    "key_includes_src_ip": false,
                    "key_fields_from_records": [
                        "timestamp",
                        "eventid"
                    ],
                    "filter_regexps": [
                        ".*type=(?P<type>\\S+)\\s.*audit.*\\((?P<timestamp>[0-9]*[.,]?[0-9]+):(?P<eventid>[0-9]+)\\):\\s*(?P<value>.*)"
                    ],
                    "group_by_field_settings": {
                        "regex_group_for_field_name": "type",
                        "regex_group_for_value": "value"
                    }
                }
            }
        },
        "inputs": {
            "00000000-0000-0000-0000-000000000000": {
                "description": {
                    "expected_datetime_formats": [
                        "DATETIME_ISO8601",
                        "DATETIME_YYYYMMDD_HHMMSS"
                    ]
                }
            }
        },
        "result_package": {
            "package_quantity": 100,
            "send_interval": 500
        },
        "module_settings": {
            "keepalive_interval": 500,
            "metric": false,
            "scope_id": "%s",
            "tenant_id": "%s",
            "logging": "<?xml version='1.0' encoding='utf-8'?><config><root><Logger level='ERROR'/><Metric level='ERROR'/><SysLog level='ERROR'/><ModuleRunner level='ERROR'/><ModuleHost level='ERROR'/></root></config>",
            "agent_id": "",
            "task_id": "",
            "historical": false
        },
        "memory_settings": {
            "chunk_size": 1024,
            "pre_allocated_memory": 3,
            "max_allowed_memory": 64
        }
    }]],
        tostring(params.scope_id),
        tostring(params.tenant_id)
    )

    local config = cjson.decode(config_json)
    config["log_channels"] = log_entries

    return cjson.encode(config)
end

function CFileReader:init(q_in, q_out, e_stop, e_quit, log_entries, store_dir)
    self.wrth = thread.new(worker_safe, {
        tmpdir = __tmpdir,
        profile = get_profile(log_entries),
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

function CFileReader:rewind(store_dir, filename)
    local svp_filename = luapath.combine(store_dir, "frd_sp")
    local savepoint = {}
    local file = io.open(svp_filename, "r")
    if file then
        savepoint = cjson.decode(file:read("*a"))
        io.close(file)
    end
    savepoint[filename] = { pos = -1 }
    file = io.open(svp_filename, "wb+")
    file:write(cjson.encode(savepoint))
    file:flush()
    file:close()
end
