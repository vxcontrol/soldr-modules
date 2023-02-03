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

local function setup_audit()
	local ok, err = audit.setup(pm, {
		audit.file_auditd_service_override,
		audit.file_auditd_conf,
		audit.file_audit_rules,
	})
	if not ok then __log.error(err) end
end

local check_interval_sec
local last_check = 0

local function update_config()
	local c = cjson.decode(__config.get_current_config())
	check_interval_sec = c.check_interval_sec
	audit.file_auditd_conf:set(c.auditd_conf)
	audit.file_audit_rules:set(c.audit_rules)
	last_check = 0
end
update_config()

__api.add_cbs{
	control = function(cmtype, data)
		if cmtype == "update_config" then update_config() end
		return true
	end,
}

while not __api.is_close() do
	local now = os.time()
	if now - last_check > check_interval_sec then
		last_check = now
		setup_audit()
	end
	__api.await(1000)
end
return "success"
