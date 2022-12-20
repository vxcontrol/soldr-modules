local protocol = {}

----------------------------------------------
-- Message names
----------------------------------------------
protocol.message_name = {}
protocol.message_name.action_response = "Module.Common.ActionResponse"
protocol.message_name.action_proxied = "Module.Сommon.ActionProxied"

----------------------------------------------
-- Connectivity errors
----------------------------------------------
protocol.connection_errors = {}
protocol.connection_errors.common = "Module.Common.AgentConnectionError"

----------------------------------------------
-- Validation errors
----------------------------------------------
protocol.validation_errors = {}
protocol.validation_errors.action_not_defined = "Module.Common.ActionNotDefinedInSchema"
protocol.validation_errors.action_data_missing_values = "Module.Common.ActionDataMissingValues"
protocol.validation_errors.action_data_field_not_defined = "Module.Common.ActionDataFieldNotDefined"
protocol.validation_errors.action_data_field_not_set = "Module.Common.ActionDataFieldValueNotSet"
protocol.validation_errors.validation_error = "Module.Common.ValidationError"

----------------------------------------------
-- Implementation errors
----------------------------------------------
protocol.implementation_errors = {}
protocol.implementation_errors.action_handler_not_defined = "Module.Common.ActionHandlerNotDefined"

----------------------------------------------
-- Business logic errors
----------------------------------------------
protocol.business_logic_errors = {}
protocol.business_logic_errors.action_handler_error = "Module.Common.ActionHandlerError"

return protocol
