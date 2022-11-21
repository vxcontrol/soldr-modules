#!/bin/bash

# Updates all libraries needed to run tests using busted&luajit

RELEASE=true

# List all additional libraries required for tests framework
LIBS=()

LIBS+=("BUSTED"); BUSTED_VERSION="2.1.1"
BUSTED_URL="https://github.com/lunarmodules/busted/archive/refs/tags/v$BUSTED_VERSION.tar.gz"
BUSTED_SHA256="5b75200fd6e1933a2233b94b4b0b56a2884bf547d526cceb24741738c0443b47"
BUSTED_LIST='$ARCHIVE_FOLDER/busted:$LUADIR/;$ARCHIVE_FOLDER/bin/busted:$LUADIR/bin;$WORKSPACE/busted.*:$LUADIR/bin'

LIBS+=("PENLIGHT"); PENLIGHT_VERSION="1.13.1"
PENLIGHT_URL="https://github.com/lunarmodules/Penlight/archive/refs/tags/$PENLIGHT_VERSION.tar.gz"
PENLIGHT_SHA256="530380e1a377df519c2e589f47823f79701f8e0e67f6bbd994e18d09a470b680"
PENLIGHT_LIST='$ARCHIVE_FOLDER/lua/pl:$LUADIR/'

LIBS+=("LUA_TERM"); LUA_TERM_VERSION="0.07"
LUA_TERM_URL="https://github.com/hoelzro/lua-term/archive/refs/tags/$LUA_TERM_VERSION.tar.gz"
LUA_TERM_SHA256="c1a1d0c57107147ea02878a50b768d1c3c13aca2769b026c5bb7a84119607f30"
LUA_TERM_LIST='$ARCHIVE_FOLDER/term:$LUADIR/;$WORKSPACE/term.core.lua:$LUADIR/term/core.lua'

LIBS+=("LUA_SYSTEM"); LUA_SYSTEM_VERSION="0.2.1"
LUA_SYSTEM_URL="https://github.com/o-lim/luasystem/archive/refs/tags/v$LUA_SYSTEM_VERSION.tar.gz"
LUA_SYSTEM_SHA256="0b83f68e9edbba92bef11ec0ccf1e5bb779a7337653f7bb77e0240c8e85c0b94"
LUA_SYSTEM_LIST='$ARCHIVE_FOLDER/system:$LUADIR/;$WORKSPACE/system.core.lua:$LUADIR/system/core.lua'

LIBS+=("LUA_MEDIATOR"); LUA_MEDIATOR_VERSION="1.1"
LUA_MEDIATOR_URL="https://github.com/Olivine-Labs/mediator_lua/archive/refs/tags/v$LUA_MEDIATOR_VERSION.tar.gz"
LUA_MEDIATOR_SHA256="0fe22369fcd124e9f2b0963968a5b098e9646544beb355238a591b2701fb367c"
LUA_MEDIATOR_LIST='$ARCHIVE_FOLDER/src/mediator.lua:$LUADIR/'

LIBS+=("LUA_CLIARGS"); LUA_CLIARGS_VERSION="3.0-2"
LUA_CLIARGS_URL="https://github.com/amireh/lua_cliargs/archive/refs/tags/v$LUA_CLIARGS_VERSION.tar.gz"
LUA_CLIARGS_SHA256="971d6f1440a55bdf9db581d4b2bcbf472a301d76f696a0d0ed9423957c7d176e"
LUA_CLIARGS_LIST='$ARCHIVE_FOLDER/src/*:$LUADIR/'

LIBS+=("LUASSERT"); LUASSERT_VERSION="1.9.0"
LUASSERT_URL="https://github.com/lunarmodules/luassert/archive/refs/tags/v$LUASSERT_VERSION.tar.gz"
LUASSERT_SHA256="1db0fabf1bd87392860375b89a8a37d17b687325c988be0df8c42e7e96e7ed73"
LUASSERT_LIST='$ARCHIVE_FOLDER/src/*:$LUADIR/luassert/'

LIBS+=("LUA_SAY"); LUA_SAY_VERSION="1.4.1"
LUA_SAY_URL="https://github.com/lunarmodules/say/archive/refs/tags/v$LUA_SAY_VERSION.tar.gz"
LUA_SAY_SHA256="ce07547ca49ef42cc799e2a30b3c65ce77039978e32e7961799a252d61a56486"
LUA_SAY_LIST='$ARCHIVE_FOLDER/src/say:$LUADIR/'

