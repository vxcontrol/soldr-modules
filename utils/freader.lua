require("yaci")
local lfs  = require("lfs")
local time = require("time")

CFileReader = newclass("CFileReader")

function CFileReader:init(is_debug, is_block, timer_ms, is_skip_empty)
    self.is_debug = false
    self.is_block = true
    self.timer_ms = 50
    self.is_skip_empty = true
    self.co = nil
    self.file_handle = nil
    self.last_size = 0
    self.last_modification = 0

    if type(is_debug) == "boolean" then
        self.is_debug = is_debug
    end
    if type(is_block) == "boolean" then
        self.is_block = is_block
    end
    if type(timer_ms) == "number" then
        self.timer_ms = timer_ms
    end
    if type(is_skip_empty) == "boolean" then
        self.is_skip_empty = is_skip_empty
    end
end

function CFileReader:print(...)
    if self.is_debug then
        print(...)
    end
end

function CFileReader:is_modification()
    local attr, err = lfs.attributes(self.file_path)
    if not attr then
        return false, err
    elseif self.last_size > attr["size"] then
        return true, "truncate"
    elseif self.last_size < attr["size"] then
        return true, "change size"
    elseif self.last_modification ~= attr["modification"] then
        return true, "updated"
    end
    return false, "nothing"
end

function CFileReader:get_modification()
    local attr, err = lfs.attributes(self.file_path)
    if not attr then
        return nil, err
    end
    return attr["modification"]
end

function CFileReader:check_modification(await, is_close)
    repeat
        if is_close() then
            return false, "closed"
        end
        if not self.is_follow then
            return true, "not follow"
        end
        local is_mod, msg = self:is_modification()
        if msg == "nothing" then
            if self.is_block then
                return true, msg
            else
                await(self.timer_ms)
            end
        elseif msg == "updated" then
            self.last_modification = self:get_modification()
        elseif msg == "truncate" and not self:open() then
            return false, "error"
        elseif is_mod == false then
            return false, msg
        else
            return true, "changed"
        end
    until not self.is_block
end

function CFileReader:get_size()
    local attr, err = lfs.attributes(self.file_path)
    if not attr then
        return nil, err
    end
    return attr["size"]
end

function CFileReader:open(file_path, file_op, is_follow, limit, step)
    if self.file_handle and io.type(self.file_handle) == "file" then
        self:print("Reader already initialized and it will be closed")
        self.file_handle:close()
    else
        self.file_path = nil
        self.file_op   = nil
        self.is_follow = false
        self.limit     = -1
        self.step      = 1

        if type(file_path) == "string" then
            self.file_path = file_path
        end
        if type(file_op) == "string" then
            self.file_op = file_op
        end
        if type(is_follow) == "boolean" then
            self.is_follow = is_follow
        end
        if type(limit) == "number" and limit >= 0 then
            self.limit = limit
        end
        if type(step) == "number" and step > 0 then
            self.step = step
        end
    end

    if self.limit ~= -1 and self.step > self.limit then
        return false, "limit should be greater than step"
    end
    if self.limit < -1 then
        return false, "limit should be greater or equal than -1"
    end
    if self.step <= 0 then
        return false, "step should be greater than 0"
    end

    if self.file_path then
        self.dir, self.file_name, self.file_ext =
            string.match(self.file_path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
    else
        return false, "File path doesn't set"
    end

    self.file_handle = io.open(self.file_path, "rb")
    if not self.file_handle then
        return false, "Can't open file: " .. file_path
    end

    if self.file_op == "tail" and self.is_follow then
        self.file_handle:seek("end")
    elseif self.file_op == "tail" and not self.is_follow then
        self.file_handle:seek("set")
        if self.limit ~= -1 then
            local ofsets = { 0 }
            for line in self.file_handle:lines() do
                local is_empty = string.match(line, "([^\r\n]*)")
                if is_empty and #is_empty > 0 then
                    table.insert(ofsets, self.file_handle:seek())
                end
            end
            if #ofsets <= self.limit then
                self.file_handle:seek("set")
            else
                self.file_handle:seek("set", ofsets[#ofsets - self.limit])
            end
        end
    elseif self.file_op == "head" then
        self.file_handle:seek("set")
    else
        self:print("File operation doesn't set")
    end

    self.last_size = self.file_handle:seek()
    self.last_modification = self:get_modification()
    return true
end

function CFileReader:get_lines(await, is_close)
    local nline = 0
    while self.limit == -1 or nline < self.limit do
        local lines = {}
        local res, msg = self:check_modification(await, is_close)
        if not res then
            self:print("Check modifications failed: ", msg)
            return res, msg
        end

        local date_marker = os.date("%Y-%m-%d %H:%M:%S ", os.time())
        for line in self.file_handle:lines() do
            self:print("<" .. date_marker .. "> " .. line)
            local is_empty = string.match(line, "([^\r\n]*)")
            if is_empty and #is_empty > 0 then
                nline = nline + 1
                table.insert(lines, line)
                if #lines == self.step or nline == self.limit then
                    self.last_size = self.file_handle:seek()
                    coroutine.yield(lines)
                    lines = {}
                end
                if nline == self.limit then
                    self:print("Lines limit exceeded: ", nline, self.limit)
                    break
                end
            end
        end

        if not self.is_follow or nline == self.limit or not self.is_block then
            if #lines ~= 0 then
                self.last_size = self.file_handle:seek()
                coroutine.yield(lines)
            end
            self:print("Get lines function was skipped: ",
                self.is_follow, nline, self.limit, self.is_block)
            break
        end
    end
    self:print("Get lines function was done")
    return true
end

function CFileReader:close()
    if io.type(self.file_handle) == "file" then
        self.file_handle:close()
    end
    self.co = nil
    self.file_handle = nil
    self.last_size = 0
    self.last_modification = 0
end

function CFileReader:get_sync_func(await, is_close)
    if type(await) ~= "function" and type(await) ~= "userdata" then
        self:print("Replace await function to default: ", await)
        await = function(delay) time.sleep(delay / 1000.) end
    end
    if type(is_close) ~= "function" and type(is_close) ~= "userdata" then
        self:print("Replace is_close function to default: ", is_close)
        is_close = function()
            if not self.file_handle then
                return true
            end
            return false
        end
    end
    return await, is_close
end

function CFileReader:read_line(await, is_close)
    await, is_close = self:get_sync_func(await, is_close)
    if not self.co or type(self.co) ~= "thread" then
        self.co = coroutine.create(self.get_lines)
    end
    while coroutine.status(self.co) == "suspended" do
        local _, lines = coroutine.resume(self.co, self, await, is_close)
        if coroutine.status(self.co) ~= "dead" then
            return lines
        end
    end
    self:print("Read line function was done")
    if self.is_block then
        self:close()
    else
        self.co = nil
    end
end

function CFileReader:read_line_cb(callback, await, is_close)
    if type(callback) ~= "function" then
        return false, "Callback doesn't set"
    end
    await, is_close = self:get_sync_func(await, is_close)
    if not self.co or type(self.co) ~= "thread" then
        self.co = coroutine.create(self.get_lines)
    end
    while coroutine.status(self.co) == "suspended" do
        local _, lines = coroutine.resume(self.co, self, await, is_close)
        if coroutine.status(self.co) ~= "dead" then
            callback(lines)
        end
    end
    self:print("Read line function callback was done")
    if self.is_block then
        self:close()
    else
        self.co = nil
    end
    return true
end
