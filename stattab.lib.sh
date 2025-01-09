
# Status-Table-Id: stattab
# -Var: sttab/STTAB

# Autoselect main index and stattab index files. If missing, preset the values
# or run stattab__init manually.
stattab_lib__load ()
{
  lib_require statusdir || return
  : "${STTAB_FS:= }"
  : "${STTAB_STATC:="0-9^<>?!$$()&*+.,:~|-"}"
  : "${STTAB_EXTS:=.tab:.list}"
  local stdidx=${STIDX_NAME:-index.tab} stbtab=${STTAB_NAME:-stattab.list}
  # Index contains entries for all User ~/.statusdir/index/* files
  if_ok "${STIDX:=$(out_fmt= statusdir_lookup ${stdidx:?} index)}" &&
  # StatTab contains entries for all other local copies of User list/table
  # files under processing.
  if_ok "${STTAB:=$(out_fmt= statusdir_lookup ${stbtab:?} index)}" ||
    $LOG alert :stattab "Expected an existing main and stattab index" \
      "E$?:$stdidx:$stbtab" $?
}

# See that main and stattab index exists (and are not empty), and select
# whatever entry stab_id is set to as source to read records from.
stattab_lib__init ()
{
  test -z "${stattab_lib_init:-}" || return $_

  # TODO: Auto populate index if empty. XXX: may run updates later as well
  {
    test -s "${STIDX:?}" || stb_main=true stderr stattab__init
  } && {
    test -s "${STTAB:?}" || stderr stattab__init
  } && {

    # XXX:
    "${stb_main:-false}" && {
      stab_id=
    } || {
      stab_id=
    }
  }
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Loaded stattab.lib" "$(sys_debug_tag)"
}


# Initialize statusdir main index, and local table
stattab__init ()
{
  "${stb_main:-false}" && {
    test -e "${STIDX:?}" || {
      mkdir -p "$(dirname "$STIDX")" && touch "$STIDX" || return
    }
  } || {
    test -e "${STTAB:?}" || {
      mkdir -p "$(dirname "$STTAB")" && touch "$STTAB" || return
    }
  }
}

# Helper for data-list reader; split key from directive line name part, and
# and then value from line as well.
stattab_data_dirln () # (stbdr) ~
{
  test -z "$_rawline"  && return

  test "${_rawline:0:1}" != "#" || {

    test "${_rawline:1:1}" = ":" && {
      local dirkey value
      : "${_rawline:2}"
      dirkey=${_%: *}
      value=${_rawline:$(( 4 + ${#dirkey} ))}
      : "${dirkey%:}"
      : "${_//[^A-Za-z0-9_]/_}"
      declare -g $_="$value"
      return
    }
  }

  str_globmatch "${_rawline:0:1}" "[# $STTAB_FS]" ||
    return ${_E_continue:-195}
}

stattab_data_line () # (:stbdr) ~ <Data-handler> [<Args...>]
{
  stattab_data_line_split "$_rawline" || return

  # Process filter vars
  #test -n "${stb_dl_stat-}" && {
  #  str_wordmatch "${_-}" "$_stat" || return 0
  #} || {
  #  test -z "${stb_dl_fstat-}" || {
  #    str_wordmatch "${_-}" "$_stat" && return 0
  #  }
  #}
  #test -n "${stb_dl_data-}" && {
  #  str_wordmatch "${_-}" "$_data" || return 0
  #} || {
  #  test -z "${stb_dl_fdata-}" || {
  #    str_wordmatch "${_-}" "$_data" && return 0
  #  }
  #}
  #test -n "${stb_dl_rest-}" && {
  #  str_wordmatch "${_-}" "$_rest" || return 0
  #} || {
  #  test -z "${stb_dl_frest-}" || {
  #    str_wordmatch "${_-}" "$_rest" && return 0
  #  }
  #}

  ! "$_append" || set -- "$_data"

  ! "${VERBOSE:-false}" ||
  ! "${DEBUG:-false}" ||
    $LOG debug :stb:data-line "Running..." "cmd=$_cmd:$#:$*"
  stb_stat="$_stat" stb_data="$_data" stb_rest="$_rest" "$_cmd" "$@"
}

stattab_data_line_split () # (:data,stat,rest) ~ <Line>
{
  local sepc="${STTAB_FS:?}" prefc=${STTAB_STATC:?} data_rest

  # Strip stat characters prefixed to value
  str_globmatch "$1" "[$prefc$sepc]*" && {
    data_rest=$(str_globstripcl "$1" "[$prefc$sepc]") || return
    _stat=${1:0:$(( ${#1} - ${#data_rest} ))}
  } || {
    data_rest=$1
    _stat=
  }

  # Remove rest of fields
  #shellcheck disable=SC2295 # Expansions inside ${..}
  str_globmatch "$data_rest" "*:$sepc*" "*:"  && {
    _data=${data_rest%%:$sepc*}
    _rest=${data_rest:$(( 1 + ${#sepc} + ${#data} ))}
  } || {
    _data=${data_rest%%$sepc*}
    _rest=${data_rest:$(( ${#sepc} + ${#_data} ))}
  }
}

# Read stattab entries line by line, split stat and rest field groups from main
# value (ie. entry ID, key), and invoke handler command. This is intended as a
# simple runner to work with list data that can be easily upgraded to include
# stattab fields.
#
# Empty lines, comments and lines starting with whitespace are normally all
# ignored. Except '#' prefixed lines are passed to a handler for processing
# before.
stattab_data_list () # (stbdr:) ~ <Handler <args...>>
{
  local _cmd="${1:?Command name expected}" _append=false
  shift || return
  test 0 -lt $# || _append=true
  local cur_IFS=$IFS _{rawline,stat,data,rest} _ln=0
  for (( _ln=0; 1; _ln++ ))
  do
    IFS=$'\n'
    read -r _rawline || break
    IFS="$cur_IFS"

    "${stb_dld:-stattab_data_dirln}" && continue || {
      test "${_E_continue:-195}" = "$?" || return $_
    }

    "${stb_dli:-stattab_data_line}" "$@"
  done ||
    return
  $LOG notice : "Reading done" "lines:$_ln"
}

stattab_data_outline () # ~ <Handler <args...>>
{
  stb_dld=stattab_data_outline_dirln \
  stb_dli=stattab_data_outline_entry \
  stattab_data_list "$@"
}

stattab_data_outline_entry () # ~ <Handler <args...>>
{
  stattab_data_line || return

  stb_stat="${stb_statl:-}${stb_stat:-${stb_stat_default-}}${stb_statr:-}" \
  stb_rest="${stb_restl:-}${stb_rest:-${stb_rest_default-}}${stb_restr:-}" \
  "$@"
}

stattab_data_outline_dirln () # ~ <Handler <args...>>
{
  test -z "${rawline?}" && return

  test "${rawline:0:1}" != "#" || {
    test "${rawline:1:2}" = "-:" && {
      false
    }
    test "${rawline:1:2}" = "+:" && {
      false
    }
  }

  return ${_E_continue:-195}
}

# Output entry from current stab_* values
stattab_entry_fields() # ST-Id [Init-Tags]
{
  note "Init fields '$*'"
  test -n "$stab_id" || stattab_env_init "$1"
  test -z "$1" || shift

  # Output
  echo "$stab_id"
  test -z "$stab_short" || echo "$stab_short"
  echo "$stab_tags" | words_to_lines | remove_dupes
}


# Id: BIN:
