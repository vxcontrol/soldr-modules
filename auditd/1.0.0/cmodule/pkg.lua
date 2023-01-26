-- Replaces each occurrence of `{name}` in cmd with the corrensponding
-- value of key `name` from table vars.
--:: string, {string => string} -> string
function format_cmd(cmd, vars)
	for name, var in pairs(vars) do
		cmd = string.gsub(cmd, "{"..name.."}", var)
	end
	return cmd
end

local Manager = {}; Manager.__index = Manager

function Manager.new(backend)
	return setmetatable({backend=backend}, Manager)
end

--:: string -> ok::boolean, err::string?
function Manager:install(package)
end

local pacman = Manager.new{
	install = "pacman -S --noconfirm {package}",
}

return {
	testing = {format_cmd = format_cmd},
}
