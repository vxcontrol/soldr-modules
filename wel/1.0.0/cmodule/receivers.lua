local Receivers = {}; Receivers.__index = Receivers

--:: () -> Receivers
function Receivers.new()
	return setmetatable({}, Receivers)
end

--:: [string] -> ()
function Receivers:configure(modules)
	for name, _ in pairs(self) do
		self[name] = nil
	end
	for _, name in ipairs(modules) do
		self[name] = {token = __imc.make_token(name, __gid)}
	end
end

function Receivers:receive(data)
	for _, module in pairs(self) do
		-- TODO: check the result
		__api.send_data_to(module.token, data)
	end
end

return Receivers
