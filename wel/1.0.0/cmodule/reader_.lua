local cjson  = require "cjson"
local cjsonf = require "cjson.safe"
local thread = require "thread"

--:: Channels :: [{
--::   channel  :: string
--::   select   :: string
--::   suppress :: string
--:: }]
--:: Channels -> {...}
local function profile(channels)
	local log_channels = {}
	for _, ch in ipairs(channels or {}) do
		log_channels[ch.channel] = {
			select   = ch.select,
			suppress = ch.suppress,
		}
	end

	return {
		output_format = "JSON",
		log_channels = log_channels,
		connection = {
			auth = {domain = "", login = "", password = ""},
			auth_type = "Negotiate",
		},
		event_buffer_size = 512,
		actualization_period = 600,
		new_events_only = true,
		inputs = {
			["00000000-0000-0000-0000-000000000000"] = {
				description = {
					expected_datetime_formats = {"DATETIME_ISO8601", "DATETIME_YYYYMMDD_HHMMSS"}}},
		},
		result_package = {
			package_quantity = 100,
			send_interval = 100,
		},
	}
end

local Reader = {}; Reader.__index = Reader

function Reader.new()
	return setmetatable({}, Reader)
end

--:: Channels, string -> ()
function Reader:configure(channels, sp_filename)
	self:close()

	local dllpath = __tmpdir .. "\\sys"
	local profile_json = cjson.encode(profile(channels))

	self._out = thread.queue(10)
	self._stop = thread.event()
	self._done = thread.event()
	self._wrk = thread.new(Reader._worker,
		__files, dllpath, profile_json, sp_filename, self._out, self._stop, self._done)
end

function Reader:close()
	if self._wrk then
		self._stop:set()
		self._wrk:join()
		self._out:free()
		self._wrk = nil
	end
end

local function with_body_decoded(records)
	for _, r in ipairs(records or {}) do
		if type(r)=="table" and r.body then
			r.body = cjsonf.decode(r.body) or r.body
		end end
	return records
end

--:: () -> [any]?
function Reader:read()
	self:_assert_worker()
	local ok, data = self._out:shift(0)
	if ok then
		return with_body_decoded(cjsonf.decode(data))
	end
end

function Reader:_assert_worker()
	if self._wrk and self._done:isset() then
		self:close()
	end
end

function Reader._worker(__files, dllpath, profile, sp_filename, out, stop, done)
	local ok, err = pcall(function()
		local function require_mod(name)
			local content = __files[name..".lua"]
			return assert(loadstring(content, name), "can't load: "..name)()
		end

		local k32 = require "waffi.windows.kernel32"
		local time = require "time"
		local CModule = (function() require_mod "module"; return CModule end)()

		k32.SetDllDirectoryA(dllpath)
		local cmodule = CModule("wineventlog.dll", function() end)

		cmodule:register(profile, {
			result = function(data)
				out:push(data)
			end,
			keep_alive = function()
				if stop:isset() then cmodule:stop() end
			end,
		}, sp_filename)

		cmodule:run()
		cmodule:unregister()
	end)

	done:set()
	assert(ok, err)
end

return Reader
