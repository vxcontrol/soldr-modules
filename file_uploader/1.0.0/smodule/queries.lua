local Queries = {}

Queries.__index = Queries

function newQueries()
    local q = {}
    setmetatable(q, Queries)

    return q
end

function Queries:create_table(t, fields)
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

function Queries:get_incomplete_upload()
    return [[
        select
            f.id
            , f.uuid
            , f.time
            , f.filename
            , f.filesize
            , f.md5_hash
            , f.sha256_hash
            , f.local_path
            , fa.upload_response
            , fa.upload_code
            , fa.action
            , f.agent_id
            , f.group_id
            , fa.id as file_action_id
        from files f
        left join file_action fa on f.id = fa.file_id
        where
            f.group_id = ?
            and fa.result = ?
            and (strftime('%s', 'now') - (strftime('%s', fa.time))) > 60
        order by f.id desc;
    ]]
end

function Queries:get_file_for_upload(t)
    return [[
        select
            id
            , uuid
            , filename
            , local_path
        from ]] .. t .. [[
        where
            filename = ?
            and md5_hash = ?
            and deleted is null
            and sha256_hash = ?;
    ]]
end

function Queries:get_file_info_by_uuid(t, fields)
    return [[
        SELECT ]] .. table.concat(fields, ", ") .. [[
        FROM ]] .. t .. [[
        WHERE uuid LIKE ?;
    ]]
end

function Queries:get_file_info_by_hash(t)
    return [[
        SELECT
            uuid
            , time
            , filename
            , filesize
            , md5_hash
            , sha256_hash
            , local_path
            , agent_id
            , group_id
        FROM ]] .. t .. [[
        WHERE md5_hash LIKE ? OR sha256_hash LIKE ?
        ORDER BY time DESC;
    ]]
end

function Queries:check_duplicate_file_by_hash(t)
    return [[
        SELECT filename, filesize, md5_hash, sha256_hash
        FROM ]] .. t .. [[
        WHERE (md5_hash LIKE ? OR sha256_hash LIKE ?) AND
            time >= datetime('now', '-7 days') AND deleted is null
        ORDER BY time DESC;
    ]]
end

function Queries:get_uploaded_files(t, fields)
    return [[
        SELECT ]] .. table.concat(fields, ", ") .. [[
        FROM ]] .. t .. [[
        ORDER BY time DESC;
    ]]
end

function Queries:put_file(t, fields)
    local prepositions = {}
    for _=1,#fields do
        table.insert(prepositions, "?")
    end
    return [[
        INSERT OR IGNORE INTO ]] .. t .. [[ (
        ]] .. table.concat(fields, ", ") .. [[
        ) VALUES (
            ]] .. table.concat(prepositions, ", ") .. [[
        );
    ]]
end

function Queries:get_file_from_filename(t)
    return [[
        select id, uuid, filename, filesize, md5_hash, sha256_hash, local_path
        from ]] .. t .. [[
        where filename = ? and deleted is null
        order by time DESC;
    ]]
end

function Queries:upload_file_resp(t)
    return [[
        UPDATE ]] .. t .. [[ SET
            upload_code = ?,
            upload_response = ?,
            result = ?,
            time = strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'),
            place = ?
        WHERE file_id = ? and (result = ? or result = ?) and action = ?;
    ]]
end

function Queries:update_file_action_status(t)
    return [[
        UPDATE ]] .. t .. [[ SET
            result = ?
        WHERE id = ?;
    ]]
end

function Queries:set_file_action(t)
    return [[
        INSERT INTO ]] .. t .. [[ (
            file_id, action, result
        ) VALUES (
            ?, ?, ?
        );
    ]]
end

function Queries:delete_file(t)
    return [[
        UPDATE ]] .. t .. [[ SET deleted = 1 WHERE id = ?;
    ]]
end

