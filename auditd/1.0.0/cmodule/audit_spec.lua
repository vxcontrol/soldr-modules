local audit   = require "audit"
local exec    = require "exec"
local managed = require "managed"
local pkg     = require "pkg"

local function has_prefix(str, prefix)
	return string.find(str, prefix, 1, true) == 1,
		string.format("expected %q has prefix %q", str, prefix)
end

context("audit", function()
	test("check_systemd() #systemd", function()
		assert(audit.check_systemd())
	end)
end)

context("audit setup() #root #systemd #network #write", function()
	setup(function()
		pm = assert(pkg.find_manager())
		state = audit.State.new()
	end)

	local function setup_and_assert()
		local files = {
			audit.file_auditd_service_override,
			audit.file_auditd_conf,
			audit.file_audit_rules,
		}
		audit.file_auditd_conf:set("#TEST\nspace_left = 1\n")
		audit.file_audit_rules:set("-D\n-w /TEST\n")

		assert(state:setup(pm, files))

		assert.equals("active", assert(exec("systemctl is-active auditd.service")))
		local conf = assert(exec("cat /etc/audit/auditd.conf"))
		assert(has_prefix(conf, "#TEST\n"))
		assert.equals("-w /TEST -p rwxa", assert(exec("auditctl -l")))
	end

	local function reset()
		assert(exec("systemctl disable --now auditd.service; true"))
		assert(exec("rm -rf /etc/systemd/system/auditd.service.d"))
		assert(exec("systemctl daemon-reload"))

		assert(exec("auditctl --signal TERM; true"))
		assert(exec("auditctl -D; true"))
		assert(exec("rm -rf /etc/audit"))
	end
	teardown(reset)

	test("case: audit is not installed", function()
		-- TODO: actually remove package audit
		reset()
		setup_and_assert()
	end)

	test("case: auditd is running with some rules in rules.d", function()
		reset()
		assert(pm:install("audit", "auditd"))
		assert(exec("mkdir -p /etc/audit/rules.d"))
		assert(exec("echo -w /UNWANTED > /etc/audit/rules.d/unwanted.rules"))
		assert(exec("systemctl start auditd.service"))
		setup_and_assert()
	end)

	test("case: someone's changed audit rules", function()
		setup_and_assert()
		assert(exec("auditctl -D"))
		setup_and_assert()
	end)
end)
