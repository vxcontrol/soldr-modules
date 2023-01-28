package.path = package.path .. ";cmodule/?.lua"
local pkg = require "pkg"
local exec = require "exec"

local function is_installed(name)
	return exec("type "..name)
end

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

describe("package manager #root", function()
	setup(function()
		pm = assert(pkg.find_manager())
		assert(pm:sync())
	end)

	test("install()", function()
		local package = "less"
		assert(not is_installed(package),
			string.format("expected %q to be not installed", package))
		assert(pm:install(package))
		assert(is_installed(package))
	end)
end)
