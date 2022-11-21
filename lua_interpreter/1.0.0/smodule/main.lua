local cjson = require("cjson.safe")

-- getting agent ID by dst token and agent type
local function get_agent_id_by_dst(dst, atype)
    for client_id, client_info in pairs(__agents.get_by_dst(dst)) do
        if client_id == dst then
            if tostring(client_info.Type) == atype then
                return tostring(client_info.ID), client_info
            end
        end
    end
    return "", {}
end

__api.add_cbs({
    data = function(src, data)
        __log.debugf("receive data from '%s' with data %s", src, data)

        local msg = cjson.decode(data)
        local vxagent_id = get_agent_id_by_dst(src, "VXAgent")
        local bagent_id = get_agent_id_by_dst(src, "Browser")
        local eagent_id = get_agent_id_by_dst(src, "External")
        if vxagent_id ~= "" then
            if msg.type ~= nil and msg.type == "response" then
                local browser_id = msg.retaddr
                msg.retaddr = nil
                __api.send_data_to(browser_id, cjson.encode(msg))
            end
        else
            -- msg from browser or external...
            if msg.type ~= nil and msg.type == "exec" then
                local agent_id = bagent_id ~= "" and bagent_id or eagent_id
                for client_id, client_info in pairs(__agents.get_by_id(agent_id)) do
                    if tostring(client_info.Type) == "VXAgent" then
                        msg.retaddr = src
                        __api.send_data_to(client_id, cjson.encode(msg))
                        break
                    end
                end
            end
        end
        return true
    end,

    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with data %s", cmtype, data)

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

return "success"