function Queries:get_files(t, search_params)
    return [[
        select
            id
            , uuid
            , time
            , filename
            , filesize
            , md5_hash
            , sha256_hash
            , local_path
            , agent_id
            , group_id
            , deleted
        from ]] .. t .. [[
        where deleted is null
            and (case when ']] .. search_params['name'] .. [[' <> '' then filename like '%]] .. search_params['name'] .. [[%' else true end)
            and (case when ']] .. search_params['agent_id'] .. [[' <> '' then agent_id like '%]] .. search_params['agent_id'] .. [[%' else true end)
            and (case when ']] .. search_params['group_id'] .. [[' <> '' then group_id like '%]] .. search_params['group_id'] .. [[%' else true end)
            and (case when ']] .. search_params['md5'] .. [[' <> '' then md5_hash = ']] .. search_params['md5'] .. [[' else true end)
            and (case when ']] .. search_params['sha256'] .. [[' <> '' then sha256_hash = ']] .. search_params['sha256'] .. [[' else true end)
        order by id desc
        limit ?, ?;
    ]]
end

function Queries:count_files(t, search_params)
    return [[
        select count(*) as count from ]] .. t .. [[
        where deleted is null
            and (case when ']] .. search_params['name'] .. [[' <> '' then filename like '%]] .. search_params['name'] .. [[%' else true end)
            and (case when ']] .. search_params['agent_id'] .. [[' <> '' then agent_id like '%]] .. search_params['agent_id'] .. [[%' else true end)
            and (case when ']] .. search_params['group_id'] .. [[' <> '' then group_id like '%]] .. search_params['group_id'] .. [[%' else true end)
            and (case when ']] .. search_params['md5'] .. [[' <> '' then md5_hash = ']] .. search_params['md5'] .. [[' else true end)
            and (case when ']] .. search_params['sha256'] .. [[' <> '' then sha256_hash = ']] .. search_params['sha256'] .. [[' else true end)
        ;
    ]]
end

function Queries:get_file_local_path_by_file_id(t)
    return [[
        SELECT local_path
        FROM ]] .. t .. [[
        WHERE id = ?;
    ]]
end

function Queries:get_files_actions(t1, t2, search_params)
    return [[
        select
            f.filename
            , f.agent_id
            , fa.action
            , fa.result as status
            , fa.place
            , fa.time
            , fa.upload_code
            , fa.upload_response
        from ]] .. t1 .. [[ f join ]] .. t2 .. [[ fa on fa.file_id = f.id
        where
            (case when ']] .. search_params['name'] .. [[' <> '' then f.filename like '%]] .. search_params['name'] .. [[%' else true end)
            and (case when ']] .. search_params['agent_id'] .. [[' <> '' then f.agent_id like '%]] .. search_params['agent_id'] .. [[%' else true end)
            and (case when ']] .. search_params['action'] .. [[' <> '' then fa.action like '%]] .. search_params['action'] .. [[%' else true end)
            and (case when ']] .. search_params['status'] .. [[' <> '' then fa.result like '%]] .. search_params['status'] .. [[%' else true end)
        order by fa.time desc
        limit ?, ?;
    ]]
end

function Queries:count_files_actions(t1, t2, search_params)
    return [[
        select count(*) as count
        from ]] .. t1 .. [[ f join ]] .. t2 .. [[ fa on fa.file_id = f.id
        where
            (case when ']] .. search_params['name'] .. [[' <> '' then f.filename like '%]] .. search_params['name'] .. [[%' else true end)
            and (case when ']] .. search_params['agent_id'] .. [[' <> '' then f.agent_id like '%]] .. search_params['agent_id'] .. [[%' else true end)
            and (case when ']] .. search_params['action'] .. [[' <> '' then fa.action like '%]] .. search_params['action'] .. [[%' else true end)
            and (case when ']] .. search_params['status'] .. [[' <> '' then fa.result like '%]] .. search_params['status'] .. [[%' else true end)
        order by fa.time desc;
    ]]
end
