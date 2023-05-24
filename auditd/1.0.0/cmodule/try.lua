-- Strips "FILE:LINE:" prefix from an error message.
--:: string -> string
local function strip_place(err)
	return string.gsub(err, "^.-:.-: ", "")
end

-- Customized protected call around assert/error.
-- In contrast to pcall/xpcall returns unchanged list of the result arguments
-- of `f` on success.
local function try(f, ...)
	local args = table.pack(xpcall(f, strip_place, ...))
	if args[1] == true then
		return table.unpack(args, 2) end
	return table.unpack(args)
end

return try
