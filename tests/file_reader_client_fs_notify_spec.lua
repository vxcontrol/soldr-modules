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

            assert.are.same(
                { "tests/data/file_reader_client/test1.txt", "tests/data/file_reader_client/test2.txt" },
                files
            )
        end)
    end)
elseif ffi.os == "Linux" then
    pending("find_all_files_linux")
elseif ffi.os == "OSX" then
    pending("find_all_files_osx")
end

if ffi.os == "Windows" then
    describe("DirectoryWatcher_windows", function()
        local new_file = "tests/data/file_reader_client/test_created.txt"
        local new_not_matching_file = "tests/data/file_reader_client/not_matching.txt"
        local new_file_pattern = "tests/data/file_reader_client/test*.txt"
        setup(function()
            os.remove(new_file)
            os.remove(new_not_matching_file)
        end)
        teardown(function()
            os.remove(new_file)
            os.remove(new_not_matching_file)
        end)

        it("addDirectory returns an error on a not-existent directory", function()
            local watcher = fs_notify.DirectoryWatcher()

            local status = watcher:addDirectory("no_such_directory\\test*.txt", function() end)

            assert.is_false(status)
        end)
        it("calls back when a new file is created matching the pattern", function()
            local watcher = fs_notify.DirectoryWatcher()
            callback = spy.new(function() end)

            local status = watcher:addDirectory(new_file_pattern, callback)
            io.open(new_file, "w"):close()
            watcher:wait(10)

            assert.is_true(status)
            assert.spy(callback).was.called_with({ new_file })
            watcher:removeDirectory(new_file_pattern)
        end)
        it("ignores new files that do not match the pattern", function()
            local watcher = fs_notify.DirectoryWatcher()
            callback = spy.new(function() end)

            local status = watcher:addDirectory(new_file_pattern, callback)
            io.open(new_not_matching_file, "w"):close()
            watcher:wait(10)

            assert.is_true(status)
            assert.spy(callback).was.called(0)
            watcher:removeDirectory(new_file_pattern)
        end)
        it("ignores file deletion events", function()
            local watcher = fs_notify.DirectoryWatcher()
            callback = spy.new(function() end)
            io.open(new_file, "w"):close()

            local status = watcher:addDirectory(new_file_pattern, callback)
            os.remove(new_file)
            watcher:wait(10)

            assert.is_true(status)
            assert.spy(callback).was.called(0)
            watcher:removeDirectory(new_file_pattern)
        end)
    end)
elseif ffi.os == "Linux" then
    pending("DirectoryWatcher_linux")
elseif ffi.os == "OSX" then
    pending("DirectoryWatcher_osx")
end
