local managed = require "managed"
local exec = require "exec"

local function temp_dir()
	local filename = assert(os.tmpname())
	assert(os.remove(filename))
	return filename .. ".dir"
end

local function rm(path)
	local cmd = string.format("rm -rf %q", path)
	assert(exec(cmd))
end

local function read_all(filename)
	local f = assert(io.open(filename, "rb"),
		string.format("failed to open: %s", filename))
	return assert(f:read("a")), f:close()
end

local function read_mode(filename)
	local cmd = string.format("ls -l %q | cut -f1 -d' '", filename)
	local ok, mode = assert(exec(cmd))
	return mode
end

describe("Managed file", function()
	setup(function()
		tmp = temp_dir()
	end)
	teardown(function()
		rm(tmp)
	end)

	describe("adjust()", function()
		it("should create a file unless it exists", function()
			local f = managed.File.new(tmp.."/file", "ug=rw,o=r")
			f:set("CREATE")
			local result = assert(f:adjust())
			assert.equals(result, managed.MODIFIED)
			assert.equals(read_all(tmp.."/file"), "CREATE")
			assert.equals(read_mode(tmp.."/file"), "-rw-rw-r--")
		end)

		it("should return `true` while file's content == target data", function()
			local f = managed.File.new(tmp.."/file", "TEST")
			f:set("CREATE")
			local result = assert(f:adjust())
			assert.equals(result, true)
		end)

		it("should overwrite if file's content != target data", function()
			local f = managed.File.new(tmp.."/file", "400")
			f:set("UPDATE")
			local result = assert(f:adjust())
			assert.equals(result, managed.MODIFIED)
			assert.equals(read_all(tmp.."/file"), "UPDATE")
			assert.equals(read_mode(tmp.."/file"), "-r--------")
		end)
	end)
end)
