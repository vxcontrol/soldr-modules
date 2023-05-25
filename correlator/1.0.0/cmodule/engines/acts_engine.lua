require("yaci")
require("strict")
require("engines.base_engine")
require("engines.corr_engine")

local rex = require("rex_pcre2")
local json = require("cjson.safe")

CActsEngine = newclass("CActsEngine", CBaseEngine)

--[[
    cfg top keys:
    * config - module arguments (hard limits)
]]
function CActsEngine:init(cfg)
    __log.debug("init CActsEngine object")
    assert(type(cfg) == "table", "configuration object has invalid type")

    cfg.engine = "acts_engine"
    self.super:init(cfg)

    self.correlator = CCorrEngine(
        function (event)
            self:push_result(event)
        end
    )

    if not self.correlator.valid then
        __log.info("try to restore correlator instance")
        self.correlator = CCorrEngine(
            function (event)
                self:push_result(event)
            end,
            true
        )
    end

    self.excludes = {}
    self.proc_id_fields = {
        "object.process.id",
        "object.process.parent.id",
        "subject.process.id",
        "subject.process.parent.id",
    }

    self.topic_name = "raw_events"
    if __imc.subscribe_to_topic then
        assert(__imc.subscribe_to_topic(self.topic_name, __gid), "can't subscribe to topic")
    else
        __log.debug("topics mechanism unsupported on agent side")
    end

    -- initialization of object after base class constructing
    self:update_config_cb()
end

-- in: nil
-- out: nil
function CActsEngine:free()
    __log.debug("finalize CActsEngine object")

    -- here will be triggered after closing vxproto object (destructor of the state)
end

-- in: nil
-- out: number
--      amount of milliseconds timeout to wait next call of the timer_cb
function CActsEngine:timer_cb()
    -- __log.debug("timer_cb CActsEngine")
    local acts_engine = CActsEngine:cast(self)
    acts_engine.correlator:pullEvents()
    __metric.add_int_gauge_counter("corr_agent_mem_usage", collectgarbage("count") * 1024)
    return 500
end

-- in: nil
-- out: nil
function CActsEngine:quit_cb()
    __log.debug("quit_cb CActsEngine")

    -- here will be triggered before closing vxproto object and destroying the state
    if __imc.unsubscribe_from_topic then
        assert(__imc.unsubscribe_from_topic(self.topic_name, __gid), "can't unsubscribe from topic")
    end
end

-- in: string
--      destination token (string) of server module side
-- out: nil
function CActsEngine:agent_connected_cb(dst)
    __log.debugf("agent_connected_cb CActsEngine with token '%s'", dst)
end

-- in: string
--      destination token (string) of server module side
-- out: nil
function CActsEngine:agent_disconnected_cb(dst)
    __log.debugf("agent_disconnected_cb CActsEngine with token '%s'", dst)
end

-- in: nil
-- out: nil
function CActsEngine:update_config_cb()
    __log.debug("update_config_cb CActsEngine")

    local acts_engine = CActsEngine:cast(self)
    acts_engine:load_excludes()

    -- actual current configuration contains into next fields
    -- self.config.actions
    -- self.config.events
    -- self.config.module
end

