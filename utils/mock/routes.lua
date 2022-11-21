local glue = require("glue")
---------------------------------------------------
local routes = {}
---------------------------------------------------

function routes.dump()
    __mock.trace("__routes.dump")
    local map = {}
    glue.map(__mock.routes, function(_, r) map[r.dst] = r.src end)
    return map
end

function routes.count()
    __mock.trace("__routes.count")
    return #__mock.routes
end

function routes.get(dst)
    __mock.trace("__routes.get", dst)
    for _, route in ipairs(__mock.routes) do
        if route.dst == dst then
            return route.src
        end
    end
    return ""
end

function routes.add(dst, src)
    __mock.trace("__routes.add", dst, src)
    for _, route in ipairs(__mock.routes) do
        if route.dst == dst and route.src == src then
            return false
        end
    end
    if not glue.indexof(src, glue.imap(__mock.agents, "dst")) then
        return false
    end
    table.insert(__mock.routes, {dst=dst, src=src})
    return true
end

function routes.del(dst)
    __mock.trace("__routes.del", dst)
    local list = {}
    for _, route in ipairs(__mock.routes) do
        if route.dst ~= dst then
            table.insert(list, route)
        end
    end
    if #list ~= #__mock.routes then
        __mock.routes = list
        return true
    end
    return false
end

return routes
