#!/usr/bin/env bash

[[ ${SCRIPTNAME+set} ]] || {
  : "${0##*/}"; : "${_%.sh}"; SCRIPTNAME=$_
}
if [[ "${SCRIPTNAME?}" == "symlink-util" ]]
then
  set -euETo pipefail

  case "${1-}" in
  ( realtarget-cb )
      "${@:3}" "$(realpath "$(readlink "${2:?}")")"
    ;;

  ( sources ) # ~ ~ <Basedir> [<Dest-base...>]
      . ~/.l/c/System/OS/sources.inc &&
      group () { :; } &&
      os-sources "${@:2}"
    ;;

  ( target-cb )
      "${@:3}" "$(readlink "${2:?}")"
    ;;

  ( * ) exit 64 ;;

  esac

elif [[ "${SCRIPTNAME?}" == "file-util" ]]
then

  case "${1-}" in

  ( * ) exit 64 ;;

  esac

fi
