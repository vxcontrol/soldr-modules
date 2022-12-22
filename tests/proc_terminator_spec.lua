require 'busted.runner'()
---------------------------------------------------

local ffi     = require('ffi')
local lfs     = require('lfs')
local path    = require('path')
local cjson   = require("cjson.safe")
local strings = require('strings')
local process_api

---------------------------------------------------
-- helper functions
---------------------------------------------------

local test_process_name
local test_process_path
local test_process_args
local test_subprocess_name
local test_subprocess_path

local function get_luajit_path()
    local i_min = 0
    while (arg[i_min]) do i_min = i_min - 1 end
    return path.normalize(arg[i_min + 1], nil, {sep=true})
end

local function file_exists(p)
    local f = io.open(p, "r")
    if f == nil then
        return false
    end
    io.close(f)
    return true
end

local function copy_file(src, dst)
    local copy_bin = ffi.os == 'Windows' and 'copy' or 'cp'
    local cmd = ('%s "%s" "%s"'):format(copy_bin, src, dst)
    __log.debug(cmd)
    os.execute(cmd)
    assert(file_exists(dst), 'failed to copy luajit')
end

local function prepare_test_process_files()
    local ext = ffi.os == 'Windows' and '.exe' or ''
    local cwd = lfs.currentdir()..path.default_sep()
    local luajit_path = get_luajit_path()

    if (ffi.os == 'Windows') then
        local lua51dll = 'lua51.dll'
        local luajit_dir = path.dir(luajit_path)..path.default_sep()
        copy_file(luajit_dir..lua51dll, cwd..lua51dll)
    end

    test_process_name = "proc_terminator_test_process"..ext
    test_process_path = cwd..test_process_name
    copy_file(luajit_path, test_process_path)

    test_subprocess_name = "proc_terminator_test_subprocess"..ext
    test_subprocess_path = cwd..test_subprocess_name
    copy_file(luajit_path, test_subprocess_path)

    local test_process_script_name = "proc_terminator_start_subprocess.lua"
    local test_process_script_path = cwd..test_process_script_name
    os.remove(test_process_script_path)

    local script = assert(io.open(test_process_script_path, "w"), 'failed to create script-file for subprocess')
    local script_code = ("os.execute('%s -e \"while true do end\"')"):format(strings.escape_path(test_subprocess_path))
    script:write(script_code)
    script:close()

    test_process_args = ' '..test_process_script_path
end

local function sleep(sec)
    local socket = require("socket")
    socket.sleep(sec)
end

local function make_set(list)
    local set = {}
    for _, l in ipairs(list) do
        set[l] = true
    end
    return set
end

local function get_process_info(process_name)
    local result_info
    process_api.for_each_process(function(proc_info)
        if (proc_info.name == process_name) then
            result_info = proc_info
            return true -- stop iterations
        end
    end)
    return result_info
end

local function create_test_processes()
    local cmd = ('%s %s'):format(test_process_path, test_process_args)
    if (ffi.os ~= 'Windows') then
        cmd = cmd .. ' &'
    end

    __log.debug('Starting process: ' .. cmd)
    assert(io.popen(cmd), 'failed to start process')

    sleep(0.3)

    return get_process_info(test_process_name)
         , get_process_info(test_subprocess_name)
end

local function kill_test_processes()
    local names_set = make_set{test_subprocess_name, test_process_name}
    process_api.for_each_process(function(proc_info)
        if (names_set[proc_info.name]) then
            process_api.kill_process(proc_info.pid)
            return false
        end
    end)
end

---------------------------------------------------

---------------------------------------------------

