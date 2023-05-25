require("module")
local ffi  = require("ffi")
local lfs  = require("lfs")
local md5  = require("md5")
local zip  = require("minizip")
local glue = require("glue")
local json = require("cjson.safe")
local luapath = require("path")

local sprofile = [[
{
    "wrapper": {
        "timeout_thread":5000,
        "steps":["normalizer", "correlator"],
        "messages_limit":100
    },
    "modules": {
        "normalizer": {
            "filename":"normalizer-module",
            "formats": {
                "input":"JSON",
                "output":"OBJECT"
            },
            "graph_filename":"formulas_graph.json",
            "timeout_pull":500,
            "timeout_thread":10,
            "keepalive_timeout":1000,
            "transfer_count":100,
            "messages_limit":500,
            "failure_alert":false,
            "workers": {
                "count":1,
                "timeout":5
            }
        },
        "correlator": {
            "filename":"correlator-module",
            "formats": {
                "input":"OBJECT",
                "output":"JSON"
            },
            "graph_filename":"rules_graph.json",
            "enricher_graph_filename":"enrules_graph.json",
            "timeout_thread":20,
            "timeout_pull":500,
            "keepalive_timeout":1000,
            "messages_limit":1000,
            "failure_transfer":false,
            "workers": {
                "count":1
            },
            "cache": {
                "update_period":30,
                "messages_limit":5000,
                "soft_ttl":1800,
                "hard_ttl":7200
            },
            "database_extensions": {
                "fpta": {
                    "enabled":false,
                    "path":"fpta_db.db"
                },
                "enricher": {
                    "enabled":false,
                    "path":"fpta_db.db"
                }
            }
        }
    }
}
]]

CCorrEngine = newclass("CCorrEngine")

function CCorrEngine:free()
    if self and self.valid == true then
        self.mdl:unregister()
        self.mdl = nil
        self.statistics = nil
        self.callbacks = nil
        self.valid = nil
    end
end

--init correlator [receiveEvents - callback result correlations, restore - restore database]
function CCorrEngine:init(receiveEvents, restore)
    local tmpdir_data = luapath.combine(__tmpdir, "data")
    zip.unzip(luapath.combine(tmpdir_data, "graphs.zip"), "-d", tmpdir_data)
    self.callbacks = {
        receive = function (type, data, size)
            if type == 1 and receiveEvents then
                receiveEvents(ffi.string(data, size))
            elseif type == 2 then
                self.statistics = json.decode(ffi.string(data, size))
            elseif type == 3 then
                __log.errorf("caught error from corr lib: '%s'", ffi.string(data, size))
            end

            return size
        end,
    }

    self.statistics = {}
    self.valid = false

    local jprofile = json.decode(sprofile)

    local _ext = ""
    if ffi.os == "Linux" then
        _ext = ".so"
    elseif ffi.os == "Windows" then
        _ext = ".dll"
    end

    for key, val in pairs(jprofile["modules"]) do
        jprofile["modules"][key]["filename"] = luapath.combine(__tmpdir, val["filename"] .. _ext)
        jprofile["modules"][key]["graph_filename"] = luapath.combine(tmpdir_data, val["graph_filename"])
        if val["enricher_graph_filename"] then
            jprofile["modules"][key]["enricher_graph_filename"] = luapath.combine(tmpdir_data, val["enricher_graph_filename"])
        end
    end

    local current_dir = luapath.normalize(lfs.currentdir())
    local global_dir = luapath.combine(current_dir, "_global")
    local global_dir_correlator = luapath.combine(global_dir, "correlator")

    for key, val in pairs(jprofile["modules"]["correlator"]["database_extensions"]) do
        local origfile = luapath.combine(tmpdir_data, val["path"] .. ".default")
        local orighash = self.get_file_hash_md5(origfile)
        local filename = luapath.combine(global_dir_correlator, orighash .. "_" .. key .. "_" .. val["path"])
        if lfs.attributes(filename, "size") == nil then
            restore = true
            break
        end
    end

    if restore == true then
        __log.infof("try to restore global database folder '%s'", global_dir_correlator)
        if lfs.attributes(global_dir_correlator, "modification") then
            __log.infof("clear global database folder '%s'", global_dir_correlator)
            for file in lfs.dir(global_dir_correlator) do
                if file ~= "." and file ~= ".." then
                    __log.infof("remove file '%s'", file)
                    os.remove(luapath.combine(global_dir_correlator, file))
                end
            end
        end
        lfs.mkdir(global_dir)
        lfs.mkdir(global_dir_correlator)
    end

    for key, val in pairs(jprofile["modules"]["correlator"]["database_extensions"]) do
        local filename = val["path"]
        local origfile = luapath.combine(tmpdir_data, filename .. ".default")
        local orighash = self.get_file_hash_md5(origfile)
        local localpath = luapath.combine(global_dir_correlator, orighash .. "_" .. key .. "_" .. filename)
        self.copyFile(origfile, localpath)
        if lfs.attributes(localpath, "size") then
            jprofile["modules"]["correlator"]["database_extensions"][key]["enabled"] = true
            jprofile["modules"]["correlator"]["database_extensions"][key]["path"] = localpath
            __log.infof("enable '%s' database extensions with path '%s'", key, localpath)
        end
    end

    self.mdl = CModule(luapath.combine(__tmpdir, "CorrelationInterface" .. _ext))
    __log.debugf("self.mdl=%s module_dir=%s/CorrelationInterface", tostring(self.mdl), __tmpdir)
    if self.mdl:register(json.encode(jprofile), self.callbacks) == true then
        self.mdl:start()
        self.valid = true
    else
        self:free()
    end
