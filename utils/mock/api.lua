local glue   = require("glue")
local socket = require("socket")
local protocol = require("protocol/protocol")
---------------------------------------------------
local api      = { unsafe = {} }
---------------------------------------------------

function api.unsafe.lock() end

function api.unsafe.unlock() end

function api.add_cbs(cbs)
    local scbs = {}
    glue.map(cbs, function(tk, tv) table.insert(scbs, string.format("%s:%s", tk, tv)) end)
    __mock.trace("__api.add_cbs", glue.unpack(scbs))
    for name, cb in pairs(cbs) do
        __mock.module_callbacks[name] = cb
    end
    return false
end

function api.del_cbs(cbs)
    local scbs = glue.map(cbs, function(_, tv) tostring(tv) end)
    __mock.trace("__api.del_cbs", glue.unpack(scbs))
    for _, name in ipairs(cbs) do
        __mock.module_callbacks[name] = nil
    end
    return false
end

function api.set_recv_timeout(time)
    __mock.trace("__api.set_recv_timeout", time)
end

function api.use_sync_mode()
    __mock.trace("__api.use_sync_mode")
    return true
end

function api.use_async_mode()
    __mock.trace("__api.use_async_mode")
    return true
end

---------------------------------------------------

function api.send_data_to(dst, data)
    __mock.trace("__api.send_data_to", dst, data)
    if __mock.callbacks.data then
        return __mock.callbacks.data(__mock, dst, __mock.module_token, data)
    end
    return false
end

function api.send_file_to(dst, data, name)
    __mock.trace("__api.send_file_to", dst, data, name)
    local path = __mock.tmppath(__mock.rand_uuid())
    assert(glue.writefile(path, data), "failed to write temp file")
    if __mock.callbacks.file then
        return __mock.callbacks.file(__mock, dst, __mock.module_token, path, name)
    end
    return false
end

function api.send_text_to(dst, data, name)
    __mock.trace("__api.send_text_to", dst, data, name)
    if __mock.callbacks.text then
        return __mock.callbacks.text(__mock, dst, __mock.module_token, data, name)
    end
    return false
end

function api.send_msg_to(dst, data, mtype)
    assert(dst ~= nil and dst ~= "", "message destination must be defined")
    assert(data ~= nil and data ~= "", "message data must be defined")
    assert(mtype ~= nil and mtype ~= "", "message mtype must be defined")
    assert(mtype >= protocol.message_type.debug and mtype <= protocol.message_type.error,
        "message mtype must contain suppoted value")

    __mock.trace("__api.send_msg_to", dst, data, mtype)
    if __mock.callbacks.msg then
        return __mock.callbacks.msg(__mock, dst, __mock.module_token, data, mtype)
    end
    return false
end

function api.send_action_to(dst, data, name)
    __mock.trace("__api.send_action_to", dst, data, name)
    if __mock.callbacks.action then
        return __mock.callbacks.action(__mock, dst, __mock.module_token, data, name)
    end
    return false
end

function api.send_file_from_fs_to(dst, path, name)
    __mock.trace("__api.send_file_from_fs_to", dst, path, name)
    if __mock.callbacks.file then
        return __mock.callbacks.file(__mock, dst, __mock.module_token, path, name)
    end
    return false
end

function api.async_send_data_to(dst, data, callback)
    __mock.trace("__api.async_send_data_to", dst, data, tostring(callback))
    if __mock.callbacks.data then
        callback(__mock.callbacks.data(__mock, dst, __mock.module_token, data))
    else
        callback(false)
    end
    return true
end

function api.async_send_file_to(dst, data, name, callback)
    __mock.trace("__api.async_send_file_to", dst, data, name, tostring(callback))
    local path = __mock.tmppath(__mock.rand_uuid())
    assert(glue.writefile(path, data), "failed to write temp file")
    if __mock.callbacks.file then
        callback(__mock.callbacks.file(__mock, dst, __mock.module_token, path, name))
    else
        callback(false)
    end
    return true
end

