require("uploader")
require("storage")
require("ui")
local cjson   = require("cjson.safe")

-- uploader variables
local fu_db
local uploader
local ui
local module_config = cjson.decode(__config.get_current_config()) or {}

-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

-- getting agent ID by dst token and agent type
local function get_agent_id_by_dst(dst, atype)
    for token, info in pairs(__agents.get_by_dst(dst)) do
        if token == dst then
            if tostring(info.Type) == atype or atype == "any" then
                return tostring(info.ID), info
            end
        end
    end
    return "", {}
end

-- getting agent source token by ID and agent type
local function get_agent_src_by_id(id, atype)
    for client_id, client_info in pairs(__agents.get_by_id(id)) do
        if tostring(client_info.Type) == atype or atype == "any" then
            return tostring(client_id), client_info
        end
    end
    return "", {}
end

-- initialize uploader worker into global module state
local function init_uploader()
    uploader = CUploaderResp({
        db = fu_db,
        debug = __args["debug_uploader"][1] == "true",
        debug_curl = __args["debug_curl"][1] == "true",
        request_config = get_option_config("request_config"),
        request_to_minio_config = get_option_config("request_to_minio_config"),
        s3_access_key = get_option_config("s3_access_key"),
        s3_secret_key = get_option_config("s3_secret_key"),
        s3_bucket = get_option_config("s3_bucket"),
        request_headers = get_option_config("request_headers"),
    })
    if not uploader:worker_start() then
        __log.error("failed to initialize uploader worker")
        uploader = nil
        collectgarbage("collect")
    end
end

-- uploader cache database
fu_db = GetDB()
if fu_db ~= nil then
    init_uploader()
    ui = newUI()
end

-- set default timeout to wait exit on blocking of recv_* functions
__api.set_recv_timeout(5000) -- 5s

