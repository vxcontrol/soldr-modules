local exec = require "exec"
local try  = require "try"

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
	return try(function()
		assert(exec(
			string.format("mkdir -p $(dirname %q)", self._path)))

		local f = assert(io.open(self._path, "wb"), "failed to open")
		local w, err = f:write(self._data);
		f:close()
		assert(w, err)

		assert(exec(
			string.format("chmod %q %q", self._mode, self._path)))
		return true
	end)
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
	return try(function()
		local status = true
		for _, item in ipairs(list) do
			if assert(item:ensure()) == MODIFIED then
				status = MODIFIED end
		end
		return status
	end)
end

return {
	MODIFIED   = MODIFIED,
	file       = file,
	ensure_all = ensure_all,
}
