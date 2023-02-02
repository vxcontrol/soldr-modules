local exec = require "exec"

local MODIFIED = {}

local File = {}; File.__index = File

-- Introduces a "managed" file.
--   1. Set the required access `mode` to the file.
--   2. Set the required content of the file with `set`.
--   3. Then use `ensure` to adjust the file on disk to required state.
-- NOTE: `mode` is a string in `chmod` format, see: chmod(1).
--:: string, string -> File
local function file(path, mode)
	return setmetatable({
		_path = path,
		_mode = mode,
		_data = "",
	}, File)
end

function File:path()
	return self._path
end

-- Sets target content of the file.
--:: string -> ()
function File:set(data)
	self._data = data
end

-- Adjust the file on disk to required state.
-- Does nothing if the file on disk matches the required state.
--:: () -> boolean|MODIFIED, err::string?
function File:ensure()
	if self:compare() == MODIFIED then
		local ok, err = self:write()
		return ok and MODIFIED,
			string.format("%s: %s", self._path, err)
	end
	return true
end

-- Entirely overwrites the file on disk with the required content.
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

	local ok, err = exec(
		string.format("chmod %q %q", self._mode, self._path))
	return ok and true, err
end

-- Compares the required content with the file's content on disk.
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

-- Calls `ensure` for every item of `list`.
-- Returns MODIFIED if any of list returns MODIFIED.
-- Immediately returns false if any of list failed.
--:: File... -> boolean|MODIFIED, err::string?
local function ensure_all(list)
	local status = true
	for _, item in ipairs(list) do
		local result, err = item:ensure()
		if not result then
			return false, err end
		if result == MODIFIED then
			status = MODIFIED end
	end
	return status
end

return {
	MODIFIED   = MODIFIED,
	file       = file,
	ensure_all = ensure_all,
}
