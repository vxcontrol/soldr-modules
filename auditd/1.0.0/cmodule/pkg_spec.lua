local pkg = require "pkg"

describe("format_cmd", function()
	local format_cmd = pkg.testing.format_cmd

	it("replaces {name} placeholders", function()
		local cmd = format_cmd("one={one} two={two}", {
			one = "ONE",
			two = "TWO",
		})
		assert.equals("one=ONE two=TWO", cmd)
	end)

	it("replaces ALL {name} occurrences", function()
		assert.equals("a=VAR b=VAR",
			format_cmd("a={var} b={var}", {var="VAR"}))
	end)

	it("ignores {unknown} variables", function()
		assert.equals("{unknown}", format_cmd("{unknown}", {}))
	end)

	it("skips unused variables", function()
		assert.equals("", format_cmd("", {unused="UNUSED"}))
	end)
end)
