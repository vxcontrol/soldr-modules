require("yaci")
require("strict")
require("storage")
local pp     = require("pp")
local fs    = require("fs")
local md5    = require("md5")
local sha2   = require("sha2")
local glue   = require("glue")
local crc32  = require("crc32")
local cjson  = require("cjson.safe")
local thread = require("thread")
local luapath = require("path")
math.randomseed(crc32(tostring({})))

CUploaderResp = newclass("CUploaderResp")

function CUploaderResp:print(...)
    if self.is_debug then
        local t = glue.pack(...)
        for i, v in ipairs(t) do
            t[i] = pp.format(v)
        end
        print(glue.unpack(t))
    end
end

--[[
    cfg top keys:
    * db - sqlite3 object to local DB.
        Use object instead construct because the class may used multiple times
        and destructor will called multiple times by engines response amount.
    * request_config - is a object which contains url and method keys to configure sender
    * request_headers - list of objects with name and value keys to extend request data
    * debug - boolean to run it in debug mode
    * debug_curl - boolean to run curl library client in debug mode
]]
function CUploaderResp:init(cfg)
    self.storage = NewFileUploaderStorage()
    self.storage.is_debug = cfg.debug

    self.request_config = cfg.request_config or {method="PUT", url=""}
    self.request_to_minio_config = cfg.request_to_minio_config or {url=""}
    self.s3_access_key = cfg.s3_access_key or ""
    self.s3_secret_key = cfg.s3_secret_key or ""
    self.s3_bucket = cfg.s3_bucket or ""
    self.request_headers = cfg.request_headers or {}
    self.is_debug = cfg.debug
    self.debug_curl = cfg.debug_curl

    if type(cfg.debug) == "boolean" then
        self.is_debug = cfg.debug
    end

    -- sender worker communication
    self.w_rth    = nil
    self.w_q_in   = thread.queue(100)
    self.w_q_out  = thread.queue(100)
    self.w_e_stop = thread.event()
    self.w_ctx = {
        is_debug = self.is_debug,
        debug_curl = self.debug_curl,
        url = self.request_config.url or "",
        method = self.request_config.method or "PUT",
        url_to_minio = self.request_to_minio_config.url or "",
        method_to_minio = "PUT",
        s3_access_key = self.s3_access_key or "",
        s3_secret_key = self.s3_secret_key or "",
        s3_bucket = self.s3_bucket or "",
        headers = self.request_headers
    }

    -- create engine table to collect raw events
    self.storage:CreateTable()
    self.storage:Migrate()
end

function CUploaderResp:free()
    self:print("finalize CUploaderResp object")
end

