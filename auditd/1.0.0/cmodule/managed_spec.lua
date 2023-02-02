local managed = require "managed"
local exec = require "exec"

local function rm(path)
	local cmd = string.format("rm -rf %q", path)
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

describe("managed File #write", function()
	setup(function()
		tmp = assert(exec("mktemp -d"))
		f_name = tmp .. "/sub/file"
	end)
	teardown(function() rm(tmp) end)

	describe("ensure()", function()
		it("should create a file unless it exists", function()
			local f = managed.file(f_name, "ug=rw,o=r")
			f:set("CREATE")

			local status = assert(f:ensure())
			assert.equals(managed.MODIFIED, status)
			assert.equals("CREATE", read_file(f_name))
			assert.equals("-rw-rw-r--", read_mode(f_name))
		end)

		it("should return `true` while file's content == required content", function()
			local f = managed.file(f_name, "INVALID")
			f:set("CREATE")

			local status = assert(f:ensure())
			assert.is_true(status)
		end)

		it("should overwrite if file's content != required content", function()
			local f = managed.file(f_name, "0400")
			f:set("UPDATE")

			local status = assert(f:ensure())
			assert.equals(managed.MODIFIED, status)
			assert.equals("UPDATE", read_file(f_name))
			assert.equals("-r--------", read_mode(f_name))
		end)
	end)
end)

describe("ensure_all() #write", function()
	setup(function()
		tmp = assert(exec("mktemp -d"))
		file_a = managed.file(tmp.."/a", "a=rw")
		file_b = managed.file(tmp.."/b", "a=rw")
	end)
	teardown(function() rm(tmp) end)

	it("should call ensure() for every item", function()
		file_a:set("CREATE")
		file_b:set("CREATE")

		local status = managed.ensure_all{file_a, file_b}
		assert.equals(managed.MODIFIED, status)
		assert.equals("CREATE", read_file(file_a:path()))
		assert.equals("CREATE", read_file(file_b:path()))
	end)

	it("should return MODIFIED if any of item is modified", function()
		file_a:set("UPDATE")
		assert.equals(managed.MODIFIED, managed.ensure_all{file_a, file_b})

		file_b:set("UPDATE")
		assert.equals(managed.MODIFIED, managed.ensure_all{file_a, file_b})
	end)

	it("otherwise returns `true`", function()
		 assert.is_true(managed.ensure_all{file_a, file_b})
	end)
end)
