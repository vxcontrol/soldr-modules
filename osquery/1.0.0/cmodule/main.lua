require("engine")

local osquery = require("osquery")
local helpers = require("helpers")

__log.debugf("path to temp dir '%s'", __tmpdir)

-- ########## SUPPORT OSQUERY FUNCTIONS ##########

-- return bool
local function need_to_update_config()
    return helpers.get_option_config('replace_current_osquery_config') and
            helpers.get_option_config("osquery_config") ~= osquery:get_config()
end

-- return bool
local function need_to_update_flagfile()
    return helpers.get_option_config('replace_current_osquery_flagfile') and
            helpers.get_option_config("osquery_flagfile") ~= osquery:get_flagfile()
end

-- ########## PHASES ##########

-- return 'install'/'configure'/'controll'
local function preparing_phase()
    if osquery:is_installed() == false or osquery:is_version_correct() == false then return "install" end

    -- mad case
    local state = osquery:state()
    if state == 'unknown' then return "install" end

    if state ~= "running" and osquery:start() == false then
        helpers.push_event("osquery_installed_error", {
            reason = "osquery is already installed but can not start (name " .. osquery:get_service_name() .. "; cur version " .. osquery:get_version() .. ")",
            version = osquery:get_msi_version(),
        })

        return "control"
    end

    helpers.push_event("osquery_already_installed", {
        reason = "name " .. osquery:get_service_name() .. "; cur version " .. osquery:get_version() .. "; new version " .. osquery:get_msi_version(),
        version = osquery:get_version(),
    })

    if need_to_update_config() then return 'configure' end
    if need_to_update_flagfile() then return 'configure_flags' end

    return "control"
end

-- installed osquery, check it and push all events
-- return 'configure'/'control'
local function install_phase()
    __log.debug("call install_phase")
    local success, reason = osquery:install()

    if success then
        local state = osquery:state()
        if state ~= "running" and osquery:start() == false then
            __log.info("osquery was not installed")

            helpers.push_event("osquery_installed_error", {
                reason = "osquery was installed but can not start (name " .. osquery:get_service_name() .. "; cur version " .. osquery:get_version() .. ")",
                version = osquery:get_version(),
            })

            return "control"
        end

        __log.info("osquery was installed success")
        helpers.push_event("osquery_installed_success", {
            version = osquery:get_version(),
            reason = "",
        })

        if need_to_update_config() then return 'configure' end
        if need_to_update_flagfile() then return 'configure_flags' end

        return 'control'
    end

    __log.info("osquery was not installed")
    helpers.push_event("osquery_installed_error", {
        version = osquery:get_msi_version(),
        reason = reason,
    })

    return 'control'
end

-- update osquery flagfile
-- return 'control'
local function configure_flags_phase()
    __log.debug("call configure_flags_phase")

    local version = osquery:get_version()

    local ok, reason = osquery:update_flag_file()

    if not ok then
        local err = "failed to update flag file to module directory: " .. reason
        __log.error(err)

        helpers.push_event("osquery_flagfile_updated_error", {
            reason = err,
            version = version,
        })

        return "control"
    end

    local restart, reason = osquery:restart()
    if not restart then
        local err = 'can not restart osquery after update flagfile (' .. reason .. ')'
        __log.error(err)

        helpers.push_event("osquery_flagfile_updated_error", {
            reason = err,
            version = version,
        })

        return "control"
    end

    __log.info("osquery flagfile updated success")
    helpers.push_event("osquery_flagfile_updated_success", {
        version = version,
    })

    return "control"
end

