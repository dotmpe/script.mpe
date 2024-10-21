#!/usr/bin/env bash

date_load ()
{
  set -e
  . "${US_BIN:-"$HOME/bin"}"/date-htd.lib.sh
  test -z "${DEBUG:-}" || set -x
}


if [ "$(basename -- "$0")" == "date-util" ]
then
  date_load

  case "${1-}" in

    ( delta )
        [[ $# -gt 2 ]] || set -- "$1" "${2:?}" "$(date --iso=date)"
        stderr echo "From $2 to $3" &&
        ts1=$(date -d "${2:?}" '+%s') &&
        ts2=$(date -d "${3:?}" '+%s') &&
        ds=$(( ts2 - ts1 )) &&
        printf "%'d seconds\n" "$ds" &&
        ds=$(( ts2 - ts1 )) &&
        printf "%'d days\n" "$(( ds / 86400 ))" &&
        {
          [[ ${ds:0:1} = - ]] && o=1 pref= suf=" before" || o=0 pref= suf=" after"
        } &&
        if_ok "$(fmtdate_relative "" "${ds:$o}" "")" &&
        echo "$pref$_$suf" || return
      ;;

    ( ts-dt|timestamp-datetime ) shift;
        date -d @${1:?} ;;

    ( time-parse ) shift;
            time_parse_seconds "$1"
        ;;

    ( time-readable ) shift;
            echo "$1" | time_minsec_human_readable
        ;;
    ( time-readable-pl ) shift;
            time_minsec_human_readable
        ;;

    ( time-readable-tag ) shift;
            time_minsec_human_readable_tag "$1"
        ;;

    ( relative )  # ~ <Time> [<Delta>] [<suffix=' ago'>]
        # human readable relative time of period since or until given <Time>
        # from now.
        # <Time> is substracted from <Now> to produce <Delta> if not given
        shift;
        case "$2" in
            ( *"."* ) fmtdate_relative_f "$@" || return ;;
            ( * ) fmtdate_relative "$@" || return ;;
        esac;;

    ( relative-ts ) shift; case "$2" in
            ( *"."* ) fmtdate_relative_f "$@" || return ;;
            ( * ) fmtdate_relative "$@" || return ;;
        esac;;

    ( relative-ts-abbrev ) shift; { case "$2" in
            ( *"."* ) fmtdate_relative_f "$@" || return ;;
            ( * ) fmtdate_relative "$@" || return ;;
        esac
      } | time_fmt_abbrev || return;;

    #* ) echo "relative|relative-abbrev"; exit 1 ;;
    * ) exit 2 ;;

  esac

elif [ "$(basename -- "$0")" == "date.sh" ]
then
  date_load
  "$@"
fi
