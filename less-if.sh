#!/usr/bin/env bash

## Less-if: 'execute even less' pager, and make it pretty

# Listens to LINES and COLS, but also takes a threshold value from USER_LINES or
# UC_OUTPUT_LINES that sets the maximum number of lines to output to an
# interactive terminal inline. This is similar to less -F except the page size
# is configurable as it where. The main purpose is to get the pager UI out of
# the way when not needed. Secondary is making output pretty and formatted
# depending on the context (inline, or separate buffer UI process).

# All env:
# IF_PAGER <self>
# USER_LINES <int>
# UC_OUTPUT_LINES <int>
# IF_LANG <language> Language syntax name as recognized by batcat
# IF_PLAIN (0|1)
# IF_PAGE (0|1)

# Caveats:

# XXX: Paging for long or infinite streams is currently not practical.

# FIXME: cat does not really prevent clobbering from ANSI, may want to add
# filter (fancy=false?) or reset to TERM defaults? at EOF or even each line
# end, depending on the data that is dumped. etc.

# XXX: git delta does does not observe COL{S,UMNS},WIDTH, neither does e.g ``gh
# search repos`` so to prevent broken layout numbering needs to be turned off
# using IF_PLAIN


## Shell mode
set -euo pipefail

## Helpers

# Pass return status
if_ok () { return; }
# Match against glob
fnmatch () { case "${2:?}" in ${1:?} ) ;; * ) false; esac; }
# add terminal reset+EOL
cat_page_reset () { cat; echo "${NORMAL:-$(tput sgr0)}"; }
# add EOL and filter ANSI escape commands
# TODO: switch maybe to other pager format (raw, ansi, plain)
cat_page_plain () { pl_ansi_clean; echo; }
# Remove ANSI as best as possible in a single perl-regex
pl_ansi_clean ()
{
  perl -e '
while (<>) {
  s/ \e[ #%()*+\-.\/]. |
    \r | # Remove extra carriage returns also
    (?:\e\[|\x9b) [ -?]* [@-~] | # CSI ... Cmd
    (?:\e\]|\x9d) .*? (?:\e\\|[\a\x9c]) | # OSC ... (ST|BEL)
    (?:\e[P^_]|[\x90\x9e\x9f]) .*? (?:\e\\|\x9c) | # (DCS|PM|APC) ... ST
    \e.|[\x80-\x9f] //xg;
    1 while s/[^\b][\b]//g;  # remove all non-backspace followed by backspace
  print;
}'
}


## Script settings

: "${bat_exe:=bat}"

: "${DEBUG:=true}"

: "${PAGER_WRAPPERS:=delta,$bat_exe}"


# TODO: describe script main env
: "${PAGER_NORMAL:=}"
# The command for the actual pager
# that will deferred to (executed as a fork) at the end of the script.
: "${IF_PAGER:=}"


## Script init

$LOG info :less-if "Executing even less" "IF_PAGER=${IF_PAGER:-(unset)}"

if_ok "${PAGER_NORMAL:=$(command -v less) -R}" || {
  test -n "$IF_PAGER" ||
    $LOG error :init "Missing plain pager exec" "PAGER_NORMAL=less" 1 || return
}

# Check for batcat to use as fancy pager: frame decorations and highlighting
test -n "${IF_PAGER:-}" || {
  # Choose default (fancy) pager or normal
  if_ok "${IF_PAGER:=$(command -v $bat_exe)}" || {
    $LOG warn :init "Missing fancy pager exec" "IF_PAGER=$bat_exe"
    : "${IF_PAGER:=$PAGER_NORMAL}"
  }
}

# Look at parent command-name and prevent recursion
PCMD=$(ps -o comm= $PPID)
execn=${PCMD##*/}
test -n "$IF_PAGER" && {
  # Check that parent isnt already same command.
  : "${IF_PAGER##*/}"
  if_pager_name="${_%% -*}"
  test "$execn" != "$if_pager_name" || {
    fnmatch "* $if_pager_name *" " ${PAGER_WRAPPERS//[:,]/ } " && {
      IF_PAGER="$PAGER_NORMAL"
    } || {
      $LOG error : "Recursion?" "$if_pager_name:$PCMD"
      exit 1
    }
  }
} || {
  ! "${DEBUG:?}" || {
    # Check for every wrapper
    for wrapper in ${PAGER_WRAPPERS//[:,]/ }
    do
      test "$wrapper" != "$execn" && continue
      IF_PAGER="$PAGER_NORMAL"
      break
    done
  }
}

test -x "${IF_PAGER%% *}" && {
  $LOG debug :init "Selected pager" "IF_PAGER=$IF_PAGER"
} || {
  $LOG error :init "Missing pager exec" "IF_PAGER=${IF_PAGER:-(unset)}" $?
  exit 127
}


## Script start: prepare to start pager

# This is not set in non-interactive script ctx
true "${LINES:=$(tput lines)}"
true "${COLUMNS:=$(tput cols)}"

# XXX: removing 6 columns for bat line-numbers + frame works for LINES<=999
COLUMNS=$(( COLUMNS - 6 ))
export COLUMNS WIDTH=$COLUMNS

args=${1:-/dev/stdin}
test "$args" != "-" || args=/dev/stdin
test $# -eq 0 || shift
$LOG debug :start "Reading input data..." "args=$args"
data=$(<"$args")
test -z "$data" &&
    lines=0 ||
    lines=$(echo "$data" | wc -l)
$LOG info :start "Read input lines" "$lines:<$args"

# Set either USER_LINES or UC_OUTPUT_LINES in profile to page on more or less
# lines
maxlines=${USER_LINES:-${UC_OUTPUT_LINES:-${LINES:?}}}

# Now choose what to do based on particular IF_PAGER and user settings.

# Add default options pagers (if not already given)
case "${IF_PAGER##*/}" in

  ( "$bat_exe" )
      # XXX: IF_PAGE
      test 1 -eq "${IF_PLAIN:-0}" && {
        bat_opts=--style=plain

      } || {

        test $maxlines -le $lines && {
          test ${v:-${verbosity:-3}} -lt 6 ||
            echo "bat-if read $lines lines, max inline output is $maxlines" >&2
          bat_opts=--paging=always\ --style=rule,numbers
        } || {
          # Display 'File: ... <EMPTY>' (without deco) even if there is no content
          # but only if quiet_empty=false (see below)
          test $lines -eq 0 &&
              bat_opts=--paging=never\ --style=plain || {
              bat_opts=--paging=never\ --style=grid,numbers
            }
        }
      }

      # Display 'File:' header for both paging and nonpaging if known, but
      # only if quiet_empty=false
      { ${quiet_empty:-true} || test $lines -gt 0
      } && test "$args" = /dev/stdin ||
          bat_opts=$bat_opts,header\ --file-name="$args"

      test -z "${IF_LANG:-}" || bat_opts=$bat_opts\ -l\ $IF_LANG

      set -- $bat_opts

      test ${v:-${verbosity:-3}} -lt 6 ||
        echo "if-pager $bat_exe: setting options to $bat_opts" >&2
    ;;

  ( "less" )
      test 0 -eq $lines -o -z "$data" && exit 100
      test $maxlines -le $lines || IF_PAGER=cat_clean
      test ${v:-${verbosity:-3}} -lt 6 ||
        echo "if-pager less: switching to $IF_PAGER" >&2
    ;;

  ( * )
      test ${v:-${verbosity:-3}} -lt 6 ||
        echo "if-pager unknown or with arguments: ${IF_PAGER##*/}" >&2
    ;;
esac

# XXX: overrides?
case "${IF_PAGER##*/} " in
  ( "$bat_exe "* )
    ;;
esac

test ${v:-${verbosity:-3}} -lt 6 ||
  $LOG notice :exec "Starting pager pipeline" "$IF_PAGER:$#:$*"

printf '%s' "$data" | exec $IF_PAGER "$@"

# Id: script.mpe less-if [2023]
