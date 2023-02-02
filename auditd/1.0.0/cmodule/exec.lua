local function show_output(s)
	local MAX_LENGTH = 1024
	s = string.gsub(s, "\n", "\\n")
	s = string.sub(s, 1, MAX_OUTPUT_LENGTH)
	return s
end

local function trim_end(s)
	return string.gsub(s, "%s+$", "")
end

-- Executes the given command in a shell.
-- NOTE: stderr is redirecting to stdout.
--:: string -> output::string?, err::string?
local function exec(cmd)
	local f = io.popen("exec <&- 2>&1;" .. cmd)
	if not f then
		return nil, string.format("exec(%s): io.popen failed", cmd, err)
	end
	local output = f:read("a") or ""
	local ok, status, code = f:close()
	if not ok then
		return nil, string.format(
			"exec(%s): %s=%d: %s", cmd, status, code, show_output(output))
	end
	return trim_end(output)
end

return exec
