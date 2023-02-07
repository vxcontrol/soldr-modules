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

-- Abstraction over a managed state of Linux Auditing System.
local State = {}; State.__index = State

function State.new()
	return setmetatable({}, State)
end

-- Performs installation and configuration of Linux Auditing System.
-- It's idempotent and can be kept calling repeatedly, without any significant
-- performance cost, to ensure the system meets the required configuration.
--:: pkg.Manager, [managed.File] -> ok?, err::string?
function State:setup(pm, files)
	return try(function()
		assert(ensure_audit(pm))

		local rules = assert(exec("auditctl -l"))
		local status = assert(managed.ensure_all(files))
		if self._rules ~= rules or status == managed.MODIFIED then
			assert(exec("systemctl daemon-reload"))
			assert(exec("systemctl try-reload-or-restart auditd.service"))
		end

		assert(exec("systemctl start auditd.service"))
		self._rules = assert(exec("auditctl -l"))
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
ExecReload=
ExecReload=kill -HUP $MAINPID
ExecReload=-/sbin/auditctl -R /etc/audit/audit.rules
]]

return {
	State                        = State,
	check_systemd                = check_systemd,
	file_auditd_conf             = file_auditd_conf,
	file_audit_rules             = file_audit_rules,
	file_auditd_service_override = file_auditd_service_override,
}
