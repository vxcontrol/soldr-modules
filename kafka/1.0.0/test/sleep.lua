function sleep(ms)
	os.execute("sleep " .. ms/1e3)
end

return sleep
