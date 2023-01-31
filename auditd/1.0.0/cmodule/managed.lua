local exec = require "exec"

local File = {}; File.__index = File

local MODIFIED = {}

-- Introduces a managed file.
-- NOTE: `mode` is a string of format of `chmod` command, see: man chmod(1).
--:: string, string -> File
function File.new(path, mode)
	return setmetatable({
		_path = path,
		_mode = mode,
		_data = "",
	}, File)
end

-- Sets target content of the managed file.
--:: string -> ()
function File:set(data)
	self._data = data
end

-- Adjust the managed file state on disk.
-- Does nothing if the file content equals to the target data.
--:: () -> true|MODIFIED, err::string?
function File:adjust()
	if self:compare() == MODIFIED then
		local ok, err = self:write()
		return ok and MODIFIED,
			string.format("file %q: %s", self._path, err)
	end
	return true
end

-- Overwrite the managed file with the target data.
--:: () -> ok::boolean, err::string?
function File:write()
	local ok, err = exec(
		string.format("mkdir -p $(dirname %q)", self._path))
	if not ok then return false, err end

	local f = io.open(self._path, "wb")
	if not f then
		return false, string.format("failed to open") end

	local w, err = f:write(self._data)
	f:close()
	if not w then
		return false, err end

	return exec(
		string.format("chmod %q %q", self._mode, self._path))
end

-- Compares content of the managed file with the target value.
--:: () -> true|MODIFIED
function File:compare()
	local data
	local f = io.open(self._path, "rb")
	if f then
		data = f:read("a")
		f:close()
	end
	return self._data == data or MODIFIED
end

return {
	File     = File,
	MODIFIED = MODIFIED,
}
