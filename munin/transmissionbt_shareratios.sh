#!/usr/bin/env bash

# Max torrent share ratio, mean, total cumulative and per-session share ratios
# XXX: might want share ratios per active torrent group, may be


report ()
{
  echo "max_shareratio.value $max_shareratio"
  echo "active_max_shareratio.value $active_max_shareratio"
  echo "active_avg_shareratio.value $active_avg_shareratio"
  echo "seeding_max_shareratio.value $seeding_max_shareratio"
  echo "seeding_avg_shareratio.value $seeding_avg_shareratio"
  echo "session_shareratio.value $session_shareratio"
  echo "total_shareratio.value $total_shareratio"
}

validate ()
{
  test $# -gt 0 || set -- \
      ${PLUGSTATE:?}/transmissionbt_shareratios.cache
  test -e "$1" || return 12

  list_validate < "$1" || {
      echo "# Problem with current $1 file"
      echo "# Problem with current $1 file" >&2
      test -e "$1.fail" || cp "$1" "$1.fail"
      return 99
  }
}

update ()
{
  test $# -gt 0 || set -- \
      ${PLUGSTATE:?}/transmissionbt_shareratios.cache

  transmission-remote -l | tbt_shares_colsfix >"$1" || return

  max_shareratio=$(list_all "$1" | max_shareratio)
  active_max_shareratio=$(list_active "$1" | max_shareratio)
  active_avg_shareratio=$(list_active "$1" | avg_shareratio)
  seeding_max_shareratio=$(list_seeding "$1" | max_shareratio)
  seeding_avg_shareratio=$(list_seeding "$1" | avg_shareratio)

  # XXX: hack to try to pin-down issues with generated data (incidental
  # ratios in 100s-1000s range)

  test ${max_shareratio/.*/} -gt 99 \
      -o ${active_max_shareratio//.*/} -gt 100 \
      -o ${active_avg_shareratio//.*/} -gt 100 \
      -o ${seeding_max_shareratio//.*/} -gt 100 \
      -o ${seeding_avg_shareratio//.*/} -gt 100 && {

      validate "$1" || return
  }

  eval "$(FMT=sh ${helper_py:?} --share-ratios)"

  report
}

load ()
{
  true "${US_BIN:=/srv/home-local/bin}"
  test -e "$MUNIN_LIBDIR/plugins/transmissionbt-munin.lib.sh" && {
      . "$MUNIN_LIBDIR/plugins/transmissionbt-munin.lib.sh" || return
  } ||
      . "$US_BIN/transmissionbt-munin.lib.sh"
}

true "${MUNIN_LIBDIR:=/usr/share/munin}"

# Location for state files.
# true "${MUNIN_PLUGSTATE:=/var/run/munin}"
true "${PLUGSTATE:=${MUNIN_PLUGSTATE:-/tmp}}"

set -euo pipefail

case ${1:-print} in

    ( autoconf ) echo "yes" ;;

    ( config ) cat <<EOM
graph_category p2p
graph_title BitTorrent Share Ratios
graph_info Upload vs. download data ratios
graph_vlabel ratio
max_shareratio.type GAUGE
max_shareratio.label Max. share ratio
active_max_shareratio.type GAUGE
active_max_shareratio.label Max. active share ratio
active_avg_shareratio.type GAUGE
active_avg_shareratio.label Avg. active share ratio
seeding_max_shareratio.type GAUGE
seeding_max_shareratio.label Max. seeding share ratio
seeding_avg_shareratio.type GAUGE
seeding_avg_shareratio.label Avg. seeding share ratio
session_shareratio.type GAUGE
session_shareratio.label Session share ratio
total_shareratio.type GAUGE
total_shareratio.label Cumulative share ratio
EOM
        ;;

    ( print | update ) load && assert_helper && assert_running || exit $?
        update ;;

    ( v | validate ) test $# -eq 0 || shift; load && validate "$@" ;;

esac

#
