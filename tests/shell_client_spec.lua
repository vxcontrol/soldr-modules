require 'busted.runner' ()
local luapath = require("path")

local cjson = require('cjson')

describe('shell agent', function()
    setup(function()
        _G.__mock = {
            vars = {},
            timeout = 2,
            cwd = "tmpcwd",
            module = "shell",
            version = "1.0.0",
            side = "agent",
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

    describe('shell', function ()
        setup(function()
            src, dst = __mock.mock_token, __mock.module_token
        end)

        it('shell started, provides data and stops', function()
            local empty_data = cjson.encode({ data = {}, retaddr = "mock_browser_src" })

            assert(__mock:send_action(src, dst, empty_data, "shell_start"),
                "failed to send shell_start action")

            assert.is_true(__mock:expect("data", function(o) return o.data['out'] ~= '' end))

            assert(__mock:send_action(src, dst, empty_data, "shell_stop"),
                "failed to send shell_stop action")
        end)

        it('shell returns provided input', function()
            local empty_data = cjson.encode({ data = {}, retaddr = "mock_browser_src" })

            assert(__mock:send_action(src, dst, empty_data, "shell_start"),
                "failed to send shell_start action")

            local data_payload = {
                retaddr = "mock_browser_src",
                i = "test",
            }
            assert(__mock:send_data(src, dst, cjson.encode(data_payload)), "failed to send input to shell")

            assert.is_true(__mock:expect("data", function(o) return o.data['out'] == "test" end))

            assert(__mock:send_action(src, dst, empty_data, "shell_stop"),
                "failed to send shell_stop action")
        end)
    end)
end)
