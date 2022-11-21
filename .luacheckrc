
-- Get rid of "unused argument self"-warnings
self = false

-- The unit tests can use busted
files["**/*_spec.lua"].std = "+busted"
files["**/tests/*_spec.lua"].std = "+busted"

max_line_length=160
max_string_line_length=250
max_comment_line_length=320

exclude_files = {"tests_framework/*"}

read_globals = {
    -- table
    "table.unpack",

    -- package
    "package.searchers",

    -- assert
    "assert.is_true",
    "assert.is_false",

    -- yaci API
    "newclass",

    -- lightningmdb global object
    "lightningmdb",

    -- luajit API
    "newproxy",

    -- winapi module
    "winapi",

    -- command line arguments
    "arg",
}

globals = {
    "__api",
    "__imc",
    "__sec",
    "__agents",
    "__config",
    "__routes",
    "__args",
    "__tmpdir",

    -- agent or server version string
    "__version",

    -- agent ID (hash) string
    "__aid",
    -- group ID (hash) string
    "__gid",
    -- policy ID (hash) string
    "__pid",

    -- server connection properties
    "__sconn",

    -- logging global table
    "__log",
    -- monitoring global table
    "__metric",

    -- system variable
    "__files",

    -- mock variable to test modules
    "__mock",

    -- utils classes
    "CFileReader",
    "CReader",

    -- correlator classes
    "CEventEngine",
    "CActionEngine",
    "CCorrEngine",
    "CBaseEngine",

    -- uploader classes
    "CUploaderResp",

    -- wineventlog module aux class
    "CModule",
    "CWinEventLog",

    -- responder template classes
    "CActsEngine",

    -- YARA classes
    "CYaraModule",
    "CDatabaseEngine",

    -- lua 5.2 compat
    "bit",
    "loadstring",
    "setfenv",

    -- busted API
    "describe",
    "teardown",
    "setup",
    "it",
}

