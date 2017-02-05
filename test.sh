#!/bin/sh

set -e


scr_test_sh_main_load()
{
  __load_lib=1
  . $scriptdir/main.lib.sh load-ext
  . $scriptdir/util.sh load-ext
}

scr_test_sh_main()
{
  test -n "$scriptdir" || scriptdir="$(dirname $0)"
  scr_test_sh_main_load
  test -n "$1" || error arg 13
  util_init
  case "$1" in
    load-ext )
      ;;
    var-isset )
        var_isset "$2" && return || return $?
      ;;
    * )
        error "Missing/unknown '$1'." 12
      ;;
  esac
}


scr_test_sh_main "$@"

