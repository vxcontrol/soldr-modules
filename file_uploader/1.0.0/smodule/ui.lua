require("storage")

local UI = {}

UI.__index = UI

function newUI()
    local ui = {}
    setmetatable(ui, UI)
    ui.storage = NewFileUploaderStorage()

    return ui
end

function UI:getFiles(search_params, page, size)
    return self.storage:GetFiles(search_params, (page - 1) * size, size)
end

function UI:getCountOfFiles(search_params)
    return self.storage:GetCountOfFiles(search_params)
end

function UI:getFilesActions(search_params, page, size)
    local actions = self.storage:GetFilesActions(search_params, (page - 1) * size, size)
    for _, action in pairs(actions) do
        if action.action == "fu_upload_object_file" then
            action.action = "загрузка на удалённый сервер"
        elseif action.action == "fu_download_object_file" then
            action.action = "загрузка в minio"
        end

        if action.status == "success" then
            action.status = "успешно"
        elseif action.status == "process" then
            action.status = "в процессе"
        elseif action.status == "wait" then
            action.status = "ожидает"
        elseif action.status == "cancel" then
            action.status = "отменено"
        end
    end

    return actions
end

function UI:getCountOfFilesActions(search_params)
    return self.storage:GetCountOfFilesActions(search_params)
end


