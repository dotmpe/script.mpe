#!/usr/bin/env bash


string_load ()
{
  set -e
  . "${US_BIN:-"$HOME/bin"}"/str-htd.lib.sh
  test -z "${DEBUG:-}" || set -x
}

# Bash stringtools
function rpad {
    if [ "$1" ]; then
        word="$1";
    else
        word="";
    fi;

    if [ "$2" ]; then
        len=$((`echo $2 | sed 's/[^0-9]//g'`));
    else
        len=${#word};
    fi;

    if [ "$3" ]; then
        padding="$3";
    else
        padding=" ";
    fi;

    while [ ${#word} -lt $len ]; do
        word="$word$padding";
    done;
    while [ ${#word} -gt $len ]; do
        word=${word:0:$((${#word}-1))}
    done;
    echo "$word";
}
function lpad {
    if [ "$1" ]; then
        word="$1";
    else
        word="";
    fi;

    if [ "$2" ]; then
        len=$((`echo $2 | sed 's/[^0-9]//g'`));
    else
        len=${#word};
    fi;

    if [ "$3" ]; then
        padding="$3";
    else
        padding=" ";
    fi;

    while [ ${#word} -lt $len ]; do
        word="$padding$word";
    done;
    while [ ${#word} -gt $len ]; do
        word=${word:1:$((${#word}-1))}
    done;
    echo "$word"
}
function cpad {
    if [ "$1" ]; then
        word="$1";
    else
        word="";
    fi;

    if [ "$2" ]; then
        len=$((`echo $2 | sed 's/[^0-9]//g'`));
    else
        len=${#word};
    fi;

    if [ "$3" ]; then
        padding="$3";
    else
        padding=" ";
    fi;

    while [ ${#word} -lt $len ]; do
        word="$word$padding";
        if [ ${#word} -lt $len ]; then
            word="$padding$word"
        fi;
    done;
    while [ ${#word} -gt $len ]; do
        word=${word:0:$((${#word}-1))}
        if [ ${#word} -gt $len ]; then
            word=${word:1:$((${#word}-1))}
        fi;
    done;

    echo "$word";
}



if [[ "${0##*/}" == "string-util" ]]
then

  case "${1-}" in
  ( if-pref | if-prefix )
      [[ "${2:?}" = "${3:0:${#2}}" ]]
    ;;

  ( * ) exit 64 ;;

  esac

elif [[ "${0##*/}" == "string" ]]
then
  string_load

  case "${1-}" in

    len ) str_len "$2" ;;
    tmux-len ) str_fmt=tmux str_len "$2" ;;

    sh-clean ) str_sh_clean "$2" ;;
    tmux-clean ) str_tmux_clean "$2" ;;

    str-padd-left ) str_sh_padd_ch "$2" "$3" "$4" ;;
    str-padd-right ) str_sh_padd_ch "$2" "" "$4" "$3" ;;
    tmux-str-padd-left ) str_tmux_padd_ch "$2" "$3" "$4" ;;
    tmux-str-padd-right ) str_tmux_padd_ch "$2" "" "$4" "$3" ;;

    append-if-len ) test -z "$2" || echo "$2$3" ;;
    prepend-if-len ) test -z "$2" || echo "$3$2" ;;

    * | "" ) exit 64 ;;

  esac

elif [ "$(basename -- "$0")" == "string.sh" ]
then
  string_load
  "$@"
fi
