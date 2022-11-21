#!/bin/sh
DIR=$(dirname -- "$( readlink -f -- "$0"; )")
exec "${LUA_BIN}" ${DIR}/busted.lua "$@"
