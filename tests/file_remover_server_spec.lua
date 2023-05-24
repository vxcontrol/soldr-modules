require 'busted.runner' ()

describe('file_remover server', function()
    setup(function()

        _G.vxagent_src = '2b93f312ba011517338774baf12c0deaae5671ea'
        _G.vxagent_dst = '2b93f312ba0115171ffe65673a8749ab35b600df'
        _G.browser_src = '8e4cf548ae94cfa4252dfb77f895a83190ddb021'
        _G.browser_dst = '140af502ab1909d4a8057e0e835b04a92b3f9e89'

        _G.__mock = {
            vars = {},
            timeout = 2,
            cwd = "tmpcwd",
            module = "file_remover",
            version = "1.0.0",
            side = "server",
            agent_conn = { type = "VXAgent", src = _G.vxagent_src, dst = _G.vxagent_dst, }
        }
        require("mock")

        table.insert(__mock.agents, { id = __mock.agent_id, type = "Browser", gid = __mock.group_id,
            src = _G.browser_src, dst = _G.browser_dst,
        })

        __mock:module_start()
    end)

    teardown(function()
        __mock:module_stop()
    end)

    before_each(function()
        __mock:clear_expectations()
    end)

    describe('should work as a proxy', function()
        it('should proxy action with correct src', function()
            local action_data = string.format('{ "data": { "object.fullpath" : "/some/path" }, "__cid": "123" }')
            assert(__mock:send_action(_G.browser_dst, "", action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("action",
                function(o)
                    if o.data and o.name == "fr_remove_object_file" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.vxagent_src, o.dst)
                        assert.not_nil(o.data.data)
                        assert.equal("123", o.data.__cid)
                        assert.equal("/some/path", o.data.data["object.fullpath"])
                        assert.equal(_G.browser_dst, o.data.__retaddr)
                        return true
                    end
                    return false
                end))

            assert.is_true(__mock:expect("msg",
                function(o)
                    if o.data and o.data.name == "fr_remove_object_file" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
                        assert.not_nil(o.data)
                        assert.equal("Module.Common.ActionProxied", o.data.__msg_type)
                        assert.equal("123", o.data.__cid)
                        return true
                    end
                    return false
                end))
        end)

        it('should not proxy action with wrong src', function()
            local action_data = string.format('{ "data" : { "object.fullpath" : "/some/path" }, "__cid": "123"  }')
            assert(__mock:send_action("some_random_dst", "", action_data, "fr_remove_object_file"),
                "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.name == "fr_remove_object_file" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal("some_random_dst", o.dst)
                        assert.not_nil(o.data)
                        assert.equal("123", o.data.__cid)
                        assert.equal("Module.Common.AgentConnectionError", o.data.error)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.not_nil(o.data.request_data)
                        assert.not_nil(o.data.request_data.data)
                        assert.equal("/some/path", o.data.request_data.data["object.fullpath"])
                        assert.equal("error", o.data.status)
                        return true
                    end
                    return false
                end))
        end)

        it('should proxy data', function()
            local action_data = string.format([[{
                "__cid": "cid",
                "__aid": "aid",
                "__msg_type": "Module.Common.ActionResponse",
                "name": "some_action",
                "status": "success",
                "request_data": "request",
                "data": "somedata",
                "__retaddr": "]] .. _G.browser_dst .. '" }')
            assert(__mock:send_data(_G.vxagent_dst, "", action_data), "failed to send data")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.name == "some_action" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
                        assert.not_nil(o.data)
                        assert.equal("aid", o.data.__aid)
                        assert.equal("Module.Common.ActionResponse", o.data.__msg_type)
                        assert.equal("somedata", o.data.data)
                        assert.equal("request", o.data.request_data)
                        assert.equal("success", o.data.status)
                        return true
                    end
                    return false
                end))
        end)

        it('should not proxy action with bad name', function()
            local action_data = string.format('{ "data" : "somedata" }')
            assert(__mock:send_action(_G.browser_dst, "", action_data, "some_action"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.name == "some_action" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
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

        it('should not proxy action with unexpected properties', function()
            local action_data = string.format('{ "data" : "somedata" }')
            assert(__mock:send_action(_G.browser_dst, "", action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.error == "Module.Common.ActionDataMissingValues" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
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

        it('should not proxy action with unexpected property values', function()
            local action_data = string.format('{ "data" : { "object.fullpath" : 123 } }')
            assert(__mock:send_action(_G.browser_dst, "", action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("data",
                function(o)
                    if o.data and o.data.error == "Module.Common.ValidationError" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
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

        it('should proxy action without cid', function()
            local action_data = string.format('{ "data": { "object.fullpath" : "/some/path" } }')
            assert(__mock:send_action(_G.browser_dst, "", action_data, "fr_remove_object_file"), "failed to send action")
            assert.is_true(__mock:expect("action",
                function(o)
                    if o.data and o.name == "fr_remove_object_file" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.vxagent_src, o.dst)
                        assert.not_nil(o.data.data)
                        assert.not_nil(o.data.__cid)
                        assert.equal("/some/path", o.data.data["object.fullpath"])
                        assert.equal(_G.browser_dst, o.data.__retaddr)
                        return true
                    end
                    return false
                end))

            assert.is_true(__mock:expect("msg",
                function(o)
                    if o.data and o.data.name == "fr_remove_object_file" then
                        assert.equal(__mock.module_token, o.src)
                        assert.equal(_G.browser_dst, o.dst)
                        assert.not_nil(o.data)
                        assert.equal("Module.Common.ActionProxied", o.data.__msg_type)
                        assert.not_nil(o.data.__cid)
                        return true
                    end
                    return false
                end))
        end)


    end)
end)
