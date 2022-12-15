require("engine")
local cjson = require("cjson.safe")
local lfs = require("lfs")
local fs = require("fs")
local glue = require("glue")
local luapath = require("path")

-- variables to initialize event and action engines
local prefix_db = __gid .. "."
local fields_schema = __config.get_fields_schema()
local current_event_config = __config.get_current_event_config()
local module_info = __config.get_module_info()

-- event and action engines initialization
local action_engine = CActionEngine(
        {},
        __args["debug"][1] == "true"
)

local event_engine = CEventEngine(
        fields_schema,
        current_event_config,
        module_info,
        prefix_db,
        __args["debug"][1] == "true"
)

local module_config = cjson.decode(__config.get_current_config())

-- ########## SUPPORT FUNCTIONS ##########

local function reread_module_info()
    module_config = cjson.decode(__config.get_current_config())
end

-- arguments:
-- * opt - name of option
-- return value of requested config option
local function get_option_config(opt)
    for attr, val in pairs(module_config) do
        if attr == opt then
            return val
        end
    end

    return nil
end

local function exec_cmd(cmd)
    __log.debugf("cmd to exec: %s", cmd)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))

    f:close()
    return s
end

-- events executor by event name and data
local function push_event(event_name, event_data)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(event_data) == "table", "event_data must be a table")

    -- push the event to the engine
    local info = {
        ["name"] = event_name,
        ["data"] = event_data,
        ["actions"] = {},
    }
    local result, list = event_engine:push_event(info)
    -- check result return variable as marker is there need to execute actions
    if result then
        local data = action_engine:exec(__aid, list)
        for action_id, action_result in ipairs(data) do
            __log.debugf("action '%s' was requested: '%s'", action_id, action_result)
        end
    end
end

-- add brackets at the last and at the end of string
local function normalize_path(path)
    if path == "" then
        return ""
    end

    path = path:gsub("^%s*(.-)%s*$", "%1")
    local first = string.sub(path, 1, 1)
    if first ~= "\"" then
        path = "\"" .. path
    end

    local last = string.sub(path, -1, -1)
    if last ~= "\"" then
        path = path .. "\""
    end

    return path
end

-- remove brackets at the last and at the end of string
local function denormalize_path(path)
    local out = path:gsub([[\"]], ''):gsub([["]], '')

    return out
end

-- return string with raw content of file (use if agent run with admin permissions)
local function get_file_content(path)
    path = denormalize_path(path)

    local content = ''
    local file = io.open(path, "r")
    if file then
        content = file:read("*a")
        file:close()
    end

    return content
end

-- arguments:
-- *  path - path to removed dir
-- return bool
local function is_file_exist(path)
    path = denormalize_path(path)
    local isfile = fs.is(path, 'file')

    return isfile
end

local function is_dir_exist(path)
    path = denormalize_path(path)
    local isdir = fs.is(path, 'dir')

    return isdir
end

local function combine_path(...)
    local t = glue.pack(...)
    local path = t[1] or ""
    for i = 2, #t do
        path = luapath.combine(path, t[i])
    end
    return path
end

local function remove_dir(path)
    path = denormalize_path(path)
    for file in lfs.dir(path) do
        local file_path = combine_path(path, file)

        if not glue.indexof(file, { ".", ".." }) then
            if lfs.attributes(file_path, "mode") == "file" then
                os.remove(file_path)
            elseif lfs.attributes(file_path, "mode") == "directory" then
                remove_dir(file_path)
            end
        end
    end

    lfs.rmdir(path)

    return not is_dir_exist(path)
end

local function copy_file(srcin, dstin)
    local src = denormalize_path(srcin)
    local dst = denormalize_path(dstin)

    local f, err = io.open(src, 'rb')
    if not f then
        return nil, 'opening file (rb mode)' .. tostring(err)
    end

    local t, ok

    t, err = io.open(dst, 'w+b')
    if not t then
        f:close()
        return nil, 'opening file (w+b mode)' .. tostring(err)
    end

    local CHUNK_SIZE = 4096
    while true do
        local chunk = f:read(CHUNK_SIZE)
        if not chunk then
            break
        end
        ok, err = t:write(chunk)
        if not ok then
            t:close()
            f:close()
            return nil, 'writing file chunk' .. (err or "can not write")
        end
    end

    t:close()
    f:close()

    collectgarbage("collect")

    return true
end

-- arguments:
-- * name for creating tmp file
-- * path to updating file
-- * content of updating file
-- return
-- * true/false
-- * reason for falsey value
local function update_file(name, path, content)
    -- dumping
    local path_to_dumped_file = tostring(__tmpdir) .. "\\" .. name

    local file = io.open(path_to_dumped_file, "w+")
    if not file then
        return false, "can't open " .. path_to_dumped_file
    end

    local ok = file:write(content)
    file:close()

    if not ok then
        return false, "can't write content to file " .. path
    end

    -- copying dump
    local ok, err = copy_file(path_to_dumped_file, path)
    if not ok then
        return false, 'copying dump ' .. path_to_dumped_file .. ': ' .. err
    end

    return true, ""
end

return {
    get_option_config = get_option_config,
    get_file_content = get_file_content,
    push_event = push_event,
    exec_cmd = exec_cmd,
    normalize_path = normalize_path,
    module_config = module_config,
    is_file_exist = is_file_exist,
    remove_dir = remove_dir,
    reread_module_info = reread_module_info,
    update_file = update_file,
}
