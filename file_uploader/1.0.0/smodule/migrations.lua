local Migrations = {}

Migrations.__index = Migrations

function newMigrations(tables, fields)
    local m = {}
    setmetatable(m, Migrations)
    m.tables = tables
    m.fields = fields

    return m
end

function Migrations:create_table(t, fields)
    local table_fields = {}
    for field, ftype in pairs(fields) do
        table.insert(table_fields, field .. " " .. ftype)
    end
    table.sort(table_fields)

    return [[
        CREATE TABLE IF NOT EXISTS ]] .. t .. [[ (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ]] .. table.concat(table_fields, ", ") .. [[
        );
    ]]
end

-- List of migrations
--
-- This is a map:
--      key is a migration name (use for identification migration in table `migrations`);
--      value is a value of migration - SQL-query.
-- Up-down mechanism is not realized.
function Migrations:get_migrations()
    return {
        ["add_file_action_table"] = self:create_table(self.tables.file_action, self.fields.file_action_fields)
    }
end