describe('proc_terminator agent', function()
    local module_actions

    setup(function()
        _G.__mock = {
            vars = {},
            timeout = 2, -- in seconds
            cwd = "tmpcwd",
            module = "proc_terminator",
            version = "1.0.0",
            side = "agent", -- server
            log_level = os.getenv("LOG_LEVEL") or "debug", -- error, warn, info, debug, trace
            sec = {siem="{}", waf="{}", nad="{}", sandbox="{}"},
        }
        -- load mocked environment
        require("mock")

        -- wait until module initialization is finished
        assert.is_true(__mock:expect("event", function(o)
            return o.event.name == "pt_module_started"
        end), "pt_module_started event not arrived")

        process_api = require("process_api")
        module_actions = require("actions")

        prepare_test_process_files()
    end)

    teardown(function()
        if process_api then
            kill_test_processes()
        end

        -- stop module actually wait for module coroutine to finish execution
        __mock:module_stop()
        -- check last expected events
        assert.is_true(__mock:expect("event", function(o)
            return o.event and o.event.name == "pt_module_stopped"
        end))
    end)

    describe('process terminator', function()
        local src, dst = __mock.mock_token, __mock.module_token

        local function kill_process_test(kill_process_action)
            local object_type = select(3, kill_process_action:find("^pt_kill_(.-)_process"))
            local need_kill_subprocess = kill_process_action:match("_tree_") ~= nil
            assert.is_true(object_type ~= nil, "unsupported action")

            kill_test_processes()

            local process_info, subprocess_info = create_test_processes()
            assert(process_info ~= nil and process_info.name == test_process_name, "test process was not started")
            assert(subprocess_info ~= nil and subprocess_info.name == test_subprocess_name, "test subprocess was not started")

            local action_data = {}
            action_data[object_type..'.process.id'] = process_info.pid
            action_data[object_type..'.process.parent.id'] = process_info.parent_pid
            action_data[object_type..'.process.name'] = test_process_name
            action_data[object_type..'.process.fullpath'] = test_process_path
            action_data[object_type..'.fullpath'] = test_process_path
            local action_data_json = cjson.encode({data=action_data})

            local process_killed_successful_event = ("pt_%s_process_killed_successful"):format(object_type)

            -- ask module to kill the process
            assert(__mock:send_action(src, dst, action_data_json, kill_process_action), "failed to send kill process action")
            -- wait for expected result to arrive (in any order)
            assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == process_killed_successful_event end))
            assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == kill_process_action end))

            -- check that process was actually killed
            process_info = get_process_info(test_process_name)
            subprocess_info = get_process_info(test_subprocess_name)
            assert.is_true(process_info == nil, "test process was not terminated by a module")

            if (need_kill_subprocess) then
                assert(subprocess_info == nil, "test subprocess was not terminated by a tree-killing action")
            else
                assert(subprocess_info ~= nil, "test subprocess was terminated by a non-tree-killing action")
            end

            -- kill process manually
            if (process_info or subprocess_info) then
                kill_test_processes()
            end

            -- ask module to kill the process again
            assert(__mock:send_action(src, dst, action_data_json, kill_process_action), "failed to send kill process action")
            -- wait for expected result to arrive (in any order)
            assert.is_true(__mock:expect("event", function(o) return o.event and o.event.name == "pt_process_not_found" end))
            assert.is_true(__mock:expect("data", function(o) return o.data and o.data.name == kill_process_action end))
        end

        --[[ Kill object single process ]]

        it('should kill object process by file path', function()
            kill_process_test(module_actions.pt_kill_object_process_by_file_path)
        end)

        it('should kill object process by name', function()
            kill_process_test(module_actions.pt_kill_object_process_by_name)
        end)

        it('should kill object process by name and pid', function()
            kill_process_test(module_actions.pt_kill_object_process_by_name_and_id)
        end)

        it('should kill object process by image', function()
            kill_process_test(module_actions.pt_kill_object_process_by_image)
        end)

        it('should kill object process by image and pid', function()
            kill_process_test(module_actions.pt_kill_object_process_by_image_and_id)
        end)

        --[[ Kill object process tree ]]

        it('should kill object process tree by file path', function()
            kill_process_test(module_actions.pt_kill_object_process_tree_by_file_path)
        end)

        it('should kill object process tree by name', function()
            kill_process_test(module_actions.pt_kill_object_process_tree_by_name)
        end)

        it('should kill object process tree by name and pid', function()
            kill_process_test(module_actions.pt_kill_object_process_tree_by_name_and_id)
        end)

        it('should kill object process tree by image', function()
            kill_process_test(module_actions.pt_kill_object_process_tree_by_image)
        end)

        it('should kill object process tree by image and pid', function()
            kill_process_test(module_actions.pt_kill_object_process_tree_by_image_and_id)
        end)

        --[[ Kill subject single process ]]

        it('should kill subject process by name', function()
            kill_process_test(module_actions.pt_kill_subject_process_by_name)
        end)

        it('should kill subject process by name and pid', function()
            kill_process_test(module_actions.pt_kill_subject_process_by_name_and_id)
        end)

        it('should kill subject process by image', function()
            kill_process_test(module_actions.pt_kill_subject_process_by_image)
        end)

        it('should kill subject process by image and pid', function()
            kill_process_test(module_actions.pt_kill_subject_process_by_image_and_id)
        end)

        --[[ Kill subject process tree ]]

        it('should kill subject process tree by name', function()
            kill_process_test(module_actions.pt_kill_subject_process_tree_by_name)
        end)

        it('should kill subject process tree by name and pid', function()
            kill_process_test(module_actions.pt_kill_subject_process_tree_by_name_and_id)
        end)

        it('should kill subject process tree by image', function()
            kill_process_test(module_actions.pt_kill_subject_process_tree_by_image)
        end)

        it('should kill subject process tree by image and pid', function()
            kill_process_test(module_actions.pt_kill_subject_process_tree_by_image_and_id)
        end)
    end)
end)
