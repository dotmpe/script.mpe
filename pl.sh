#!/usr/bin/env bash

### Playlist util


ranges ()
{
  test $# -gt 0 || set -- main
  readtab "$@" < "${1:?}.tab" | {
    declare st et p extra sts ets curp lets
    while IFS=$'\t\n' read -r st et p extra
    do
      test "${st:0:1}" = "#" && continue
      test "${st:?}" != "-" -a "${et:?}" != "-" || {
        $LOG debug :ranges "Unknown range" "$st $et $extra"
        continue
      }
      test "${curp:-}" = "$p" || {
        unset lets
        curp=$p
      }
      echo "$st $et $p $extra"
      sts=$(time2seconds "$(stdtime "$st")")
      test -n "${lets:-}" && {
        echo last end to start: $(echo "scale=1; $sts - $lets"|bc) seconds
      }
      ets=$(time2seconds "$(stdtime "$et")")
      echo start to end: $(echo "scale=1; $ets - $sts"|bc) seconds
      lets=$ets
    done
  }
}

# Read-tab wrapper to filter
filter () # ~ [<Tags <...>>]
{
  test $# -eq 0 || PL_TAGS=( "$@" )
  readtab "${PL_TAGS[@]:?}"
}

filtertab_if ()
{
  test -z "${PL_TAGS:-}" || {
    set -- ${PL_TAGS//:/ }
  }
  readtab "$@"
}

# Helper to
write () # ~ [<Tags <...>>]
{
  false
}

# Helper to (re)write output format if source tabfile (for basename) has changed.
# The basename.tab is looked up in PWD and PLTABSDIR. The given extension is
# used to determine the writer to use. Default is .vlc.m3u.
update () # ~ <Basename>.<Ext> [ <Alt-tabfile> [ <Alt-output> ]]
{
  # XXX: bd=$(dirname ${1:?})
  bn=$(basename ${1:?})
  shift

  test ${bn:0:2} != ./ || bn=${bn:2}
  ext=${bn#*.}
  bn=${bn%%.*}
  test "$bn" != "$ext" || ext=
  ext=${ext:-vlc.m3u}
  reader=$(printf '%s\n' ${ext//./ } | tac)
  reader=${reader//$'\n'/_}

  local tabdir pldir=${PLDIR:?}
  test -e "$bn.tab" && tabdir=$PWD || tabdir=${PLTABSDIR:?}

  test $# -eq 0 && {
    test -e $pldir/${bn:?}.${ext:?} \
      -a $pldir/${bn:?}.${ext:?} -nt $tabdir/${bn:?}.tab && {

      echo "File '${bn}.${ext}' is up to date with $bn.tab" >&2
    } || {
      echo "Writing '${bn}.${ext}' from $bn.tab (writepl_${reader//$'\n'/_})" >&2
      {
        {
          filtertab_if < $tabdir/${bn:?}.tab
        } | writepl_${reader} > $pldir/${bn:?}.${ext:?}
      } ||
          $LOG error :pl:update "Error (re)generating" "E$?" $? || return
    }
  } || {
    # XXX:
    {
      test "${1:-}" = "-" && {
        cat || $LOG error "" "" "E$?" $?
        exit $?
      } || {
        test -z "${1:-}" && {
          filtertab_if < $tabdir/${bn:?}.tab ||
            $LOG error "" "Reading tab" "E$?:$bn.tab" $?
          exit $?
        } || {
          filtertab_if < "${1}" || $LOG error "" "Reading tab" "E$?:$1" $?
          exit $?
        }
      }
    } | writepl_${reader} | {
      test "${2:-}" = "-" && {
        cat || $LOG error "" "" "E$?" $?
        exit $?
      } || {
        #test -z "${1:-}" && {
        cat >> "${2:?}"
      }
    }
  }
}


## User-script parts

pl_shortdescr='Media playlist utils'
pl_name=Playlists
pl_version=0.0.0-alpha
pl_maincmds="files globs"
#pl_defcmd=

pl_aliasargv ()
{
  case "$1" in
  esac
}

pl_loadenv ()
{
  : "${PLTABSDIR:=${METADIR:-.meta}/tab}"
  : "${PLDIR:=${METADIR:-.meta}/cache}"
  #shellcheck source=pl.lib.sh
  . ${US_BIN:?}/pl.lib.sh
}


# Main entry (see user-script.sh for boilerplate)

us-env -r us:boot.screnv &&

us-env -r user-script || ${us_stat:-exit} $?

! script_isrunning "pl" .sh || {
  user_script_load || exit $?
  # Pre-parse arguments
  user_script_defarg=defarg\ aliasargv
  eval "set -- $(user_script_defarg "$@")"
  script_run "$@"
}
#
