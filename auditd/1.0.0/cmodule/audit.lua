local exec    = require "exec"
local managed = require "managed"
local try     = require "try"

-- Checks if systemd is available on current OS.
--:: () -> ok?, err::string?
local function check_systemd()
	return exec("type systemctl"),
		string.format("unsupported linux distro: systemd not found")
end

-- Ensures that audit is installed and available to use.
--:: pkg.Manager -> ok::boolean, err::string?
local function ensure_audit(pm)
	if exec("type auditctl") then
		return true end
	local ok, err = try(function()
		-- TODO: sync packages?
		-- assert(pm:sync())
		assert(pm:install("audit", "auditd"))
		assert(exec("type auditctl"))
		return true
	end)
	return ok, string.format("audit not available: %s", err)
end

--:: pkg.Manager, {managed.File,...} -> ok?, err::string?
local function setup(pm, files)
	return try(function()
		assert(ensure_audit(pm))

		local status = assert(managed.ensure_all(files))
		if status == managed.MODIFIED then
			assert(exec("systemctl daemon-reload"))
			assert(exec("systemctl reload-or-restart auditd.service"))
		end

		assert(exec("systemctl start auditd.service"))
		return status
	end)
end

local file_auditd_conf = managed.file("/etc/audit/auditd.conf", "644")
local file_audit_rules = managed.file("/etc/audit/audit.rules", "400")

-- Overrides configuration of auditd service to always read audit rules
-- from `/etc/audit/audit.rules` with `auditctl`.
-- (By default most linux distros are configured to use `augenrules` and
-- read audit rules from `/etc/audit/rules.d`)
local file_auditd_service_override =
	managed.file("/etc/systemd/system/auditd.service.d/override.conf", "644")
file_auditd_service_override:set[[
# Managed by SOLDR(auditd)
[Service]
ExecStartPost=
ExecStartPost=-/sbin/auditctl -R /etc/audit/audit.rules
]]

return {
	setup                        = setup,
	check_systemd                = check_systemd,
	file_auditd_conf             = file_auditd_conf,
	file_audit_rules             = file_audit_rules,
	file_auditd_service_override = file_auditd_service_override,
}