-- update osquery config
-- return 'configure_flags'
local function configure_phase()
    __log.debug("call configure_phase")

    local version = osquery:get_version()

    local ok, reason = osquery:update_config_file()
    if not ok then
        local err = "failed to update config file to module directory: " .. reason
        __log.error(err)

        helpers.push_event("osquery_config_updated_error", {
            reason = err,
            version = version,
        })

        return "configure_flags"
    end

    local restart, reason = osquery:restart()
    if not restart then
        local err = 'can not restart osquery after update config (' .. reason .. ')'
        __log.error(err)

        helpers.push_event("osquery_config_updated_error", {
            reason = err,
            version = version,
        })

        return "configure_flags"
    end

    __log.info("osquery config updated success")
    helpers.push_event("osquery_config_updated_success", {
        version = version,
    })

    return "configure_flags"
end


-- return 'install' or nothing
local function control_phase()
    local osquery_dir_path = osquery:get_dir_path()
    local last_state = osquery:state()
    local version = osquery:get_msi_version()
    if last_state == "running" then
        version = osquery:get_version()
    end

    local change_state

    while not __api.is_close() do
        local current_state = osquery:state()
        if last_state == current_state then goto continue end

        change_state = "from: " .. last_state .. ", to: " .. current_state

        if current_state == "unknown" then
            __log.warnf("osquery was unexpected uninstalled (state: %s)", change_state)

            helpers.push_event("osquery_unexpected_uninstalled", {
                version = version,
                reason = change_state,
            })

            if osquery_dir_path == "" then return "install" end

            if not helpers.remove_dir(osquery_dir_path) then __log.errorf("%s was not removed, change state: %s", change_state) end

            return "install"
        end

        if current_state == "stopped" then
            __log.warnf("osquery was unexpected stopped (state: %s)", change_state)

            __log.info("osquery is stopped and should be running")
            helpers.push_event("osquery_unexpected_stopped", {
                reason = change_state,
                version = version,
            })

            if not osquery:start() then
                local err = "failed to start osquery, change state: " .. change_state
                __log.error(err)

                helpers.push_event("osquery_started_error", {
                    reason = err,
                    version = version,
                })

                last_state = "stopped"
                goto continue
            end

            version = osquery:get_version()
            __log.infof("osquery started success, change state: %s", change_state)

            helpers.push_event("osquery_started_success", {
                reason = change_state,
                version = version,
            })

            last_state = "running"
            goto continue
        end

        if current_state == "running" then
            version = osquery:get_version()
            helpers.push_event("osquery_already_started", {
                reason = change_state,
                version = version,
            })

            last_state = "running"
        end

        ::continue::
        __api.await(10000)
    end
end

-- ########## SYSTEM FUNCTIONS AND CALLBACKS ##########

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({

    -- data = function(src, data)
    -- file = function(src, path, name)
    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)
    -- action = function(src, data, name)

    control = function(cmtype, data)
        __log.infof("receive control msg '%s' with payload: %s", cmtype, data)

        if cmtype == 'update_config' then
            helpers.reread_module_info()
            configure_phase()
            configure_flags_phase()
        end

        if cmtype == 'quit' then
            local version = osquery:get_version()
            local success, reason = osquery:uninstall()

            if success then
                __log.info("osquery was uninstalled success")
                helpers.push_event("osquery_uninstalled_success", {
                    version = version,
                })

                return true
            end

            __log.errorf("osquery was not uninstalled, reason: %s", reason)
            helpers.push_event("osquery_uninstalled_error", {
                version = version,
                reason = reason,
            })
        end
        return true
    end,
})


__log.infof("module '%s' was started", __config.ctx.name)

local next_phase = preparing_phase()

while next_phase do
    __log.debugf("the next phase '%s'", next_phase)
    if next_phase == "install" then
        next_phase = install_phase()
    elseif next_phase == "configure" then
        next_phase = configure_phase()
    elseif next_phase == "configure_flags" then
        next_phase = configure_flags_phase()
    elseif next_phase == "control" then
        next_phase = control_phase()
    else
        __log.errorf("unexpected next handler: %s", next_phase)
        break
    end
end

__log.infof("module '%s' was stopped", __config.ctx.name)

return 'success'
