package.path = package.path .. ";cmodule/?.lua"
local exec = require "exec"

local function string_contains(str, sub)
	return string.find(str, sub, 1, true) ~= nil
end

describe("exec", function()
	it("runs a given command", function()
		local ok, err = exec("true")
		assert(ok, "unexpected error: "..tostring(err))
	end)

	it("must fail unless the exit code is 0", function()
		local ok, err = exec("echo ERROR; false")
		assert(not ok)
		assert(string_contains(err, 'exit=1: ERROR'),
			"unexpected error message: "..tostring(err))
	end)

	test("a bad command", function()
		local ok, err = exec("unknown-command")
		assert(not ok)
		assert(string_contains(err, "not found"),
			"unexpected error message: "..tostring(err))
	end)
end)
