#!/bin/sh
# Created: 2015-12-14
gv__source=$_


### Sub-commands


gv__edit()
{
  $EDITOR \
    $0 \
    ~/bin/graphviz.inc.sh \
    $(which graphviz.py) \
    "$@"
}

gv_run__bg=G
# Defer to python
gv__bg()
{
  test -n "$1" || set -- "bg"
  graphviz.py -f $graph --address $sock "$@" || return $?
}


gv_run__info=G #b
# Test argv
gv__info()
{
  gv__bg print-info
}


# ----


gv__usage()
{
  echo 'Usage: '
  echo "  $scriptname.sh <cmd> [<args>..]"
}

gv__help()
{
  gv__usage
  echo 'Functions: '
  echo ''
  echo '  help                             print this help listing.'
  std_help gv "$@"
}


# Pre-run: Initialize from argv/env to run subcmd
gv_init()
{
  local parse_all_argv= \
    scsep=__ \
    subcmd_pref=${scriptalias} \
    def_subcmd=status

  gv_preload || {
    error "preload" $?
  }

  gv_parse_argv "$@" || {
    error "parse-argv" $?
  }

  shift $c

  test -n "$subcmd_func" || {
    error "func required" $?
  }

  gv__lib "$@" || {
    error "lib error '$@'" $?
  }

  local tdy="$(try_value "${subcmd}" "" today)"

  test -z "$tdy" || {
    today=$(statusdir.sh file $tdy)
    tdate=$(date +%y%m%d0000)
    test -n "$tdate" || error "formatting date" 1
    touch -t $tdate $today
  }

  uname=$(uname)

  box_src_lib gv
}

# Init stage 1: Preload libraries
gv_preload()
{
  local __load_lib=1
  . ~/bin/std.sh
  . ~/bin/main.sh
  . ~/bin/util.sh
  . ~/bin/graphviz.inc.sh "$@"
  . ~/bin/os.lib.sh
  . ~/bin/date.lib.sh
  . ~/bin/match.sh load-ext
  . ~/bin/vc.sh load-ext
  test -n "$verbosity" || verbosity=6
  # -- gv box init sentinel --
}

# Pre-run stage 3: more libraries, possibly for subcmd.
gv__lib()
{
  local __load_lib=1
  . ~/bin/box.lib.sh
  # -- gv box lib sentinel --
}


### Main

gv__main()
{
  local scriptname=graphviz scriptalias=gv base=$(basename $gv__source .sh) \
    subcmd=$1

  case "$base" in

    $scriptname | $scriptalias )

        # invoke with function name first argument,
        local subcmd_func= c=0

        gv_init "$@" || {
          error "init error '$@'" 1
        }

        shift $c

        $subcmd_func "$@" || {
          gv__unload || error "unload on error failed: $?"
          error "exec error $subcmd_func" $?
        }

        gv__unload || {
          error "unload error" $?
        }

      ;;

    * )
      echo "Not a frontend for $base ($scriptname)"
      exit 1
      ;;

  esac
}

case "$0" in "" ) ;; "-*" ) ;; * )

  # Ignore 'load-ext' sub-command
  # XXX arguments to source are working on Darwin 10.8.5, not Linux?
  # fix using another mechanism:
  test -z "$__load_lib" || set -- "load-ext"
  case "$1" in load-ext ) ;; * )

      gv__main "$@"
    ;;

  esac ;;
esac


