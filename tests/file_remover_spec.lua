require 'busted.runner'()

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

local test_co = function(f)
    local scenario_co = coroutine.create(f)
    while coroutine.status(scenario_co) == "suspended" do
        local result, err = coroutine.resume(scenario_co)
        assert(result, err)
    end
end

---------------------------------------------------

---------------------------------------------------

describe('file_remover agent', function()
    setup(function()
        _G.__mock = {
            vars = {},
            timeout = 2, -- in seconds
            cwd = "tmpcwd",
            module = "file_remover",
            version = "1.0.0",
            side = "agent", -- server
            log_level = os.getenv("LOG_LEVEL") or "debug", -- error, warn, info, debug, trace
            sec = {siem="{}", waf="{}", nad="{}", sandbox="{}"},
        }
        -- load mocked environment
        require("mock")
        -- wait until module initialization is finished
        assert.is_true(__mock:expect("event", function(o) return o.event.name == "fr_module_started" end), "fr_module_started event not arrived")
    end)

    teardown(function()
        -- stop module actually wait for module coroutine to finish execution
        __mock:module_stop()
        -- check last expected events
        assert.is_true(__mock:expect("event", function(o)
            return o.event and o.event.name == "fr_module_stopped"
        end))
    end)

    describe('single file removal', function()
        local src, dst = __mock.mock_token, __mock.module_token
        local test_file_path = new_test_file()
        local action_data = string.format('{ "data" : { "object.fullpath" : "%s" }}', test_file_path)

        it('should successfully create file on file system', function()
            assert.is_true(file_exists(test_file_path), "test file is not found")
        end)

        it('should delete file using module functionlity', function()
            -- ask module to delete the file

            assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
            -- wait for expected result to arrive (in any order)
            assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_successful" end))
            assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end))

            -- check that file was actually removed
            assert.is_false(file_exists(test_file_path), "test file was not removed by a module")
        end)

        it('should fail if file deletion asked more then once', function()
            test_co(function()
                -- ask module to delete the file once again
                assert.is_true(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_failed" end))
                assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end))
            end)
        end)
    end)

    describe('file that does not exist', function()
        local src, dst = __mock.mock_token, __mock.module_token
        local never_existed_file = __mock.tmppath(__mock.rand_uuid() .. ".txt")

        it('should not be found on the FS', function()
            assert.is_false(file_exists(never_existed_file), "random file somehow exists in FS")
        end)

        it('should fail to delete by module', function()
            local action_data = string.format('{ "data" : { "object.fullpath" : "%s" }}', never_existed_file)
            test_co(function()
                assert.is_true(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send file remove action")
                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == "fr_object_file_removed_failed" end))

                -- TODO: validate data object using schema from configuration
                assert.is_true(__mock:expect("data", function(o)
                    return o.data
                        and o.data.name == "fr_remove_object_file"
                        and o.data.status == "nil" -- TODO: here is first issue found by a test
                        and o.data.agent_id == __mock.agent_id
                end))
            end)
        end)
    end)

    describe('file removal', function()
        local src, dst = __mock.mock_token, __mock.module_token
        local test_cases = {
            {
                create_file = true,
                action = "fr_remove_object_file", param = "object.fullpath",
                result_data = "fr_remove_object_file", result_event = "fr_object_file_removed_successful"
            },
            {
                create_file = true,
                action = "fr_remove_object_proc_image", param = "object.process.fullpath",
                result_data = "fr_remove_object_proc_image", result_event = "fr_object_proc_image_removed_successful"
            },
            {
                create_file = true,
                action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
                result_data = "fr_remove_subject_proc_image", result_event = "fr_subject_proc_image_removed_successful"
            },
            {
                create_file = false,
                action = "fr_remove_object_file", param = "object.fullpath",
                result_data = "fr_remove_object_file", result_event = "fr_object_file_removed_failed"
            },
            {
                create_file = false,
                action = "fr_remove_object_proc_image", param = "object.process.fullpath",
                result_data = "fr_remove_object_proc_image", result_event = "fr_object_proc_image_removed_failed"
            },
            {
                create_file = false,
                action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
                result_data = "fr_remove_subject_proc_image", result_event = "fr_subject_proc_image_removed_failed"
            },
        }

        it('should be possible to call public actions list', function()
            for _, test_case in ipairs(test_cases) do
                -- create test file
                local file_path = __mock.tmppath(__mock.rand_uuid() .. ".txt")
                assert.is_false(file_exists(file_path), "random file somehow exists in FS")
                if test_case.create_file then
                    file_path = new_test_file()
                    assert.is_true(file_exists(file_path), "file was not created on FS")
                end

                -- ask module to delete the file
                local action_data = string.format('{ "data" : { "%s" : "%s" }}', test_case.param, file_path)
                test_co(function()
                    assert.is_true(__mock:send_action(src, dst, action_data, test_case.action), "failed to send action")
                end)

                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == test_case.result_event end))
                assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == test_case.result_data end))

                -- check that file doesn't exist
                assert.is_false(file_exists(file_path), "test file was not removed by a module")
            end
        end)
    end)
end)
