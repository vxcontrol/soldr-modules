#!/bin/sh

function abspath() {
  pushd . > /dev/null;
  if [ -d "$1" ]; then
    cd "$1";
    dirs -l +0;
  else
    cd "`dirname \"$1\"`";
    cur_dir=`dirs -l +0`;
    if [ "$cur_dir" == "/" ]; then
      echo "$cur_dir`basename \"$1\"`";
    else
      echo "$cur_dir/`basename \"$1\"`";
    fi;
  fi;
  popd > /dev/null;
}

DIR=$(dirname -- "$( abspath "$0"; )")
exec "${LUA_BIN}" ${DIR}/busted.lua "$@"
