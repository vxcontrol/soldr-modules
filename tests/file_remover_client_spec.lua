require 'busted.runner' ()
local luapath = require("path")

local cjson = require('cjson')

---------------------------------------------------

---------------------------------------------------
-- helper functions
---------------------------------------------------

local function new_test_file(file_name)
    file_name = file_name or (__mock.rand_uuid() .. ".txt")
    local test_file_path = __mock.tmppath(file_name)
    local f, err = io.open(test_file_path, 'w+b')
    assert(f, err)
    assert(f:write("some data"))
    assert(f:close())
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

local function filepath_to_json(param, path)
    local action_data = {}
    action_data[param] = path
    return cjson.encode({ data = action_data })
end

---------------------------------------------------

---------------------------------------------------

describe('file_remover agent', function()
    setup(function()
        _G.__mock = {
            vars = {},
            timeout = 2,
            cwd = "tmpcwd",
            module = "file_remover",
            version = "1.0.0",
            side = "agent",
            log_level = os.getenv("LOG_LEVEL"),
        }
        -- load mocked environment
        require("mock")
        -- wait until module initialization is finished

        __mock:module_start()
    end)

    teardown(function()
        -- stop module actually wait for module coroutine to finish execution
        __mock:module_stop()
    end)

    before_each(function()
        __mock:clear_expectations()
    end)

    describe('single file removal', function()
        local src, dst = __mock.mock_token, __mock.module_token
        local test_file_path = new_test_file()

        local action_data = filepath_to_json('object.fullpath', test_file_path)

        it('should successfully create file on file system', function()
            assert.is_true(file_exists(test_file_path), "test file is not found")
        end)

        it('should delete file using module functionlity', function()
            -- ask module to delete the file

            assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"),
                "failed to send file remove action")
            -- wait for expected result to arrive (in any order)
            assert.is_true(__mock:expect("event",
                function(o) return o.event and o.event.name == "fr_object_file_removed_successful" end))
            assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end))

            -- check that file was actually removed
            assert.is_false(file_exists(test_file_path), "test file was not removed by a module")
        end)

        it('should fail if file deletion asked more then once', function()
            test_co(function()
                -- ask module to delete the file once again
                assert.is_true(__mock:send_action(src, dst, action_data, "fr_remove_object_file"),
                    "failed to send file remove action")
                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event", function(o)
                        return o.event and o.event.name == "fr_object_file_removed_failed"
                end))
                assert.is_true(__mock:expect("data",
                    function(o) return o.data and o.data.name == "fr_remove_object_file" end))
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
            local action_data = filepath_to_json('object.fullpath', never_existed_file)
            test_co(function()
                assert.is_true(__mock:send_action(src, dst, action_data, "fr_remove_object_file"),
                    "failed to send file remove action")
                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event",
                    function(o) return o.event and o.event.name == "fr_object_file_removed_failed" end))

                -- TODO: validate data object using schema from configuration
                assert.is_true(__mock:expect("data", function(o)
                    return o.data
                        and o.data.name == "fr_remove_object_file"
                        and o.data.status == "error"
                        and o.data.__aid == __mock.agent_id
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
                type = "object", subtype = "file", result_data = "fr_remove_object_file",
                result_event = "fr_object_file_removed_successful"
            },
            {
                create_file = true,
                action = "fr_remove_object_proc_image", param = "object.process.fullpath",
                type = "object", subtype = "proc_image", result_data = "fr_remove_object_proc_image",
                result_event = "fr_object_proc_image_removed_successful"
            },
            {
                create_file = true,
                action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
                type = "subject", subtype = "proc_image", result_data = "fr_remove_subject_proc_image",
                result_event = "fr_subject_proc_image_removed_successful"
            },
            {
                create_file = false,
                action = "fr_remove_object_file", param = "object.fullpath",
                type = "object", subtype = "file", result_data = "fr_remove_object_file",
                result_event = "fr_object_file_removed_failed"
            },
            {
                create_file = false,
                action = "fr_remove_object_proc_image", param = "object.process.fullpath",
                type = "object", subtype = "proc_image", result_data = "fr_remove_object_proc_image",
                result_event = "fr_object_proc_image_removed_failed"
            },
            {
                create_file = false,
                action = "fr_remove_subject_proc_image", param = "subject.process.fullpath",
                type = "subject", subtype = "proc_image", result_data = "fr_remove_subject_proc_image",
                result_event = "fr_subject_proc_image_removed_failed"
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
                local expected_reason = test_case.create_file and "removed successful" or file_path .. ": No such file or directory"
                local expected_uniq = "fr_" ..
                    test_case.type ..
                    "_" .. test_case.subtype ..
                    "_removed_" .. (test_case.create_file and "successful" or "failed") .. "_"

                -- ask module to delete the file
                local action_data = filepath_to_json(test_case.param, file_path)
                test_co(function()
                    assert.is_true(__mock:send_action(src, dst, action_data, test_case.action), "failed to send action")
                end)

                -- wait for expected result to arrive (in any order)
                assert.is_true(__mock:expect("event",
                    function(o)
                        if o.event and o.event.name == test_case.result_event then
                            assert.equal(__mock.agent_id, o.aid)
                            expected_uniq = expected_uniq .. o.event.data.start_time:gsub("%s", "_") .. "_"
                            assert.is_true(o.event.uniq:find(expected_uniq, 1, true) == 1)
                            assert.equal(1, #o.event.actions)
                            assert.equal("file_remover." .. test_case.action, o.event.actions[1])
                            assert.not_nil(o.event.data)
                            assert.equal("table", type(o.event.data))
                            assert.equal("file_object", o.event.data[test_case.type],
                                "field .data." .. test_case.type .. " not set")
                            assert.equal(__mock.tmpdir, o.event.data[test_case.type .. ".path"])
                            assert.equal(luapath.file(file_path), o.event.data[test_case.type .. ".name"])
                            assert.equal("txt", o.event.data[test_case.type .. ".ext"])
                            if test_case.create_file then
                                assert.is_true(o.event.data.result)
                            else
                                assert.is_false(o.event.data.result)
                            end
                            assert.not_nil(o.event.data.__cid)
                            assert.not_nil(o.event.data.uuid)
                            assert.equal(file_path, o.event.data[test_case.type .. ".fullpath"])
                            assert.equal(expected_reason, o.event.data.reason)
                            assert.not_nil(o.event.data.start_time)
                            assert.not_nil(o.event.time)
                            return true
                        end
                        return false
                    end))
                assert.is_true(__mock:expect("data",
                    function(o)
                        if o.data and o.data.name == test_case.result_data then
                            assert.equal(__mock.mock_token, o.dst)
                            assert.equal(__mock.module_token, o.src)
                            assert.equal(test_case.create_file and "success" or "error", o.data.status)
                            assert.equal(__mock.agent_id, o.data.__aid)
                            assert.equal(test_case.action, o.data.name)
                            return true
                        end
                        return false
                    end))

                -- check that file doesn't exist
                assert.is_false(file_exists(file_path), "test file was not removed by a module")
            end
        end)

        it('should not allow action with bad name', function()
            local action_data = string.format('{ "data" : "somedata" }')
            assert(__mock:send_action(src, dst, action_data, "some_action"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.name == "some_action" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(__mock.mock_token, o.dst)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.equal("Module.Common.ActionNotDefinedInSchema", o.data.error)
                        assert.not_nil(o.data.request_data)
                        assert.equal("somedata", o.data.request_data.data)
                        assert.equal("error", o.data.status)
                        return true
                    end
                    return false
                end))
        end)

        it('should not allow action with unexpected properties', function()
            local action_data = string.format('{ "data" : "somedata" }')
            assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.error == "Module.Common.ActionDataMissingValues" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(__mock.mock_token, o.dst)
                        assert.equal("fr_remove_object_file", o.data.name)
                        assert.equal("Module.Common.ActionDataMissingValues", o.data.error)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.not_nil(o.data.request_data)
                        assert.equal("somedata", o.data.request_data.data)
                        assert.equal("error", o.data.status)
                        return true
                    end
                    return false
                end))
        end)

        it('should not allow action with unexpected property values', function()
            local action_data = string.format('{ "data" : { "object.fullpath" : 123 } }')
            assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.error == "Module.Common.ValidationError" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(__mock.mock_token, o.dst)
                        assert.equal("fr_remove_object_file", o.data.name)
                        assert.equal("Module.Common.ValidationError", o.data.error)
                        assert.equal("wrong type: expected string, got number", o.data.reason)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.not_nil(o.data.request_data)
                        assert.not_nil(o.data.request_data.data)
                        assert.equal(123, o.data.request_data.data["object.fullpath"])
                        assert.equal("error", o.data.status)
                        return true
                    end
                    return false
                end))
        end)

        it('should not allow action with unexpected property values (empty)', function()
            local action_data = string.format('{ "data" : { "object.fullpath" : "" } }')
            assert(__mock:send_action(src, dst, action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.error == "Module.Common.ActionDataFieldValueNotSet" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(__mock.mock_token, o.dst)
                        assert.equal("fr_remove_object_file", o.data.name)
                        assert.equal("Module.Common.ActionDataFieldValueNotSet", o.data.error)
                        assert.equal("field 'object.fullpath' value is not set", o.data.reason)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.not_nil(o.data.request_data)
                        assert.not_nil(o.data.request_data.data)
                        assert.equal("", o.data.request_data.data["object.fullpath"])
                        assert.equal("error", o.data.status)
                        return true
                    end
                    return false
                end))
        end)
    end)

    describe('file removal bug fixes', function()
        -- EDR-1666
        it('should remove files with UTF8 names', function()
            local test_file_path = new_test_file("имя файла на русском языке." ..
                __mock.rand_uuid())
            local action_data = filepath_to_json('object.fullpath', test_file_path)
            assert.is_true(file_exists(test_file_path), "test file is not found")
            -- ask module to delete the file

            assert(__mock:send_action(__mock.mock_token, __mock.module_token, action_data, "fr_remove_object_file"),
                "failed to send file remove action")
            -- wait for expected result to arrive (in any order)
            assert.is_true(__mock:expect("event",
                function(o) return o.event and o.event.name == "fr_object_file_removed_successful" end))
            assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == "fr_remove_object_file" end))

            -- check that file was actually removed
            assert.is_false(file_exists(test_file_path), "test file was not removed by a module")
        end)
    end)
end)
