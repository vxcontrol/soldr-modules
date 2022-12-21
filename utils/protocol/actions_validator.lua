require("yaci")
require("strict")

local cjson = require("cjson.safe")
local jsonschema = require("jsonschema")
local protocol = require("protocol/protocol")

CActionsValidator = newclass("CActionsValidator")

function CActionsValidator:init(fields_schema, action_config_schema)
    self.action_config_schema = cjson.decode(action_config_schema) or {}
    self.fields_schema        = cjson.decode(fields_schema) or {}

    self.actions = {}
    for action, action_config in pairs(self.action_config_schema.properties or {}) do
        self.actions[action] = ((((action_config.allOf or {})[2] or {}).properties or {}).fields or {}).default or {}
    end

    self.fields_validators = {}
    for field, schema in pairs(self.fields_schema.properties or {}) do
        self.fields_validators[field] = jsonschema.generate_validator(schema)
    end
end

function CActionsValidator:free()
    self.action_config_schema = nil
    self.fields_schema = nil
    self.actions = nil
    self.fields_validators = nil
end

function CActionsValidator:validate(action_name, action_data)
    assert(action_name, "action name must be provided")

    local action_config = self.actions[action_name]
    if action_config == nil then
        return false, protocol.validation_errors.action_not_defined,
            string.format("action '%s' is not defined in action_config_schema.json", action_name)
    end
    local number_of_actions_in_config = 0
    for _, field in ipairs(action_config) do
        number_of_actions_in_config = number_of_actions_in_config + 1
        local value = action_data[field]
        if value == nil then
            return false, protocol.validation_errors.action_data_missing_values,
                string.format("action data should contain value for '%s' field", field)
        end
        local field_validator = self.fields_validators[field]
        if field_validator == nil then
            return false, protocol.validation_errors.action_data_field_not_defined,
                string.format("field '%s' is not defined in fields_schema.json", field)
        end
        if value == nil or value == "" then
            return false, protocol.validation_errors.action_data_field_not_set,
                string.format("field '%s' value is not set", field)
        end
        local validation_result, validation_error = field_validator(value)
        if not validation_result then
            return false, protocol.validation_errors.validation_error, validation_error
        end
    end
    -- extra fields are allowed and not harming the validation
    return true
end
