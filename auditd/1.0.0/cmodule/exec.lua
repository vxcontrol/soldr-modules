local try = require "try"

local function show_output(s)
	local MAX_LENGTH = 1024
	s = string.gsub(s, "\n", "\\n")
	s = string.sub(s, 1, MAX_LENGTH)
	return s
end

local function trim_end(s)
	return string.gsub(s, "%s+$", "")
end

-- Executes the given command in a shell.
-- NOTE: stderr is redirecting to stdout.
--:: string -> output::string?, err::string?
local function exec(cmd)
	local result, err = try(function()
		local stdout = assert(
			io.popen("exec <&- 2>&1;"..cmd), "io.popen failed")
		local output = stdout:read("a") or ""
		local ok, status, code = stdout:close()
		assert(ok,
			string.format("%s=%d: %s", status, code, show_output(output)))
		return trim_end(output)
	end)
	return result, string.format("exec(%s): %s", cmd, err)
end

return exec