end

function CCorrEngine.get_file_hash_md5(filepath)
    local md5_digest = md5.digest()
    local file = io.open(filepath, "rb")
    if not file then
        return ""
    end
    local read_num, content = 1024 * 1024 -- 1 MB as a chunk to read file
    while true do
        content = file:read(read_num)
        if content == nil then break end
        md5_digest(content)
    end
    file:close()
    return glue.tohex(md5_digest())
end

function CCorrEngine.copyFile(src, dst, force)
    local f, err = io.open(src, "rb")
    if not f then return nil, err end

    local t, ok
    if not force then
        t = io.open(dst, "rb")
        if t then
            f:close()
            t:close()
            return nil, "file alredy exists"
        end
    end

    t, err = io.open(dst, "w+b")
    if not t then
        f:close()
        return nil, err
    end

    local CHUNK_SIZE = 4096
    while true do
        local chunk = f:read(CHUNK_SIZE)
        if not chunk then break end
        ok, err = t:write(chunk)
        if not ok then
            t:close()
            f:close()
            return nil, err or "can not write"
        end
    end

    t:close()
    f:close()
    collectgarbage("collect")
    return true
end

function CCorrEngine:copyDir(dir_from, dir_to, force)
    for file in lfs.dir(dir_from) do
        if file ~= "." and file ~= ".." then
            local f = dir_from .. "/" .. file
            local attr = lfs.attributes(f)

            if attr.mode == "directory" then
                self:copyDir(f, dir_to, force)
            end

            self.copyFile(f, luapath.combine(dir_to, file), force)
        end
    end
end

function CCorrEngine:isValid()
    return self.valid ~= nil and self.valid
end

function CCorrEngine:updateStats()
    if self:isValid() == false then return end
    self.mdl:send(2, "") --get statistics
    self.mdl:send(4, "") --pull events
end

function CCorrEngine:pullEvents()
    if self:isValid() == false then return end
    self.mdl:send(4, "") --pull events
end

function CCorrEngine:sendEvent(data)
    if self:isValid() == false then return false end
    if self.mdl:send(1, data) ~= #data then  -- if push event failed
        self:pullEvents()
        return false
    end
    return true
end
