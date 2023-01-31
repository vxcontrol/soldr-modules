local exec = require "exec"

local function string_contains(str, sub)
	return string.find(str, sub, 1, true) ~= nil
end

describe("exec", function()
	it("runs a given command", function()
		assert(exec("true"))
	end)

	it("must fail if exit code != 0", function()
		local ok, err = exec("echo ERROR; false")
		assert(not ok)
		assert(string_contains(err, 'exit=1: ERROR'),
			string.format("unexpected error message: %s", err))
	end)

	test("a bad command", function()
		local ok, err = exec("unknown-command")
		assert(not ok)
		assert(string_contains(err, "not found"),
			string.format("unexpected error message: %s", err))
	end)
end)
