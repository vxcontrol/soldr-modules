local thread = require("thread")
local thds = {}

local function worker1(ctx)
    print("hello from thread:", ctx.id)
    return ctx.id
end
local function worker2(ctx)
    print("hello from thread:", ctx.id)
    return ctx.id
end

table.insert(thds, thread.new(worker1, {id=1}))
table.insert(thds, thread.new(worker2, {id=2}))
for _, thd in ipairs(thds) do print("join from main:", thd:join()) end
print("done")