-- in: string, string
--      source token (string) of sender module side
--      data payload (string) as a custom string serialized struct object (json)
-- out: boolean
--      result of data processing from business logic
function CActsEngine:recv_data_cb(src, data)
    __log.debugf("perform custom logic for data with payload len %d from '%s'", #data, src)

    local acts_engine = CActsEngine:cast(self)
    local odata, err = json.decode(data)
    if not odata then
        __log.errorf("failed to parse events packet: %s", err)
        return true
    end

    if acts_engine.correlator then
        __metric.add_int_counter("corr_agent_events_recv_count", #odata)
        __metric.add_int_counter("corr_agent_events_recv_size", #data)

        for _, v in ipairs(odata) do
            if v.mime == "application/x-pt-eventlog" or v.mime == "application/json" then
                v.body = json.encode(v.body)
            end
            while acts_engine.correlator:sendEvent(json.encode(v)) == false do
                __api.await(50)
            end
        end
    else
        __metric.add_int_counter("corr_agent_events_drop", #odata)
    end

    return true
end

-- in: string, string, string
--      source token (string) of sender module side
--      file path (string) on local FS where received file was stored
--      file name (string) is a original file name which was set on sender side
-- out: boolean
--      result of file processing from business logic
function CActsEngine:recv_file_cb(src, path, name)
    __log.debugf("perform custom logic for file with path '%s' and name '%s' from '%s'", path, name, src)
    return true
end

-- in: string, string, table
--      source token (string) of sender module side
--      action name (string) to execute it into the acts_engine
--      action data (table) as a arguments to execute action via acts_engine
--        e.x. {"data": {"key": "val"}, "actions": ["mod1.act1"]}
-- out: boolean
--      result of action processing from business logic
function CActsEngine:recv_action_cb(src, data, name)
    __log.debugf("perform custom logic for action '%s' from '%s'", name, src)

    local acts_engine = CActsEngine:cast(self)
    if name == "some_action" then
        return acts_engine:dummy(data.data["arg"])
    end

    return false
end

-- in: nil
-- out: nil
function CActsEngine:load_excludes()
    self.excludes = {}
    for _, exclude in ipairs(self.config.module.excludes) do
        local compiled = {}
        for _, cond in ipairs(exclude) do
            if type(cond) ~= "table" then
                __log.errorf("condition isn't a table (array) value: '%s'", json.encode(cond))
                goto continue
            end
            if type(cond.fields) ~= "table" then
                __log.errorf("fields isn't a table (array) value: '%s'", json.encode(cond.fields))
                goto continue
            end
            if #cond.fields == 0 then
                __log.errorf("fields is empty array")
                goto continue
            end
            for _, field in ipairs(cond.fields) do
                if type(field) ~= "string" then
                    __log.errorf("field isn't a string value: '%s'", json.encode(field))
                    goto continue
                end
            end
            if type(cond.regex) ~= "string" then
                __log.errorf("regex isn't a string value: '%s'", json.encode(cond.regex))
                goto continue
            end
            local status, regex = pcall(rex.new, cond.regex)
            if not status then
                __log.errorf("can't compile regexp: '%s' with error '%s'", cond.regex, regex)
                goto continue
            end
            table.insert(compiled, {
                fields = cond.fields,
                sregex = cond.regex,
                cregex = regex,
            })
            ::continue::
        end
        if #compiled ~= 0 then
            table.insert(self.excludes, compiled)
        end
    end
    __log.infof("loaded %d excludes from '%s'", #self.excludes, json.encode(self.config.module.excludes))
end

-- in: table
-- out: bool, table
function CActsEngine:match_excludes(event)
    local body = {}
    for fname, fvalue in pairs(event) do
        if type(fname) ~= "string" then
            fname = tostring(fname) or ""
        end
        if type(fvalue) ~= "string" then
            fvalue = json.encode(fvalue) or ""
        end
        body[fname] = fvalue
    end

    for _, exclude in ipairs(self.excludes) do
        local matches = {}
        for _, cond in ipairs(exclude) do
            for _, fname in ipairs(cond.fields) do
                local fvalue = body[fname]
                if not fvalue then
                    -- field '{fname}' isn't exist in body
                    goto next_field
                end
                local match = cond.cregex:match(fvalue)
                if match then
                    table.insert(matches, {
                        field = fname,
                        match = match,
                        regex = cond.sregex,
                        value = fvalue,
                    })
                    -- field '{fname}' with value '{fvalue}' matches '{match}' by regex '{cond.sregex}'
                    __log.debugf("field '%s' with value '%s' matches '%s' by regex '%s'", fname, fvalue, match, cond.sregex)
                    goto next_condition
                end
                -- field '{fname}' with value '{fvalue}' doesn't match by regex '{cond.sregex}'
                __log.debugf("field '%s' with value '%s' doesn't match by regex '%s'", fname, fvalue, cond.sregex)
                ::next_field::
            end
            -- fields '{cond.fields}' don't match by regex '{cond.sregex}'
            __log.debugf("fields '%s' don't match by regex '%s'", json.encode(cond.fields), cond.sregex)
            goto next_exclude
            ::next_condition::
        end
        if #matches == #exclude then
            __log.debugf("all exclude conditions matched with event body '%s'", json.encode(matches))
            return true, matches
        end
        ::next_exclude::
    end

    return false
end

-- in: table
-- out: nil
function CActsEngine:push_result(event)
    local oevent = json.decode(event)
    if type(oevent) ~= "table" then
        __log.errorf("failed to parse event from correlator: %s", tostring(event))
        return
    end
    local event_name = oevent["_rule"]
    local result = oevent

    if event_name == nil or event_name == "" then return end

    local config_events = self.config["events"] or { events = {} }
    local config_event = config_events[event_name] or { fields = {} }
    local config_fields = self.config["fields"] or { properties = {} }
    local _fields = config_event["fields"] or {}
    local defaults = { string = "", number = 0, integer = 0, object = {}, array = {}, boolean = false, null = nil }

    for _, v in ipairs(self.proc_id_fields) do
        result[v] = tonumber(result[v])
    end
    for _, v in ipairs(_fields) do
        result[v] = result[v] or defaults[(config_fields.properties[v] or {}).type or "null"]
    end

    __log.debugf("perform logic to push result: '%s'", json.encode(result))
    if not self:match_excludes(result) then
        self:push_event(event_name, result)
    end
end
