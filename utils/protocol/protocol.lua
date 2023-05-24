local protocol = {}

----------------------------------------------
-- Message names
----------------------------------------------
protocol.message_name = {}
protocol.message_name.action_response = "Module.Common.ActionResponse"
protocol.message_name.action_proxied = "Module.Common.ActionProxied"
protocol.message_name.data_request = "Module.Common.DataRequest"
protocol.message_name.data_response = "Module.Common.DataResponse"
protocol.message_name.data_proxied = "Module.Common.DataProxied"

----------------------------------------------
-- Message types
----------------------------------------------
protocol.message_type = {}
protocol.message_type.debug = 0
protocol.message_type.info  = 1
protocol.message_type.warn  = 2
protocol.message_type.error = 3

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
protocol.implementation_errors.data_handler_not_defined = "Module.Common.DataHandlerNotDefined"

----------------------------------------------
-- Business logic errors
----------------------------------------------
protocol.business_logic_errors = {}
protocol.business_logic_errors.action_handler_error = "Module.Common.ActionHandlerError"
protocol.business_logic_errors.data_handler_error = "Module.Common.DataHandlerError"

return protocol
