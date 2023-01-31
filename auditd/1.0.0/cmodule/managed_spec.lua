local managed = require "managed"
local exec = require "exec"

local function rm(path)
	local cmd = string.format("rm -r %q", path)
	assert(exec(cmd))
end

local function read_file(filename)
	local f = assert(io.open(filename, "rb"),
		string.format("failed to open: %s", filename))
	return assert(f:read("a")), f:close()
end

local function read_mode(filename)
	local cmd = string.format("ls -l %q | cut -f1 -d\\ ", filename)
	return assert(exec(cmd))
end

describe("Managed file #write", function()
	setup(function()
		tmp = assert(exec("mktemp -d"))
		f_name = tmp .. "/sub/file"
	end)
	teardown(function()
		rm(tmp)
	end)

	describe("ensure()", function()
		it("should create a file unless it exists", function()
			local f = managed.File.new(f_name, "ug=rw,o=r")
			f:set("CREATE")

			local result = assert(f:ensure())
			assert.equals(managed.MODIFIED, result)
			assert.equals("CREATE", read_file(f_name))
			assert.equals("-rw-rw-r--", read_mode(f_name))
		end)

		it("should return `true` while file's content == required content", function()
			local f = managed.File.new(f_name, "INVALID")
			f:set("CREATE")

			local result = assert(f:ensure())
			assert.is_true(result)
		end)

		it("should overwrite if file's content != required content", function()
			local f = managed.File.new(f_name, "0400")
			f:set("UPDATE")

			local result = assert(f:ensure())
			assert.equals(managed.MODIFIED, result)
			assert.equals("UPDATE", read_file(f_name))
			assert.equals("-r--------", read_mode(f_name))
		end)
	end)
end)
