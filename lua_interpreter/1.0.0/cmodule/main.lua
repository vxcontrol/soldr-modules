local glue = require("glue")
local cjson = require("cjson.safe")
local output = ""

local function hooked_print(...)
    local args = glue.pack(...)
    for i=1,args.n do
        output = output .. "\t" .. tostring(args[i])
    end
    output = output .. "\n"
end

__api.add_cbs({
    data = function(src, data)
        __log.infof("receive data from '%s' with data %s", src, data)

        local msg = cjson.decode(data)
        if msg.type ~= nil and msg.type == "exec" then
            local f, err = loadstring(msg.code)
            local resp = {["type"]="response", ["retaddr"]=msg.retaddr}
            if f ~= nil then
                local env = {print=hooked_print}
                setmetatable(env, {__index = _G})
                setfenv(f, env)
                resp.status, resp.ret, resp.err = xpcall(f, debug.traceback)
                resp.output = output
            else
                resp.err = "syntax error : " .. tostring(err)
            end
            __api.send_data_to(src, cjson.encode(resp))
            output = ""
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
