local cjson = require "cjson"

local function get_server_token()
	for _, agent in pairs(__agents.dump()) do
		return agent.Dst
	end
	return nil
end

__api.add_cbs{
	-- Resend the content of action to a server.
	action = function(src, data, name)
		return __api.send_data_to(get_server_token(), data)
	end,

	-- Trick for PT WinEventLog module.
	data = function(src, data)
		local token = get_server_token()
		local records = cjson.decode(data)
		local result = true
		for _, r in ipairs(records or {}) do
			local data = cjson.encode{data=r}
			result = result and __api.send_data_to(token, data)
		end
		return result
	end,
}

__api.await(-1)
return 'success'
