local pkg = require "pkg"
local exec = require "exec"

local function is_installed(name)
	return exec("type "..name)
end

describe("format_cmd()", function()
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

context("package manager #root", function()
	setup(function()
		pm = assert(pkg.find_manager())
	end)

	test("sync() #network", function()
		assert(pm:sync())
	end)

	test("install() #network", function()
		local package = "lsof"
		-- Uncomment to assert clean installation:
		-- assert(not is_installed(package),
		-- 	string.format("expected %q to be not installed", package))
		assert(pm:install("alternative", package))
		assert(is_installed(package))
	end)
end)
