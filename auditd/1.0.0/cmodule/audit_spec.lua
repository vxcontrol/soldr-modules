local audit   = require "audit"
local exec    = require "exec"
local managed = require "managed"
local pkg     = require "pkg"

context("audit", function()
	test("check_systemd() #systemd", function()
		assert(audit.check_systemd())
	end)
end)

context("audit setup() #root #systemd #network #write", function()
	setup(function()
		pm = assert(pkg.find_manager())
	end)

	local function setup_and_assert()
		local files = {
			audit.file_auditd_service_override,
			audit.file_auditd_conf,
			audit.file_audit_rules,
		}
		audit.file_auditd_conf:set("# TEST")
		audit.file_audit_rules:set("-D\n-w /TEST\n")

		assert(audit.setup(pm, files))

		assert.equals("active", assert(exec("systemctl is-active auditd.service")))
		assert.equals("# TEST", assert(exec("cat /etc/audit/auditd.conf")))
		assert.equals("-w /TEST -p rwxa", assert(exec("auditctl -l")))
	end

	before_each(function()
		assert(exec("systemctl disable --now auditd.service; true"))
		assert(exec("rm -rf /etc/audit"))
		assert(exec("rm -rf /etc/systemd/system/auditd.service.d"))
		assert(exec("systemctl daemon-reload"))
		assert(exec("auditctl -D; true"))
	end)

	test("case: audit is not installed", function()
		-- TODO: remove package audit
		setup_and_assert()
	end)

	test("case: auditd is running with some rules in rules.d", function()
		assert(pm:install("audit", "auditd"))
		assert(exec("mkdir -p /etc/audit/rules.d"))
		assert(exec("echo -w /UNWANTED > /etc/audit/rules.d/unwanted.rules"))
		assert(exec("systemctl start auditd.service"))
		setup_and_assert()
	end)
end)
