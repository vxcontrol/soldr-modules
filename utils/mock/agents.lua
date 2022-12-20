local glue = require("glue")
---------------------------------------------------
local agents = {}
---------------------------------------------------

local function make_agent(agent)
    return {
        ["ID"]               = agent.id,
        ["GID"]              = agent.gid,
        ["Ver"]              = agent.ver,
        ["IP"]               = agent.ip,
        ["Src"]              = agent.src,
        ["Dst"]              = agent.dst,
        ["Type"]             = agent.type,
        ["IsOnlyForUpgrade"] = false,
        ["Info"]             = {
            ["Os"] = {
                ["Type"] = agent.os_type,
                ["Name"] = agent.os_name,
                ["Arch"] = agent.os_arch,
            },
            ["Net"] = {
                ["Hostname"] = agent.host,
                ["Ips"] = agent.ips,
            },
            ["Users"] = {
                {
                    ["Name"] = "unknown",
                    ["Groups"] = {
                        "unknown",
                    }
                }
            }
        }
    }
end

function agents.dump()
    __mock.trace("__agents.dump")
    return glue.map(__mock.agents, function(_, a) return make_agent(a) end)
end

function agents.count()
    __mock.trace("__agents.count")
    return #__mock.agents
end

function agents.get_by_id(agent_id)
    __mock.trace("__agents.get_by_id", agent_id)
    local list = {}
    for _, agent in ipairs(__mock.agents) do
        if agent.id == agent_id then
            list[agent.src] = make_agent(agent)
        end
    end
    return list
end

function agents.get_by_src(src)
    __mock.trace("__agents.get_by_src", src)
    local list = {}
    for _, agent in ipairs(__mock.agents) do
        if agent.src == src then
            table.insert(list, make_agent(agent))
        end
    end
    return list
end

function agents.get_by_dst(dst)
    __mock.trace("__agents.get_by_dst", dst)
    local list = {}
    for _, agent in ipairs(__mock.agents) do
        if agent.dst == dst then
            list[agent.dst] = make_agent(agent)
        end
    end
    return list
end

return agents
