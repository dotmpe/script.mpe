#!/usr/bin/env bash

# Boilerplate env for CI scripts

test -z "${ci_env_:-}" && ci_env_=1 || exit 98 # Recursion

# FIXME: generate local static env
true "${BIN:="$HOME/bin"}"
test ! -e $HOME/.local/etc/profile.d/_local.sh || . $HOME/.local/etc/profile.d/_local.sh

: "${CS:="dark"}"
export CS
: "${CWD:="$PWD"}"
: "${LOG:="$CWD/tool/sh/log.sh"}"

sh_include env-strict debug-exit \
  env-0-1-lib-sys env-gnu

test -n "${U_S-}" || {
  $LOG "error" "" "Expected U-S env" "" 1 || return
}

ci_env_ts=$($gdate +"%s.%N")
ci_stages="${ci_stages:-} ci_env"

: "${SUITE:="CI"}"
: "${keep_going:=1}" # No-Sync

sh_env_ts=$($gdate +"%s.%N")
ci_stages="$ci_stages sh_env"

. "${CWD}/tool/sh/env.sh"

sh_env_end_ts=$($gdate +"%s.%N")

test -n "${ci_util_:-}" || {

  . "$U_S/tools/ci/util.sh"
}

: ${INIT_LOG:="$CWD/tool/sh/log.sh"}

test -n "${IS_BASH:-}" || $INIT_LOG error "Not OK" "Need to know shell dist" "" 1

# XXX: lib_load build-htd env-deps web # No-Sync

$INIT_LOG note "" "CI Env pre-load time: $(echo "$sh_env_ts - $ci_env_ts"|bc) seconds"
ci_env_end_ts=$($gdate +"%s.%N")

$INIT_LOG note "" "Sh Env load time: $(echo "$ci_env_end_ts - $ci_env_ts"|bc) seconds"
test -z "${CI:-}" || {
  test ${verbosity:-${v:-3}} -lt 4 ||
    print_yellow "ci:env:${SUITE}" "Starting: $0 ${_ENV-} #$#:'$*'" >&2
}
# Sync: U-S:
# Id: Script.mpe/0.0.4-dev tools/ci/env.sh