LIBS+=("LUA_COV"); LUA_COV_VERSION="0.15.0"
LUA_COV_URL="https://github.com/lunarmodules/luacov/archive/refs/tags/v$LUA_COV_VERSION.tar.gz"
LUA_COV_SHA256="19ebe0fdd5dd05ab63d5192371dcf272f2c7ccea5366e98fee440a2f30e021d8"
LUA_COV_LIST='$ARCHIVE_FOLDER/src/luacov:$LUADIR/;$ARCHIVE_FOLDER/src/bin/luacov:$LUADIR/bin/;$ARCHIVE_FOLDER/src/luacov.lua:$LUADIR/'

LIBS+=("LUACOV_COBERTURA"); LUACOV_COBERTURA_VERSION="1.1.0"
LUACOV_COBERTURA_URL="https://github.com/britzl/luacov-cobertura/archive/refs/tags/$LUACOV_COBERTURA_VERSION.tar.gz"
LUACOV_COBERTURA_SHA256="f525665be94b1dd7dc1c650d51ec2d4dad9e7a1e156bd555edb97348e633a9be"
LUACOV_COBERTURA_LIST='$ARCHIVE_FOLDER/luacov/*:$LUADIR/luacov/'

LIBS+=("DKJSON"); DKJSON_VERSION="2.6"; DKJSON_MODE="file"
DKJSON_URL="http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=6c6486a4a589ed9ae70654a2821e956650299228"
DKJSON_SHA256="bdb71dbe2863e9567d5a9a926faed1cfc4c12e04741a3e9009d334df25b9748c"
DKJSON_LIST='$TMPDIR/DKJSON-$DKJSON_VERSION.lua:$LUADIR/dkjson.lua'


# Evironment configuration

WORKSPACE="$(pwd)"
TMPDIR="$WORKSPACE/tmpdir"
LUADIR="$WORKSPACE/lua"

# Helper functions

function prepare_directory() {
    if [ -d $1 ]
    then
        $RELEASE && rm -rf $1/* && echo "Directory $1 cleaned"
    else
        mkdir $1 && echo "Directory $1 created"
    fi
}

ARCHIVE_FOLDER=""
function download_library() {
    name=$1
    version="$1_VERSION"; version="${!version}"
    url="$1_URL"; url="${!url}"
    list="$1_LIST"; list="${!list}"
    sha256="$1_SHA256"; sha256="${!sha256}"
    mode="$1_MODE"; mode="${!mode}"
    if [ -z $mode ]; then mode="archive"; fi
    if [[ "$mode" == "archive" ]];
    then
      download_name="$name-$version.tar.gz"
    else
      download_name="$name-$version.lua"
    fi
    # Download file if it is not present
    echo -n "Downloading $name $version..."
    [[ ! -f $download_name ]] && wget -q $url -O $download_name
    echo -e "\rDownloading $name $version, done $(ls -lah $download_name | awk -F " " {'print $5'})"
    # Validate downloaded file SHA256
    downloaded_sha256="$(sha256sum $download_name | cut -d ' ' -f1)"    
    if [[ "$sha256" != "$downloaded_sha256" ]]; then
        echo -e "\n\nExpected SHA256 hash $sha256 not equal to one from downloaded file: $downloaded_sha256"
        exit 1
    fi
    
    if [[ "$mode" == "archive" ]];
    then
        # Unarchive downloaded file
        tar -xf $download_name    
        ARCHIVE_FOLDER=`tar -tzf $download_name | head -1 | cut -f1 -d"/"`
        ARCHIVE_FOLDER="$TMPDIR/$ARCHIVE_FOLDER"
    fi

    # Copy all necessary files to destination
    export IFS=";"
    for pair in $list; do
        from=$(echo $pair | cut -f1 -d:); to=$(echo $pair | cut -f2 -d:)
        if [[ $to != *.lua ]]; then
            cmd="mkdir -p $to" && eval "$cmd"
        fi
        cmd="cp -rf $from $to" && eval "$cmd"
    done
}

# Preparing environment

prepare_directory "$TMPDIR"
prepare_directory "$LUADIR"

cd $TMPDIR

# Libraries fetch and strip
for value in "${LIBS[@]}"
do
    download_library "$value"
done