__api.add_cbs({
    data = function(src, data)
        __log.infof("receive data from '%s' with data %s", src, data)

        local msg_data = cjson.decode(data) or {}
        local vxagent_id = get_agent_id_by_dst(src, "VXAgent")
        if vxagent_id ~= "" then
            if msg_data["type"] == "exec_upload_resp" then
                __log.debugf("server module got response by exec from agent")
                local dst = msg_data.retaddr
                msg_data.retaddr = nil
                msg_data.status = msg_data.status and "success" or "error"

                local start_upload_file_result = nil

                if msg_data.name == "fu_upload_object_file" then
                    if #msg_data.existing_file ~= 0 then
                        start_upload_file_result = uploader:start_upload_file(
                            msg_data.existing_file["filename"],
                            msg_data.existing_file["md5_hash"],
                            msg_data.existing_file["sha256_hash"],
                            "fu_upload_object_file",
                            dst
                        )
                    else
                        start_upload_file_result = uploader:start_upload_file(
                            msg_data.data["object.name"],
                            msg_data.data["md5_hash"],
                            msg_data.data["sha256_hash"],
                            "fu_upload_object_file",
                            dst
                        )
                    end
                    if start_upload_file_result == nil then
                        msg_data.stage = "process"
                        local send_res = __api.send_data_to(dst, cjson.encode(msg_data))
                        __log.debugf("response routed to '%s' with result %s", dst, send_res)
                    end
                elseif msg_data.name == "fu_download_object_file" then
                    msg_data.type = "exec_download_resp"
                    if #msg_data.existing_file == 0 then
                        local fl = uploader.storage:GetFileInfoByHash(msg_data.data.md5_hash, msg_data.data.sha256_hash)
                        msg_data.existing_file = fl
                    end

                    start_upload_file_result = uploader:start_upload_file(
                        msg_data.existing_file["filename"],
                        msg_data.existing_file["md5_hash"],
                        msg_data.existing_file["sha256_hash"],
                        "fu_download_object_file",
                        dst
                    )
                end

                if start_upload_file_result ~= nil then
                    local payload = {
                        status = "error_upload",
                        error = start_upload_file_result,
                    }
                    __api.send_data_to(dst, cjson.encode(payload))
                end
            else
                __log.debugf("receive unknown type message '%s' from agent", msg_data["type"])
            end
        else
            -- msg from browser or external...
            if msg_data["type"] == "exec_sql_req" then
                __log.debugf("server module got request to exec SQL query")
                exec_query(src, msg_data, fu_db)
            elseif msg_data["type"] == "fu_get_files" then
                local files = ui:getFiles(msg_data["search"], msg_data["page"], msg_data["pageSize"])
                local count_of_files = ui:getCountOfFiles(msg_data["search"])
                local response, jerr = cjson.encode({
                    type = "fu_get_files",
                    files = files,
                    total = count_of_files
                })
                if not response then
                    __log.errorf("failed to encode files by exec: %s", jerr)
                end
                __api.send_data_to(src, response)
            elseif msg_data["type"] == "fu_get_files_actions" then
                local files_actions = ui:getFilesActions(msg_data["search"], msg_data["page"], msg_data["pageSize"])
                local count_of_files_actions = ui:getCountOfFilesActions(msg_data["search"])
                local response, jerr = cjson.encode({
                    type = "fu_get_files_actions",
                    filesActions = files_actions,
                    total = count_of_files_actions
                })
                if not response then
                    __log.errorf("failed to encode files actions by exec: %s", jerr)
                end
                __api.send_data_to(src, response)
            elseif msg_data["type"] == "fu_delete_file" then
                local file = uploader.storage:GetFileLocalPathByFileId(msg_data["id"])
                if file ~= nil then
                    for _, f in ipairs(file) do
                        local err = os.remove(f.local_path)
                        if err ~= true and err ~= nil then
                            __log.errorf("failed to delete file with id %s in local_path %s: %s", msg_data["id"], f.local_path, err)
                        else
                            uploader.storage:DeleteFile(msg_data["id"])
                            local response, jerr = cjson.encode({
                                type = "fu_delete_file",
                                id = msg_data["id"]
                            })
                            if not response then
                                __log.errorf("failed to encode response about deleted file: %s", jerr)
                            end
                            __api.send_data_to(src, response)
                        end
                    end
                end
            else
                __log.debugf("receive unknown type message '%s' from browser", msg_data["type"])
            end
        end

        return true
    end,

    file = function(src, path, name)
        __log.infof("receive file from '%s' with name '%s' path '%s'", src, name, path)

        local aid = get_agent_id_by_dst(src, "any")
        if uploader == nil or not uploader:put_file(name, path, aid) then
            __log.error("failed to process file via uploader")
        end
        return true
    end,

    -- text = function(src, text, name)
    -- msg = function(src, msg, mtype)

    action = function(src, data, action_name)
        __log.infof("receive action '%s' from '%s' with data %s", action_name, src, data)

        local action_data = cjson.decode(data)
        assert(type(action_data) == "table", "input action data type is invalid")
        action_data.retaddr = src
        local id, _ = get_agent_id_by_dst(src, "any")
        local dst, _ = get_agent_src_by_id(id, "VXAgent")
        if dst ~= "" then
            __log.debugf("send action request to '%s'", dst)

            if action_name == "fu_upload_object_file" or action_name == "fu_download_object_file" then
                local filename = string.gsub(action_data["data"]["object.fullpath"], "(.*/)(.*)", "%2")
                filename = string.gsub(filename, "(.*\\)(.*)", "%2")

                if filename ~= nil and filename ~= "" then
                    local files = uploader:getFilesInfoFromFilename(filename)
                    action_data["data"]["files"] = {}
                    if #files ~= 0 then
                        for i, file in ipairs(files) do
                            local isExistsFile = uploader:isExistsFileInFS(file.local_path)
                            if isExistsFile then
                                action_data["data"]["files"][i] = {
                                    ["id"] = file.id,
                                    ["sha256_hash"] = file.sha256_hash,
                                    ["filename"] = file.filename,
                                    ["filesize"] = file.filesize,
                                    ["uuid"] = file.uuid,
                                    ["md5_hash"] = file.md5_hash,
                                    ["local_path"] = file.local_path
                                }
                            else
                                uploader.storage:DeleteFile(file.id)
                            end
                        end
                    end
                end
            end

            __api.send_action_to(dst, cjson.encode(action_data), action_name)

            local msg_data = {
                type = "prepare_upload_resp"
            }
            __api.send_data_to(action_data.retaddr, cjson.encode(msg_data))
        else
            local payload = {
                status = "error",
                error = "connection_error",
            }
            __log.debugf("send response data to '%s'", src)
            __api.send_data_to(src, cjson.encode(payload))
        end

        return true
    end,

    control = function(cmtype, data)
        __log.debugf("receive control msg '%s' with data %s", cmtype, data)

        -- cmtype: "quit"
        -- cmtype: "agent_connected"
        -- cmtype: "agent_disconnected"
        if cmtype == "update_config" then
            -- update current module config
            module_config = cjson.decode(__config.get_current_config()) or {}

            -- update uploader state after changing module config
            if uploader ~= nil then
                uploader:worker_stop()
            end
            init_uploader()
        end

        return true
    end,
})

__log.infof("module '%s' was started", __config.ctx.name)

while not __api.is_close() do
    if uploader ~= nil then
        uploader:process()
    end
    __api.await(1000)
end

-- release uploader
if uploader ~= nil then
    uploader:worker_stop()
    uploader = nil
end
collectgarbage("collect")

-- release database
if fu_db ~= nil then
    fu_db = nil
end
collectgarbage("collect")

__log.infof("module '%s' was stopped", __config.ctx.name)

return "success"