function api.async_send_msg_to(dst, data, mtype, callback)
    __mock.trace("__api.async_send_msg_to", dst, data, mtype, tostring(callback))
    if __mock.callbacks.msg then
        callback(__mock.callbacks.msg(__mock, dst, __mock.module_token, data, mtype))
    else
        callback(false)
    end
    return true
end

function api.async_send_action_to(dst, data, name, callback)
    __mock.trace("__api.async_send_action_to", dst, data, name, tostring(callback))
    if __mock.callbacks.action then
        callback(__mock.callbacks.action(__mock, dst, __mock.module_token, data, name))
    else
        callback(false)
    end
    return true
end

function api.async_send_file_from_fs_to(dst, path, name, callback)
    __mock.trace("__api.async_send_file_from_fs_to", dst, path, name, tostring(callback))
    if __mock.callbacks.file then
        callback(__mock.callbacks.file(__mock, dst, __mock.module_token, path, name))
    else
        callback(false)
    end
    return true
end

function api.push_event(agent_id, event)
    __mock.trace("__api.push_event", agent_id, event)
    if __mock.callbacks.push_event then
        return __mock.callbacks.push_event(__mock, agent_id, event)
    end
    return false
end

---------------------------------------------------

function api.await(time)
    __mock.trace("__api.await", time)
    if coroutine.running() then
        local stime, etime = socket.gettime() * 1000, 0 -- in milliseconds
        while not api.is_close() and (etime < time or time == -1) do
            coroutine.yield(false)
            socket.sleep(0.1)
            etime = socket.gettime() * 1000 - stime
        end
    end
end

function api.is_close()
    __mock.trace("__api.is_close")
    return __mock.is_closed
end

function api.async(f, ...)
    __mock.trace("__api.async", tostring(f), ...)
    api.unsafe.unlock()
    local t = glue.pack(f(...))
    api.unsafe.lock()
    return glue.unpack(t)
end

function api.sync(f, ...)
    __mock.trace("__api.sync", tostring(f), ...)
    api.unsafe.lock()
    local t = glue.pack(f(...))
    api.unsafe.unlock()
    return glue.unpack(t)
end

---------------------------------------------------

function api.recv_data()
    __mock.trace("__api.recv_data")
    local src, data, res = "", "", false
    return src, data, res
end

function api.recv_file()
    __mock.trace("__api.recv_file")
    local src, path, name, res = "", "", "", false
    return src, path, name, res
end

function api.recv_text()
    __mock.trace("__api.recv_text")
    local src, data, name, res = "", "", "", false
    return src, data, name, res
end

function api.recv_msg()
    __mock.trace("__api.recv_msg")
    local src, data, mtype, res = "", "", "", false
    return src, data, mtype, res
end

function api.recv_action()
    __mock.trace("__api.recv_action")
    local src, data, name, res = "", "", "", false
    return src, data, name, res
end

function api.recv_data_from(src)
    __mock.trace("__api.recv_data_from", src)
    local data, res = "", false
    return data, res
end

function api.recv_file_from(src)
    __mock.trace("__api.recv_file_from", src)
    local path, name, res = "", "", false
    return path, name, res
end

function api.recv_text_from(src)
    __mock.trace("__api.recv_text_from", src)
    local data, name, res = "", "", false
    return data, name, res
end

function api.recv_msg_from(src)
    __mock.trace("__api.recv_msg_from", src)
    local data, mtype, res = "", "", false
    return data, mtype, res
end

function api.recv_action_from(src)
    __mock.trace("__api.recv_action_from", src)
    local data, name, res = "", "", false
    return data, name, res
end

---------------------------------------------------

function api.get_name()
    __mock.trace("__api.get_name")
    return __mock.module
end

function api.get_os()
    __mock.trace("__api.get_os")
    return __mock.os.type
end

function api.get_arch()
    __mock.trace("__api.get_arch")
    return __mock.os.arch
end

function api.get_exec_path()
    __mock.trace("__api.get_exec_path")
    return arg[0]
end

---------------------------------------------------

return api
