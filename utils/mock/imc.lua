local glue = require("glue")
---------------------------------------------------
local imc = {}
---------------------------------------------------

function imc.get_token()
    __mock.trace("__imc.get_token")
    return __mock.module_token
end

function imc.get_info(token)
    __mock.trace("__imc.get_info", token)
    for _, module in ipairs(__mock.modules) do
        if module.token == token then
            return module.name, module.gid, true
        end
    end
    return "", "", false
end

function imc.is_exist(token)
    __mock.trace("__imc.is_exist", token)
    for _, module in ipairs(__mock.modules) do
        if module.token == token then
            return true
        end
    end
    return false
end

function imc.make_token(name, gid)
    __mock.trace("__imc.make_token", name, gid)
    return __mock.make_imc_token(name, gid)
end

function imc.get_groups()
    __mock.trace("__imc.get_groups")
    return __mock.groups
end

function imc.get_modules()
    __mock.trace("__imc.get_modules")
    return glue.imap(__mock.modules, "name")
end

function imc.get_groups_by_mid(name)
    __mock.trace("__imc.get_groups_by_mid", name)
    local groups_map = {}
    for _, module in ipairs(__mock.modules) do
        if module.name == name then
            groups_map[module.gid] = true
        end
    end
    local groups_list = {}
    glue.map(groups_map, function(tk)
        table.insert(groups_list, tk)
    end)
    return groups_list
end

function imc.get_modules_by_gid(gid)
    __mock.trace("__imc.get_modules_by_gid", gid)
    local modules_map = {}
    for _, module in ipairs(__mock.modules) do
        if module.gid == gid then
            modules_map[module.name] = true
        end
    end
    local modules_list = {}
    glue.map(modules_map, function(tk)
        table.insert(modules_list, tk)
    end)
    return modules_list
end

return imc
