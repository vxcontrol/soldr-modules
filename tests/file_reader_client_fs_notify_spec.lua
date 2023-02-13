require("busted.runner")()

local ffi = require("ffi")
local path = require("path")
local fs = require("lfs")
local glue = require("glue")

package.path = package.path .. ";./file_reader/1.0.0/cmodule/?.lua"

local fs_notify = require("fs_notify")

describe("is_glob_pattern", function()
    it("returns false for empty strings", function()
        assert.is_false(fs_notify.is_glob_pattern(""))
    end)
    it("returns false for usual paths", function()
        assert.is_false(fs_notify.is_glob_pattern("/usr/bin/luajit"))
    end)
    it("returns true for glob patterns", function()
        assert.is_true(fs_notify.is_glob_pattern("/usr/bin/lua*"))
        assert.is_true(fs_notify.is_glob_pattern("/usr/bin/lua?"))
    end)
    it("returns false for glob not in filename", function()
        assert.is_false(fs_notify.is_glob_pattern("/*/*/file.txt"))
    end)
end)

describe("is_filename_match_pattern", function()
    if ffi.os ~= "Windows" then
        it("always returns false", function()
            assert.is_false(fs_notify.is_filename_match_pattern("test.txt", "*"))
        end)
        return
    end
    it("returns true for empty pattern", function()
        assert.is_true(fs_notify.is_filename_match_pattern("test.txt", ""))
    end)
    it("returns false for not matching pattern", function()
        assert.is_false(fs_notify.is_filename_match_pattern("test.txt", "not*.jpj"))
    end)
    it("returns true for matching pattern", function()
        assert.is_true(fs_notify.is_filename_match_pattern("test.txt", "te*.txt"))
    end)
end)

describe("find_all_files", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    local matching_files = {
        path.combine(tmp_dir, "test1.txt"),
        path.combine(tmp_dir, "test2.txt"),
    }
    local all_files = glue.merge(matching_files, { path.combine(tmp_dir, "other.txt") })
    local all_tests_glob = path.combine(tmp_dir, "test*.txt")

    setup(function()
        fs.mkdir(tmp_dir)
        for _, filename in ipairs(all_files) do
            io.open(filename, "w"):close()
        end
    end)
    teardown(function()
        for _, filename in ipairs(all_files) do
            os.remove(filename)
        end
        fs.rmdir(tmp_dir)
    end)

    if ffi.os ~= "Windows" then
        it("always returns empty set", function()
            assert.are.same({}, fs_notify.find_all_files(all_tests_glob))
        end)
        return
    end
    it("returns an empty list when there are no matching files", function()
        local not_matching_glob = path.combine(tmp_dir, "notmatching*.txt")
        assert.are.same({}, fs_notify.find_all_files(not_matching_glob))
    end)
    it("returns all files matching pattern", function()
        assert.are.same(matching_files, fs_notify.find_all_files(all_tests_glob))
    end)
end)
