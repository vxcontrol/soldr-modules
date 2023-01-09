require 'busted.runner'()
local ffi = require('ffi')

---------------------------------------------------
-- mock helper functions
---------------------------------------------------

local function mock_expect_event(name)
    return __mock:expect("event", function(o)
        return o.event and o.event.name == name
    end)
end

local function mock_get_event_context(name)
    return __mock:pop_from_context("event", function(o)
        return o.event and o.event.name == name
    end)
end

---------------------------------------------------
-- osquery helper functions
---------------------------------------------------

local function osquery_uninstall()
    print("uninstallation osquery in test")
    io.popen('dpkg --force-all -P osquery 2> /dev/null', 'r')
end

local function osquery_stop()
    print("stopping osquery in test")
    io.popen('systemctl stop osqueryd', 'r')
end

describe('osquery_linux agent', function()
    setup(function()
        _G.__mock = {
            vars = {},
            timeout = 60, -- in seconds
            cwd = "tmpcwd",
            module = "osquery_linux",
            version = "1.0.0",
            side = "agent",
            log_level = os.getenv("LOG_LEVEL") or "info", -- error, warn, info, debug, trace
        }
        -- load mocked environment
        require("mock")

        -- hack, see: https://github.com/vxcontrol/soldr-modules/issues/42
        __mock.module_info.fields = { "reason", "version" }
        __mock.module_info.actions = {}
        __mock.module_info.events = {
            "osquery_linux_already_installed",
            "osquery_linux_already_started",
            "osquery_linux_config_updated_error",
            "osquery_linux_config_updated_success",
            "osquery_linux_installed_error",
            "osquery_linux_installed_success",
            "osquery_linux_started_error",
            "osquery_linux_started_success",
            "osquery_linux_unexpected_stopped",
            "osquery_linux_unexpected_uninstalled",
            "osquery_linux_uninstalled_error",
            "osquery_linux_uninstalled_success"
        }

        osquery_uninstall()
    end)

    before_each(function()
        __mock:clear_expectations()
    end)

    teardown(function()
        -- stop module actually wait for module coroutine to finish execution
        osquery_uninstall()
        __mock:module_stop()
    end)

    context('osquery module life circle', function()
        if ffi.os ~= 'Linux' then
            describe('installing osquery', function()
                it('should not install osquery', function()
                    --__mock:module_start()

                    --for i, data in ipairs(__mock.stage.ctx["event"]) do
                    --    print("i", i)
                    --    print("data", data)
                    --end

                    assert.equal(table.getn(__mock.stage.ctx["event"]), 1) -- only one event
                    assert.is_true(mock_expect_event("osquery_linux_installed_error"))
                end)
            end)
        end

        if ffi.os == 'Linux' then
            describe('installing osquery', function()
                it('should install and configure osquery', function()
                    -- exec cmd + assert
                    assert.is_true(mock_expect_event("osquery_linux_installed_success"))
                    assert.is_true(mock_expect_event("osquery_linux_config_updated_success"))
                end)
            end)

            describe('when osquery was unexpected stopped', function()
                it('should start osquery', function()
                    assert.is_nil(mock_get_event_context("osquery_linux_unexpected_stopped"))
                    assert.is_nil(mock_get_event_context("osquery_linux_started_success"))
                    osquery_stop()
                    assert.is_true(mock_expect_event("osquery_linux_unexpected_stopped"))
                    assert.is_true(mock_expect_event("osquery_linux_started_success"))
                end)
            end)

            describe('when osquery was unexpected removed', function()
                it('should reinstall osquery', function()
                    assert.is_nil(mock_get_event_context("osquery_linux_unexpected_uninstalled"))
                    assert.is_nil(mock_get_event_context("osquery_linux_installed_success"))
                    osquery_uninstall()
                    assert.is_true(mock_expect_event("osquery_linux_unexpected_uninstalled"))
                    assert.is_true(mock_expect_event("osquery_linux_installed_success"))
                end)
            end)

            describe('when module get command update_config in callback', function()
                it('should start osquery', function()
                    assert.is_nil(mock_get_event_context("osquery_linux_config_updated_success"))
                    --assert.is_nil(mock_get_event_context("osquery_linux_installed_success"))
                    --local src, dst = __mock.mock_token, __mock.module_token
                    __mock:send_control("update_config")
                    --mock_command_update_config()
                    assert.is_true(mock_expect_event("osquery_linux_config_updated_success"))
                end)
            end)
        end
    end)
end)
