---------------------------------------------------

---------------------------------------------------
-- helper functions
---------------------------------------------------

local function new_test_file()
    local test_file_path = __mock.tmppath(__mock.rand_uuid() .. ".txt")
    local f, err = io.open(test_file_path, 'w+b')
    assert(f, err)
    assert(f:write("some data"))
    return test_file_path
end

local function file_exists(file_path)
    local f = io.open(file_path, "r")
    return f ~= nil and io.close(f)
end

---------------------------------------------------

---------------------------------------------------

-- set mock configuration (test environment)
__mock = {
    vars = {},
    timeout = 4, -- in seconds
    cwd = "tmpcwd",
    module = "file_remover",
    version = "1.0.0",
    side = "agent", -- server
    log_level = "debug", -- error, warn, info, debug, trace
}
-- load mocked environment
require("mock")

-- TESTS SETUP

local src, dst = __mock.mock_token, __mock.module_token
-- wait until module initialization is finished
__mock:expect("event", function(o) return o.event.name == "fr_module_started" end)

-- TESTS

--[[ TABLE
local test_cases = {
    {
        create_file = true,
        action = "fr_remove_object_file", param = "object.fullpath",
        result_data = "fr_remove_object_file", result_event = "fr_object_file_removed_successful"
    }, {
        create_file = true,
        action = "fr_remove_object_proc_image", param = "object.process.fullpath",
        result_data = "fr_remove_object_proc_image", result_event = "fr_object_proc_image_removed_successful"
    }, {
        create_file = true,
        action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
        result_data = "fr_remove_subject_proc_image", result_event = "fr_subject_proc_image_removed_successful"
    },
    {
        create_file = false,
        action = "fr_remove_object_file", param = "object.fullpath",
        result_data = "fr_remove_object_file", result_event = "fr_object_file_removed_failed"
    }, {
        create_file = false,
        action = "fr_remove_object_proc_image", param = "object.process.fullpath",
        result_data = "fr_remove_object_proc_image", result_event = "fr_object_proc_image_removed_failed"
    }, {
        create_file = false,
        action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
        result_data = "fr_remove_subject_proc_image", result_event = "fr_subject_proc_image_removed_failed"
    },
}
for _, test_case in ipairs(test_cases) do
    __mock.test(test_case.action .. " with " .. test_case.param, function()
        -- create test file
        local file_path = __mock.tmppath(__mock.rand_uuid() .. ".txt")
        assert(not file_exists(file_path), "random file somehow exists in FS")

        if test_case.create_file then
            file_path = new_test_file()
            assert(file_exists(file_path), "file was not created on FS")
        end

        -- ask module to delete the file
        local action_data = string.format('{ "data" : { "%s" : "%s" }}', test_case.param, file_path)
        assert(__mock:send_action(src, dst, action_data, test_case.action), "failed to send action")
        -- wait for expected result to arrive (in any order)
        __mock:expect("event", function(o) return o.event and o.event.name == test_case.result_event end)
        __mock:expect("data", function(o) return o.data and o.data.name == test_case.result_data end)

        -- check that file doesn't exist
        assert(not file_exists(file_path), "test file was not removed by a module")
    end)
end
--]]

--[[ FIRST ISSUE
__mock.test("check that file that never existed can be asked for deletion by object.fullpath", function()
    -- create test file
    local never_existing_file = __mock.tmppath(__mock.rand_uuid() .. ".txt")
    assert(not file_exists(never_existing_file), "random file somehow exists in FS")

    -- ask module to delete the file
    local action_data = string.format('{ "data" : { "object.fullpath" : "%s" }}', never_existing_file)
    assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
    -- wait for expected result to arrive (in any order)
    __mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_failed" end)

    -- TODO: validate data object using schema from configuration
    __mock:expect("event", function(o)
        return o.event
            and o.event.name == "fr_remove_object_file"
            and o.event.status == "nil" -- TODO: here is first issue found by a test
            and o.event.agent_id == __mock.agent_id
    end)
end)
--]]

---[[ JUST TEST
__mock.test("check file deletion by object.fullpath", function()
    -- create test file
    local test_file_path = new_test_file()

    -- check that recently created file exists
    assert(file_exists(test_file_path), "test file is not found")

    -- ask module to delete the file
    local action_data = string.format('{ "data" : { "object.fullpath" : "%s" }}', test_file_path)
    assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
    -- wait for expected result to arrive (in any order)
    __mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_successful" end)
    __mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end)

    -- check that file was actually removed
    assert(not file_exists(test_file_path), "test file was not removed by a module")

    -- ask module to delete the file once again
    assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
    -- wait for expected result to arrive (in any order)
    __mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_failed" end)
    __mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end)
end)
--]]

-- TESTS TEARDOWN

-- stop module actually wait for module coroutine to finish execution
__mock:module_stop()
-- check last expected events
__mock:expect("event", function(o) return o.event and o.event.name == "fr_module_stopped" end)
