local Watcher = {}; Watcher.__index = Watcher

--:: seconds? -> Watcher
function Watcher.new(interval)
	return setmetatable({
		_interval = interval or 0,
	}, Watcher)
end

--:: seconds? -> ()
function Watcher:reset(interval)
	self._last_run = 0
	self._interval = interval or self._interval
end

function Watcher:run(f)
	self._last_run = 0
	self._interval = self._interval or 1

	while not __api.is_close() do
		local now = os.time()
		if now - self._last_run >= self._interval then
			self._last_run = now
			f()
		end
		__api.await(1000)
	end
end

return Watcher
