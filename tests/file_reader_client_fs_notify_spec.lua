require("busted.runner")()
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
    it("returns false for glob not in filenames", function()
        assert.is_false(fs_notify.is_glob_pattern("/*/*/file.txt"))
    end)
end)

local ffi = require("ffi")
if ffi.os == "Windows" then
    describe("filename_matching_windows", function()
        it("returns true for empty pattern", function()
            assert.is_true(fs_notify.filename_matching_pattern("test.txt", ""))
        end)
        it("returns false for not matching pattern", function()
            assert.is_false(fs_notify.filename_matching_pattern("test.txt", "not*.jpj"))
        end)
        it("returns true for matching pattern", function()
            assert.is_true(fs_notify.filename_matching_pattern("test.txt", "te*.txt"))
        end)
    end)
elseif ffi.os == "Linux" then
    pending("filename_matching_linux")
elseif ffi.os == "OSX" then
    pending("filename_matching_osx")
end

if ffi.os == "Windows" then
    describe("find_all_files_windows", function()
        it("returns an empty list when there are no matching files", function()
            local files = fs_notify.find_all_files("tests/data/file_reader_client/notmatching*.txt")

            assert.are.same({}, files)
        end)
        it("returns all files matching pattern", function()
            local files = fs_notify.find_all_files("tests/data/file_reader_client/test*.txt")

            assert.are.same({ "tests/data/file_reader_client/test1.txt", "tests/data/file_reader_client/test2.txt" }, files)
        end)
    end)
elseif ffi.os == "Linux" then
    pending("find_all_files_linux")
elseif ffi.os == "OSX" then
    pending("find_all_files_osx")
end
