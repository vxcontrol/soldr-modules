local audit = require "audit"
local pkg   = require "pkg"
local cjson = require "cjson"

local ok, err = audit.check_systemd()
if not ok then
	__log.error(err)
	__api.await(-1)
	return "success"
end

local pm, err = pkg.find_manager()
if not pm then
	__log.error(err)
	__api.await(-1)
	return "success"
end

local watcher = require("watcher").new()

local function update_config()
	local c = cjson.decode(__config.get_current_config())
	audit.file_auditd_conf:set(c.auditd_conf)
	audit.file_audit_rules:set(c.audit_rules)
	watcher:reset(c.check_interval)
end
update_config()

__api.add_cbs{
	control = function(cmtype, data)
		if cmtype == "update_config" then update_config() end
		return true
	end,
}

watcher:run(function()
	local ok, err = audit.setup(pm, {
		audit.file_auditd_service_override,
		audit.file_auditd_conf,
		audit.file_audit_rules,
	})
	if not ok then __log.error(err) end
end)
return "success"
