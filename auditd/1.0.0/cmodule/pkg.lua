local exec = require "exec"

-- Replaces each occurrence of `{name}` in cmd with the corresponding
-- value of key `name` from table vars.
--:: string, {string => string} -> string
local function format_cmd(cmd, vars)
	for name, var in pairs(vars) do
		cmd = string.gsub(cmd, "{"..name.."}", var)
	end
	return cmd
end

-- Manager is an abstraction over system package managers.
-- See the list of supported package managers below.
local Manager = {}; Manager.__index = Manager

local backend_commands = {
	test    = "type {bin}",
	sync    = "false",
	install = "false",
}

function Manager.new(name, bin, commands)
	commands = commands or {}
	for type, cmd in pairs(backend_commands) do
		commands[type] = commands[type] or cmd
	end
	return setmetatable({
		name = name,
		bin  = bin,
		_cmd = commands,
	}, Manager)
end

-- Tests if the manager is available on current OS.
--:: () -> ok::boolean, err::string?
function Manager:test()
	local cmd = format_cmd(self._cmd.test, {name=self.name, bin=self.bin})
	return exec(cmd)
end

-- Used to synchronize the package index files from their sources.
--:: () -> ok::boolean, err::string?
function Manager:sync()
	local cmd = format_cmd(self._cmd.sync, {name=self.name, bin=self.bin})
	return exec(cmd)
end

-- Performs installation procedure for the given package.
--:: string -> ok::boolean, err::string?
function Manager:install(package)
	local cmd = format_cmd(self._cmd.install,
			{name=self.name, bin=self.bin, package=package})
	return exec(cmd)
end

-- List of supported package managers.
local managers = {
	Manager.new("APT", "apt-get", {
		sync    = "{bin} update --quiet",
		install = "{bin} install --quiet --yes {package}",
	}),
	Manager.new("DNF", "dnf", {
		sync    = "{bin} --quiet makecache",
		install = "{bin} --quiet -y install {package}",
	}),
	Manager.new("YUM", "yum", {
		sync    = "{bin} --quiet makecache fast",
		install = "{bin} --quiet -y install {package}",
	}),
	Manager.new("Pacman", "pacman", {
		sync    = "{bin} -Sy --noconfirm",
		install = "{bin} -S --asdpes --noconfirm {package}",
	}),
}

-- Tries to guess a package manager available on current OS.
--:: () -> Manager?, err::string?
local function find_manager()
	for _, manager in ipairs(managers) do
		if manager:test() then return manager end
	end
	return nil, "unsupported package manager / linux distro"
end

return {
	find_manager = find_manager,
	testing = {
		format_cmd = format_cmd },
}