local function worker(ctx, q_in, q_out, e_stop)
    local ffi     = require("ffi")
    local lcurl   = require("libcurl")
    local lglue   = require("glue")
    local hmac = require("openssl").hmac
    local url     = ctx.url
    local method  = ctx.method

    local easy = lcurl.easy{
        post = true,
        verbose = ctx.debug_curl,
        ssl_verifyhost = false,
        ssl_verifypeer = false,
    }

    local g_print = print
    local print = function(...)
        if ctx.is_debug then
            g_print(...);
        end
    end

    local function base64_encode(data)
        local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

        return ((data:gsub('.', function(x)
            local r,b='',x:byte()
            for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
            return r;
        end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
            if (#x < 6) then return '' end
            local c=0
            for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
            return b:sub(c+1,c+1)
        end)..({ '', '==', '=' })[#data%3+1])
    end

    local function upload_file_to_external_server(task)
        local headers = {}
        local headers_map = {
            ["User-Agent"] = "SOLDR/1.0",
            ["Content-Type"] = "application/octet-stream",
            ["Expect"] = "",
        }
        lglue.map(ctx.headers, function(_, row)
            headers_map[row.name] = row.value
        end)
        lglue.map(headers_map, function(name, value)
            name = tostring(name) or ""
            value = tostring(value) or ""
            table.insert(headers, name .. ":" .. (value ~= "" and " " .. value or ""))
        end)

        local f = io.open(task.path, "rb")
        local ec = easy:clone()
        task.result = ""

        ec:set("httpheader", headers)
        ec:set("customrequest", method)
        ec:set("url", url)
        ec:set("writefunction", function(raw)
            local res = ffi.string(ffi.cast("char*", raw))
            task.result = task.result .. res
            return #res
        end)
        ec:set("readfunction", function(buf, size, nitems)
            local bytes = f:read(tonumber(size * nitems))
            if not bytes then
                return 0
            end
            ffi.copy(buf, bytes, #bytes)
            return #bytes
        end)

        local _, err, ecode = ec:perform()
        if err ~= nil then
            print("err=", err, "ecode=", ecode)
            task.result_task = "wait"
        else
            task.result_task = "success"
        end

        task.code = tonumber(ec:info("response_code")) or 0
        q_out:push(task)

        ec:close()
        f:close()
        headers = {}
    end

    local function upload_file_to_minio(task)
        local headers = {}
        local header_content_type = "application/octet-stream"
        local path_in_minio = string.format(
            "/%s/%s/%s/%s",
            ctx.s3_bucket,
            os.date("!%Y_%m_%d"),
            os.date("!%H_%M_%S"),
            task.name
        )
        local task_date = os.date("!%a, %d %b %Y %T %z")

        local signature = string.format(
            "%s\n\n%s\n%s\n%s",
            ctx.method_to_minio,
            header_content_type,
            task_date,
            path_in_minio
        )

        local sha = hmac.hmac("sha1", signature, ctx.s3_secret_key, true)
        local b64 = base64_encode(sha)

        local f = io.open(task.path, "rb")
        local ec = easy:clone()
        task.result = ""

        local function fsize(file)
            local current = file:seek()
            local size = file:seek("end")
            file:seek("set", current)
            return size
        end

        local headers_map = {
            ["User-Agent"] = "SOLDR/1.0",
            ["Content-Type"] = header_content_type,
            ["Date"] = task_date,
            ["Host"] = "127.0.0.1:9000",
            ["Authorization"] = string.format( "AWS %s:%s", ctx.s3_access_key, b64)
        }

        lglue.map(ctx.headers, function(_, row)
            headers_map[row.name] = row.value
        end)
        lglue.map(headers_map, function(name, value)
            name = tostring(name) or ""
            value = tostring(value) or ""
            table.insert(headers, name .. ":" .. (value ~= "" and " " .. value or ""))
        end)

        ec:set("infilesize", fsize(f))
        ec:set("upload", true)
        ec:set("httpheader", headers)
        ec:set("customrequest", ctx.method_to_minio)
        ec:set("url", string.format("%s%s", ctx.url_to_minio, path_in_minio))
        ec:set("writefunction", function(raw)
            local res = ffi.string(ffi.cast("char*", raw))
            task.result = task.result .. res
            return #res
        end)
        ec:set("readfunction", function(buf, size, nitems)
            local bytes = f:read(tonumber(size * nitems))
            if not bytes then
                return 0
            end
            ffi.copy(buf, bytes, #bytes)
            return #bytes
        end)

        local _, err, ecode = ec:perform()
        if err ~= nil then
            print("err=", err, "ecode=", ecode)
            task.result_task = "wait"
        else
            task.result_task = "success"
        end

        task.code = tonumber(ec:info("response_code")) or 0
        task.place = string.format("%s%s", ctx.url_to_minio, path_in_minio)
        q_out:push(task)

        ec:close()
        f:close()
        headers = {}
    end

    while true do
        if e_stop:isset() then break end
        local status, task = q_in:shift(os.time() + 1.0)
        if status then

            if task.action_name == "fu_upload_object_file" then
                upload_file_to_external_server(task)
            end

            if task.action_name == "fu_download_object_file" then
                upload_file_to_minio(task)
            end

        end
    end
end

function CUploaderResp:worker_start()
    self:print("worker_start CUploaderResp")
    if self.w_rth == nil then
        self.w_rth = thread.new(
            worker,
            self.w_ctx,
            self.w_q_in,
            self.w_q_out,
            self.w_e_stop
        )
    end
    return self.w_rth ~= nil
end

function CUploaderResp:worker_stop()
    self:print("worker_stop CUploaderResp")
    if self.w_rth ~= nil and self.w_e_stop ~= nil then
        self.w_e_stop:set()
        self.w_rth:join()
        self.w_e_stop = nil
        self.w_rth = nil
    end
    if self.w_q_in ~= nil then
        self.w_q_in:free()
        self.w_q_in = nil
    end
    if self.w_q_out ~= nil then
        self.w_q_out:free()
        self.w_q_out = nil
    end
end

function CUploaderResp:get_file_hashs(filepath)
    self:print("get_file_hashs CUploaderResp by file path", filepath)
    local md5_digest, sha256_digest = md5.digest(), sha2.sha256_digest()
    local file = io.open(filepath, "rb")
    if not file then
        return "", ""
    end
    local read_num, content = 1024 * 1024 -- 1 MB as a chunk to read file
    while true do
        content = file:read(read_num)
        if content == nil then break end
        md5_digest(content)
        sha256_digest(content)
    end
    file:close()
    return glue.tohex(md5_digest()), glue.tohex(sha256_digest())
end

function CUploaderResp:make_uuid()
    self:print("make_uuid CUploaderResp")
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

function CUploaderResp:make_upload_file_msg(uuid, filename, local_path, action_name, retaddr)
    self:print("make_upload_file_msg CUploaderResp", uuid, filename, local_path)
    return {
        ["uuid"] = uuid,
        ["type"] = "upload",
        ["path"] = local_path,
        ["name"] = filename,
        ["action_name"] = action_name,
        ["retaddr"] = retaddr
    }
end

function CUploaderResp:continue_incomplete()
    local files_to_upload = self.storage:FilesToUpload()
    if #files_to_upload ~= 0 then
        self:print("continue_incomplete CUploaderResp")
    end
    for _, file in ipairs(files_to_upload) do
        if not self:isExistsFileInFS(file.local_path) then
            self.storage:UpdateFileActionStatus("cancel", file.file_action_id)
            self.storage:DeleteFile(file.id)
        elseif file.uuid and file.filename and file.local_path then
            self.w_q_in:push(self:make_upload_file_msg(file.uuid, file.filename, file.local_path, file.action, nil))
            self.storage:UpdateFileActionStatus("process", file.file_action_id)
        end
    end
end

function CUploaderResp:getFilesInfoFromFilename(filename)
    return self.storage:GetFilesFromFilename(filename)
end

function CUploaderResp:isExistsFileInFS(fileLocalPath)
    local filename = luapath.file(fileLocalPath)
    local filesize = fs.attr(fileLocalPath, "size")
    if filename ~= nil and filesize ~= nil then
        return true
    end
    return false
end

function CUploaderResp:put_file(filename, local_path, aid)
    local uuid = self:make_uuid()
    local filesize = fs.attr(local_path, "size")
    if filesize == nil then
        self:print("local file not found by path", local_path)
        return false
    end
    local md5_hash, sha256_hash = self:get_file_hashs(local_path)
    self:print("put_file CUploaderResp", uuid, filename, md5_hash, sha256_hash, aid)
    if self.storage:CheckDuplicateFileByHash(md5_hash, sha256_hash) then
        self:print("found duplicate file by hash into local DB")
        return true
    end
    local status, err = self.storage:ExecPutFile(uuid, filename, filesize, md5_hash, sha256_hash, local_path, aid)
    if not status then
        self:print("failed to put file record to local DB", err)
        return false
    end
    return true
end

function CUploaderResp:start_upload_file(filename, md5_hash, sha256_hash, action_name, retaddr)
    local file = self.storage:GetFileForUpload(filename, md5_hash, sha256_hash)
    if file.id == nil then
        self:print("file not found: ", filename)
        return false
    end

    self.storage:SetNewFileOperation(file.id, action_name)

    if self.request_config.url == "" then
        self:print("external system url is not set so the record will store only to local DB")
        return true
    end
    if self.w_q_in == nil then
        self:print("failed to run file process, worker has already stopped")
        return false
    end
    self.w_q_in:push(self:make_upload_file_msg(file.uuid, filename, file.local_path, action_name, retaddr))
    return true
end

function CUploaderResp:upload_file(uuid, filename, local_path, code, resp, result, place)
    self:print("upload_file CUploaderResp", uuid, filename, local_path, code)
    local status, err = self.storage:ExecUploadFile(uuid, code, resp, result, place)
    if not status then
        self:print("failed to update (upload) file record in local DB", err)
        return false
    end
    if self.w_q_in == nil then
        self:print("failed to run file process, worker has already stopped")
        return false
    end
    return true
end

function CUploaderResp:process()
    local results = {}
    local status, resp
    repeat
        status, resp = self.w_q_out:shift(os.time() + 0.1)
        if status then
            self:print("got response from worker", resp.uuid, resp.type, resp.name, resp.path, resp.result)
            if type(resp.error) == "string" then
                self:print("failed to process http response from uploader: ", cjson.encode(resp))
            elseif resp.type == "upload" then
                if resp.retaddr ~= nil then
                    local msg_data = {
                        stage = resp.result_task
                    }
                    if resp.action_name == "fu_upload_object_file" then
                        msg_data.type = "exec_upload_resp"
                    elseif resp.action_name == "fu_download_object_file" then
                        msg_data.type = "exec_download_resp"
                        msg_data.place = resp.place
                    end
                    __api.send_data_to(resp.retaddr, cjson.encode(msg_data))
                end
                self:upload_file(resp.uuid, resp.name, resp.path, resp.code, resp.result, resp.result_task, resp.place)
            end
        end
    until not status
    self:continue_incomplete()
    return results
end
