
__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with payload: %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        -- cmtype: "update_config"

        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

__api.await(-1)

__log.infof("module '%s' was stopped", __config.ctx.name)

return 'success'
