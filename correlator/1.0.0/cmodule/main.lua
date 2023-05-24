require("engines.acts_engine")

-- base config to actions engine
local cfg = {
    config = {}
}

-- actions engine initialize
local acts_engine = CActsEngine(cfg)

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function(src, data)
        __log.debugf("receive data from '%s' with data", src)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_data(src, data)
    end,

    file = function(src, path, name)
        __log.infof("receive file from '%s' with name '%s' path '%s'", src, name, path)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        return acts_engine:recv_file(src, path, name)
    end,

    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function(src, data, name)
        __log.infof("receive action '%s' from '%s' with data %s", name, src, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        local action_result = acts_engine:recv_action(src, data, name)
        __log.infof("requested action '%s' was executed: %s", name, action_result)
        return action_result
    end,

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with data %s", cmtype, data)
        assert(acts_engine ~= nil, "actions engine instance is not initialized")

        if cmtype == "quit" then
            acts_engine:quit()
        end
        if cmtype == "agent_connected" then
            acts_engine:agent_connected(data)
        end
        if cmtype == "agent_disconnected" then
            acts_engine:agent_disconnected(data)
        end
        if cmtype == "update_config" then
            acts_engine:update_config()
        end

        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)
acts_engine:run()
__api.del_cbs({ "data", "file", "action", "control" })
__log.infof("module '%s' was stopped", __config.ctx.name)

-- explicit destroy engine
__log.info("before destroy correlator phase")
if acts_engine.correlator ~= nil then
    acts_engine.correlator:free()
    acts_engine.correlator = nil
end
collectgarbage("collect")

__log.info("after destroy correlator phase")
if acts_engine.event_engine ~= nil then
    acts_engine.event_engine:free()
    acts_engine.event_engine = nil
end
if acts_engine.action_engine ~= nil then
    acts_engine.action_engine:free()
    acts_engine.action_engine = nil
end
acts_engine = nil
collectgarbage("collect")

return "success"
