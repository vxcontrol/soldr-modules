local MODULE = require("protocol/cmodule")
local os_specific_functions = MODULE.require("file_remove")

---------------------------------------------------
-- module configuration
---------------------------------------------------

local config = {
    remove_file_retry_count = tonumber(__args["remove_file_retry_count"][1]) or 5,
    remove_file_retry_interval = tonumber(__args["remove_file_retry_interval"][1]) or 100
}

---------------------------------------------------
-- module business logic
---------------------------------------------------

local function os_remove_file(file_path)
    local result, err
    for _ = 0, config.remove_file_retry_count do
        result, err = os_specific_functions.remove_file(file_path)
        if result then
            break
        else
            __api.await(config.remove_file_retry_interval)
        end
    end
    return result, err
end

---------------------------------------------------
-- action executor
---------------------------------------------------

local luapath = require("path")

local function exec_action(action_data, value_field_name, object_type, object_prefix)
    -- gather input data
    local file_path = action_data[value_field_name]
    -- NOTE: there is no need to do an additional validation of missing input values
    --       cause it is already done in cmodule package

    -- action business logic
    local remove_result, remove_err = os_remove_file(file_path)

    -- response generation
    local object_key = object_prefix
    if object_type == "proc_image" then
        object_key = object_key .. ".process"
    end

    local result                      = {}
    result[object_prefix]             = "file_object"
    result[object_key .. ".path"]     = luapath.dir(file_path)
    result[object_key .. ".name"]     = luapath.file(file_path)
    result[object_key .. ".ext"]      = luapath.ext(file_path)
    result[object_key .. ".fullpath"] = file_path
    if object_type == "proc_image" then
        result[object_prefix .. ".path"]     = result[object_key .. ".path"]
        result[object_prefix .. ".name"]     = result[object_key .. ".name"]
        result[object_prefix .. ".ext"]      = result[object_key .. ".ext"]
        result[object_prefix .. ".fullpath"] = result[object_key .. ".fullpath"]
    end
    result.result = remove_result or false
    result.reason = remove_result and "removed successful" or tostring(remove_err)

    return remove_result, result
end

---------------------------------------------------
-- action handlers configuration
---------------------------------------------------

local action_handlers = {}

action_handlers[MODULE.actions.fr_remove_object_file] = {
    -- handler must return two values:
    -- first is a boolean result flag(true - operation success, false - operation failed)
    -- second is an event object that need to be sent in the event stream
    handler = function(action_data)
        return exec_action(action_data, MODULE.fields.object_fullpath, "file", "object")
    end,
    -- success and failure are an event names that gonna be sent as a result of handler execution
    success = MODULE.events.fr_object_file_removed_successful,
    failure = MODULE.events.fr_object_file_removed_failed,
}

action_handlers[MODULE.actions.fr_remove_object_proc_image] = {
    handler = function(action_data)
        return exec_action(action_data, MODULE.fields.object_process_fullpath, "proc_image", "object")
    end,
    success = MODULE.events.fr_object_proc_image_removed_successful,
    failure = MODULE.events.fr_object_proc_image_removed_failed,
}

action_handlers[MODULE.actions.fr_remove_subject_proc_image] = {
    handler = function(action_data)
        return exec_action(action_data, MODULE.fields.subject_process_fullpath, "proc_image", "subject")
    end,
    success = MODULE.events.fr_subject_proc_image_removed_successful,
    failure = MODULE.events.fr_subject_proc_image_removed_failed,
}

---------------------------------------------------
-- cmodule init
---------------------------------------------------

return MODULE.start(action_handlers)
