#!/usr/bin/env bash

## Main source to bootstrap User-Script executables

# Custom scripts can provide <baseid>-*=<custom value> to use local values
user_script_name="User-script"
user_script_version=0.0.2-dev

# The short help only lists main commands
user_script_maincmds="help long-help aliases commands variables version"

# The short help starts with a short usage description.
user_script_shortdescr='This is a boilerplate and library to write executable shell scripts.
See help and specifically help user-script for more info'

# TODO: The long per-sub-command help
#shellcheck disable=2016
user_script_extusage='Custom scripts only need to know where to find
user-script.sh. I'"'"'ll include the current minimal boilerplate here to
illustrate:

    test -n "${user_script_loaded:-}" ||
        . "${US_BIN:="$HOME/bin"}"/user-script.sh
    script_entry "my.sh" "$@"

This would make your (executable) script run at script-entry, if invoked as
`my.sh` (or when included in a script invoked as such). But not when called or
sourced otherwise. Basically only if SCRIPTNAME == entry-argument.

Generic env settings:
    DEBUG - To enable some bash-specific trace/debug shell settings.
    DEBUGSH - To enable verbose execution (aka sh -x, xtrace; to stderr)
    BASH_VERSION - Used to enable bash-specific runtime options
    quiet - Used to make user-script stop commenting on anything

# Entry sequence
Before entry, user-script-shell-env can be executed to get access at other
functions in the pre-entry stage, such as pre-processing arguments (w. defarg)

Without defarg, there are only one or two more env settings at this point:
    SCRIPT_BASEEXT - Set to strip ".ext" from name
    SCRIPTNAME - Should be no need to set this

At script-entry first the SCRIPTNAME is set and checked with first argument.
user-script-shell-env then gets to run again (if needed), but it only does
some basics for generic user-script things like the help function and
the simple argument pre processing.

- set some environment vars (calling user-script-loadenv)
- load some libraries (basic dependencies for user-script)
- and do some shell specific setups (using shell.lib).

Then script-doenv is called, to do find the handler function and to do further
preparations.
This runs the <baseid>-loadenv hook so custom scripts can do their own stuff.

At that point these variables are provided:
    base{,id} - Same as SCRIPTNAME, and an ID created from that
    script-cmd{,id,alsid} - The first argument, and an ID created from that.
        And also from an alias if set (see defarg)

After do-env it is expected that "$1" equals the name of a shell function, if
not then "usage" (fail) is invoked instead.
do-env can not change arguments,
either the handler does further argv processing or defarg takes care of it.

script-doenv is paired with a script-unenv, called after the command.
Both are short steps:

- doenv sets base and baseid,
  calls script-cmdid to set vars,
  and then <baseid>_loadenv

- unenv calls <baseid>_unload,
  and then undoes every of its own settings and unsets vars

During unenv, script-cmdstat holds the return status.

Some of these things may need to be turned into hooks as well.


# Hooks
The current hooks mainly revolve around command alias functionality.

defarg
    Process arguments and print new argument line followed by (global) env
    to set before entering script.

    To help user-script-aliases find case/esac items set script-extra-defarg.

    Custom scripts may not want to take on the defarg boilerplate however,
    processing argv is a bit tricky since we use the dump-eval steps,
    and extracting aliases requires the case/esac in-line in the function body.

    Instead user-script-defarg can pick up one script-fun-xtra-defarg,
    which it includes in-line (evals function body).


NOTE: I use user-script-shell-env and user-script-defarg for almost all scripts,
focus is on good online help functions still. And using code/comments to
provide needed data instead of having to give additional variables.

TODO: fix help usage/maincmd so each gives proper info. Some tings mixed up now
'

user_script__libs=user-script

user_script_sh__grp=user-script


# Execute when script is sourced, when given base matches SCRIPTNAME.
# If the handlers prefixes don't match the exec name, use
# base var to change that.
script_entry () # [script{name,_baseext},base] ~ <Scriptname> <Action-arg...>
{
  local SCRIPTNAME=${SCRIPTNAME:-}
  script_name || return
  if [[ $SCRIPTNAME = "$1" ]]
  then
    shift
    script_run "$@" || return
  else
    ! sys_debug ||
      $LOG info :script-entry "Skipped non-matching command" "$1<>$SCRIPTNAME"
  fi
}

script_envinit () # ~ <Bases...>
{
  # TODO: transpile and source us-env functions
  add_path "${U_S?}/tool/us/part" &&
  uc_script_load "-us-env.base" &&
  # XXX: start us-env
  us_env_declare &&
  us_env_load "${1:?}"

  std_silent declare -p ENVD_FUN || declare -gA ENVD_FUN=()
  std_silent declare -p us_node || declare -gA us_node=()
  std_silent declare -p us_node_base || declare -gA us_node_base=()
  std_silent declare -p us_node_hooks || declare -gA us_node_hooks=()
  std_silent declare -p us_node_libs || declare -gA us_node_libs=()

  #sys_default "us_node_base['user-script']" &&
  user_script_graph_init "$@" &&
  script_baseenv
}

# Setup env to start loading user-script(s) and parts. To prepare env for
# commands, see loadenv handlers.
#
script_baseenv ()
{
  local script_bases=${script_base//,/ } script_base{,id}

  for script_base in ${script_bases:?}
  do
    #: "${script_baseid:=$(str_id "${script_base%[, ]*}")}"
    script_baseid=$(str_word "${script_base:?}")

    # Get initial instance vars, using initial base.
    # Including override value for base, if such is ever needed or useful.
    local var{,_}
    for var in base defcmd name version shortdescr
    do
      var_=${script_baseid:?"$(sys_exc us:script-baseenv:scriptid)"}_$var
      test -z "${!var_:-}" || eval "script_$var=\"${!var_}\""
    done
  done
  : "${script_name:="$user_script_name:$SCRIPTNAME"}"
  : "${script_shortdescr:="User-script '$script_name' has no description. "}"

  # Get inherited vars
  local _baseid
  for var in maincmds
  do
    for _baseid in $(user_script_baseids)
    do
      var_=${_baseid}_$var;
      test -n "${!var_:-}" || continue
      eval "script_$var=\"${_//,/ }\""
      continue 2
    done
  done

  : "${SCRIPTNAME:?"$(sys_exc script-loadenv:SCRIPTNAME)"}"
  local SCRIPTNAME_ext=${SCRIPT_BASEEXT:-}
  : "${script_src:="$SCRIPTNAME$SCRIPTNAME_ext"}"
  test "$script_src" = user-script.sh || script_src="$script_src user-script.sh"
  # TODO: write us_load function ${script_lib:=user-script.lib.sh}
  script_lib=
}

script_cmdid ()
{
  script_cmd="${1:?}"
  script_cmdname="${script_cmd##*/}"
  script_cmdname="${script_cmdname%% *}"
  script_cmdid=$(str_word "$script_cmd")
  test -z "${script_cmdals:-}" || {
      script_cmdalsid=$(str_word "$script_cmdals")
    }
}

script_debug_args () # ~ <Args> # Pretty-print arguments
{
  test 0 -lt $# || return ${_E_MA:?}
  local arg i=1
  for arg in "$@"
  do
    echo "$i: $arg"
    i=$(( i + 1 ))
  done
}

# Turn declaration into pretty print using sed
script_debug_arr () # ~ <Array-var> # Pretty-print array
{
  test 1 -eq $# || return ${_E_MA:?}
  if_ok "$(declare -p ${1:?})" &&
    fnmatch "declare -*[Aa]* ${1:?}" "$_" &&
      echo "Array '${_:11}' (empty)" ||
      <<< "Array '${_:11}" sed "s/=(\[/':\\n\\t/
s/\" \[/\\n\\t/g
s/]=\\\$/\\t\$/g
s/]=\"/\\t/g
s/\" *)//g
"
}

script_debug_arrs ()
{
  test 0 -lt $# || return ${_E_MA:?}
  while test 0 -lt $#
  do script_debug_arr "${1:?}" || return
    shift
  done
}

script_debug_class_arr () # ~ <key> [<Class>] # Pretty print Class array
{
  test 0 -lt $# -a 2 -ge $# || return ${_E_MA:?}
  script_debug_arr "${2:-Class}__${1:?}"
}

script_debug_env () # ~ [<Names...>]
{
  : about "Describe variables/functions in env"
  : about "Without arguments sets preselect set (and also shows us:bases)"
  : notes "See script-debug-{p,g}env to match specific env names"
  : param "[<Names...>]"
  [[ $# -gt 0 ]] || {
    set -- \
      script_{base{,id},cmd{name,fun},defcmd,defarg,maincmds,name,version,src,lib} \
      user_script_defarg \
      ENV_{SRC,LIB} \
      us_node{,_base}
    stderr echo Bases: $(user_script_bases)
  }
  #stderr echo Bases rev: $(user_script_bases | tac)
  [[ $# -gt 0 ]] || return ${_E_MA:?}
  : "$(for a; do sh_var "$a" && echo "$a"; done)"
  test -z "$_" || script_debug_vars $_
  : "$(for a; do sh_arr "$a" && echo "$a"; done)"
  test -z "$_" || script_debug_arrs $_
  : "$(for a; do sh_fun "$a" && echo "$a"; done)"
  test -z "$_" || us_debug_fullfun=false script_debug_funs $_
}

script_debug_frame () # ~ # Print stacktrace using FUNCNAME/caller
{
  : "${#FUNCNAME[@]}"
  test 0 -lt $_ || return
  local framec=$_
  stderr echo "Call#: $framec"
  stderr echo "Argv/argc#: ${#BASH_ARGV[@]} ${#BASH_ARGC[@]}"
  #stderr echo "Sources/lines: ${#BASH_SOURCE[@]} ${#BASH_LINENO[@]}"
  local frame_skip=${1:-1} info
  framec=$(( framec - 2 ))
  while info=( $(caller $framec) )
  do
    stderr echo "$framec. ${info[1]}: ${FUNCNAME[$framec]} <${info[2]}:${info[0]}>"
    framec=$(( framec - 1 ))
    test $framec -ge $frame_skip || break
  done
}

script_debug_funs () # ~ <Fun...> # List shell functions
{
  shopt -s extdebug
  local fun
  echo "# Functions ($#):"
  for fun
  do
    if_ok "$(declare -F $fun)" &&
    echo "# $_" &&
    "${us_debug_fullfun:-true}" || continue
    declare -f $fun
  done
}

script_debug_penv () # ~ <Name-prefixes ...>
{
  : param '<Name-prefixes ...>'
  # Hide status
  set -- $( for pref
    do compgen -A variable $pref
    done) \
    $( for pref
    do compgen -A arrayvar $pref
    done) \
    $( for pref
    do compgen -A function $pref
    done)
  [[ $# -gt 0 ]] || return ${_E_MA:?}
  script_debug_env $*
}

script_debug_genv () # ~ <Name-grep-args ...>
{
  : param '<Var-name-grep-args ...>'
  # Hide status
  set -- $(compgen -A variable | grep "${@:?}") \
    $(compgen -A arrayvar | grep "${@:?}") \
    $(compgen -A function | grep "${@:?}")
  [[ $# -gt 0 ]] || return ${_E_MA:?}
  script_debug_env $*
}

script_debug_libs () # ~ # List shell libraries loaded and load/init states
{
  echo "lib_loaded: $lib_loaded"
  if_ok "
$( lib_uc_hook pairs _lib_load | sort | sed 's/^/   /' )
lib_init:
$( lib_uc_hook pairs _lib_init | sort | sed 's/^/   /' )
" &&
  stderr echo "$_"
}

script_debug_vars () # ~ <Var-names...> # Print simple list of assignments
{
  : "${def_stat:=-}"
  : "${def_val:=(unset)}"

  # NOTE: for ref-vars (-n), using '${!...}' flips its function
  declare -n vn
  : "$(for vn in "$@"
  do
    : "${vn-$def_val}"
    printf "%s=%s\n" "${!vn}" "$_"
  done)"
  stderr echo "$_"
}

# Handle env setup (vars & sources) for script-entry.
# Executes first existing
# loadenv hook, unless it returns status E:not-found then it continues on to
# the next doenv hook on script-bases.
script_doenv () # ~ <Action <argv...>>
{
  [[ ${script_base-} ]] ||
    script_envinit ||
    $LOG error "" "During script env init" "E$?:$*" $? || return

  # Update bases, if there is one given for particular action, on any of the
  # current bases.
  ! "${user_script_baseless:-false}" && : "" || : "${1:?} "
  if_ok "$_$(for base in $(user_script_bases)
    do
      echo "$base-${1:?}"
    done)" &&
  sys_loop user_script_cmdhandler_set $_ &&
  script_baseenv ||
    $LOG error "" "During base env" "E$?" $? || return
  #stderr declare -p DEV DEBUG DIAG INIT ASSERT QUIET VERBOSE
  test -n "${script_cmdfun-}" &&
    $LOG info "" "Found command handler" "$script_cmdfun" ||
    $LOG warn"" "No command handler found" "$1"
  ! "${DEBUG:-false}" || script_debug_env

  local _baseid stat fail
  # Run all loadenv hooks, going top-down from base to groups
  for _baseid in $(user_script_baseids | tac)
  do
    ! sh_fun "$_baseid"_loadenv || {
      local -n env_status=${_baseid}_env
      ! sys_debug || $LOG debug "" "Loadenv" "$_baseid"
      "$_baseid"_loadenv "$@"
      # XXX: maybe...
      test ${_E_not_found:-124} -eq $? ||
      test 0 -eq $_ || {
        env_status=$_
        test ${_E_done:-200} -eq $env_status && fail=false
        test ${_E_break:-197} -eq $env_status && interrupt=true
        test ${_E_continue:-195} -eq $env_status || {
          test ${_E_next:-196} -eq $env_status && fail=true || {

            $LOG error "" "During loadenv" "E$_:$_baseid" $_ ||
              return
          }
        }
      }
      ! sys_debug +debug +init ||
        $LOG info "" "Finished 'loadenv' on base '$_baseid'" \
              "${env_status+"S$env_status"}"
      "${interrupt-false}" && return ${_E_int:-131}
      ! "${fail-false}" || return
    }
  done

  shift ${scriptenv_argc:?}

  script_cmdid "${1:?}" ||
    $LOG error "" "Command ID" "E$?:$1" $? || return
  : "${script_cmdfun:=${script_cmdname//-/_}}"

  # prefer to use most specific name, fallback to unprefixed handler function
  #! sh_fun "${baseid}_${script_cmdfun}" || script_cmdfun="$_"

  sh_fun "$script_cmdfun" && {
    ! sys_debug +diag +init ||
      $LOG info "" "Script command handler ready" "$script_cmdname"
  } || {
    $LOG error "" "No such function" "$script_cmdfun"
    set -- $SCRIPTNAME usage -- "$script_cmd" "$@"
    user_script_load "$@" || return
    script_cmdfun=user_script_usage
  }
}

script_edit () # ~ # Invoke $EDITOR on script source(s)
{
  #test $# -gt 0 || set -- $script_src $script_lib
  "$EDITOR" "$0" "$@"
}

# Check if given argument equals zeroth argument.
# Unlike when calling script-name, this will not pollute the environment.
script_isrunning () # [SCRIPTNAME] ~ <Scriptname> [<Name-ext>]# argument matches zeroth argument
{
  [[ $# -ge 1 && $# -le 2 ]] || return ${_E_GAE:-3}
  [[ ${SCRIPTNAME:+set} ]] && {
    [[ $SCRIPTNAME = "$1" ]]
    return
  }
  [[ $# -eq 2 ]] && SCRIPT_BASEEXT="${2:?}"
  script_name &&
  [[ "${SCRIPTNAME:?Expected SCRIPTNAME after script_name}" = "$1" ]] || {
    [[ $# -lt 2 ]] || unset SCRIPT_BASEEXT
    unset SCRIPTNAME
    return 1
  }
}

script_name () # ~ <Command-name> # Set SCRIPTNAME env based on current $0
{
  : "${SCRIPTNAME:="$(basename -- "$0" ${SCRIPT_BASEEXT:-})"}"
}

script_run () # ~ <Action <argv...>>
{
  local extlogbase=${UC_LOG_BASE-}${UC_LOG_BASE+/}
  export UC_LOG_BASE=${extlogbase}${script_name:?}"[$$]":doenv
  local scriptenv_argc=0
  script_doenv "$@" ||
    $LOG warn :/script-run "Script setup failed" "E$?:$#:$*" $? || return
  ! uc_debug ||
      $LOG info :/script-run "Entering user-script $(script_version)" \
          "cmd:$script_cmd:als:${script_cmdals-(unset)}"
  incr scriptenv_argc
  shift ${scriptenv_argc:?}
  ! uc_debug ||
      $LOG info :/script-run "Running main handler" "fun:$script_cmdfun:$*"
  export UC_LOG_BASE=${extlogbase}$script_name"[$$]":${script_cmdals:-${script_cmdname:?}}
  "$script_cmdfun" "$@" || script_cmdstat=$?
  export UC_LOG_BASE=${extlogbase}$script_name"[$$]":unenv
  script_unenv || return
  export UC_LOG_BASE=${extlogbase}
}

# Undo env setup for script-entry. Almost the inverse of script-doenv, except
# this doesnt get any arguments (to process argv or an action argument) as the
# enitre env has been established.
script_unenv () # ~
{
  local _baseid stat
  for _baseid in $(user_script_baseids)
  do
    ! sh_fun "$_baseid"_unload || {
      ! sys_debug || $LOG info "" "Loadenv" "$_baseid"
      "$_baseid"_unload "$@" || {
        test ${_E_not_found:?} -eq $? && continue ||
        test ${_E_next:-196} -eq $_ && continue ||
          $LOG error "" "During unload" "E$_:$_baseid" $_ ||
            return
      }
    }
  done

  local cmdstat=${script_cmdstat:-0}

  unset script{name,_{baseext,cmd{als,def,id,alsid,stat},defcmd}} base{,id}

  # FIXME: switch using sh-mode helper
  set +e
  # XXX: test "$IS_BASH" = 1 -a "$IS_BASH_SH" != 1 && set +uo pipefail
  test -z "${BASH_VERSION:-}" || set +uo pipefail
  test -z "${DEBUGSH:-}" || set +x

  ! sys_debug +debug +diag +init || {
    sys_debug assert && {
      #[[ ${cmdstat:?} -eq 0 ]] &&
      #  $LOG info :unenv "Cleanup OK after" "$base:$script_cmdname" ||
      $LOG info "" "Cleanup OK after" "$base:$script_cmdname"
    } ||
      $LOG debug "" "Unloaded env"
  }
  return ${cmdstat:?}
  #test 0 -eq "$cmdstat" && return
  #case "$cmdstat" in
  #  ( ${_E_fail:?} | ${_E_syntax:?} | ${_E_todo:?}
  #return ${_E_error:?}
}


## U-s functions

# XXX: Helper to select/invoke next handler specific to current context and
# inputs.
user_script_ () # ~ <Hook-name> [<Hook-args...>]
{
  : "${base:=${SCRIPTNAME:?}}"
  : "${baseid:=$(str_word "${base:?}")}"
  sh_fun ${baseid}_${1//-/_} || : user_script_${1//-/_}
  "$_" "${@:2}"
}

user_script_aliases () # ~ [<Name-globs...>] # List handlers with aliases
{
  # Match given function name globs, or set fairly liberal regex
  test $# -eq 0 && {
    set -- "[A-Za-z_:-][A-Za-z0-9_:-]*"
  } || {
    set -- "$(grep_or "$*")"
  }

  local bid fun vid
  user_script_aliases_raw | grep "\<$1\> .*)" | {

    # Handle output formatting
    test -n "${u_s_env_fmt:-}" || {
      test ! -t 1 || u_s_env_fmt=pretty
    }
    case "${u_s_env_fmt:-plain}" in
        ( pretty ) grep -v '^#' | sort | column -s ':' -t ;;
        ( plain ) cat ;;
    esac
  }
}

user_script_aliases_raw ()
{
  for bid in $(user_script_baseids)
  do
    for h in ${user_script_defarg:-defarg}
    do
      sh_fun "${bid}_$h" && fun=${bid}_$h || {
        sh_fun "$h" && fun=$h || continue
      }
      echo "# $fun"
      case "${out_fmt:-}" in
      ( raw )
          sh_type_esacs_als $fun
        ;;

      ( * )
          sh_type_esacs_als $fun | sed '
                  s/ set -- \([^ ]*\) .*$/ set -- \1/g
                  s/ *) .* set -- /: /g
                  s/^ *//g
                  s/ *| */, /g
                  s/"//g
              '
        ;;
      esac
    done
  done
}

# List script node words, going from specific base or group to all containers
user_script_baseids () # ~ [script-node-base] ~ <keys...>
{
  local base
  if_ok "$(user_script_bases "$@")" &&
  for base in $_
  do
    str_word "$base"
  done
}

# List script node ids, going from specific base or group to all containers
user_script_bases () # ~ [script-node-base] ~ <keys...>
{
  local bases
  [[ $# -gt 0 ]] || {
    : ${script_base:?"$(sys_exc user-script:bases:start)"}
    set -- ${_//,/ }
  }
  local -A _bases
  while test $# -gt 0
  do
    [[ ${_bases["$1"]+set} ]] && shift && continue
    _bases["$1"]=
    echo "${1:?}"
    [[ ! ${us_node_base["$1"]-} ]] && shift && continue
    bases=${us_node_base["$1"]?}
    set -- $bases "${@:2}"
  done
}

user_script_cmdhandler_set () # ~ <Node>
{
  sh_fun "${1//[:.-]/_}" && {
    script_cmdfun=$_
    script_cmdname=$1
    #ENVD_FUN["$1"]=$script_cmdfun
    return
  }
  return ${_E_continue:-195}
}

# TODO: commands differs from handlers in that it lists maincmds and aliases
user_script_commands () # ~ # Resolve aliases and list command handlers
{
  # FIXME: maincmds list are not functions, use aliases to resolve handler names
  test $# -gt 0 || set -- $script_maincmds
  user_script_resolve_aliases ||
      $LOG error :commands "Resolving aliases" "E$?:$*" $? || return
  user_script_handlers "$@" ||
      $LOG error :commands "Resolving handlers" "E$?:$*" $?
}

# Output argv line after doing 'default' stuff. Because these script snippets
# have to change the argv of the function, it is not possible to move them to
# subroutines hence they are copy-pasted and evaluated in-line. The defarg
# phase should process (initial) arguments (and flags, options) and may prepare
# some initial environment needed before invoking script-run or script-entry.
user_script_defarg ()
{
  #local rawcmd="${1:-}"

  declare -A script_defenv

  # Track default command, and allow it to be an alias
  [[ $# -gt 0 ]] || {
    set -- "${script_defcmd:="usage"}"
    script_defenv[script_defcmd]=${script_defcmd:?}
  }

  # Hook-in more for current user-script or other bases
  # Script needs to be sourced or inlined from file to be able to modify
  # current arguments.
  local bid fun xtra_defarg
  for bid in $(user_script_baseids)
  do
    for h in ${user_script_defarg:-defarg}
    do
      sh_fun "${bid}_${h}" || {
        continue
      }
      # Be careful not to recurse to current function
      test "$h" != defarg -o "$bid" != user_script || continue
      eval "$(sh_type_fun_body $bid"_"$h)" || return
    done
  done

  # Resolve aliases
  case "${1:?}" in

  # XXX: ( a|all ) shift && set -- user_scripts_all ;;

  ( script-bases )              set -- script --bases "${@:2}" ;;
  ( script-baseids )            set -- script --baseids "${@:2}" ;;

  # Every good citizen on the executable lookup PATH should have these
  ( "-?"|-h|help )              set -- help "${@:2}" ;;
  ( --help|long-help )          set -- longhelp "${@:2}" ;;
  ( -V|--version|version )      set -- version "${@:2}" ;;

  ( --aliases|aliases )         set -- aliases "${@:2}" ;;
  ( --aliases-raw)              set -- aliases_raw "${@:2}" ;;

  ( --handlers|handlers )       # Display all potential handlers
                                set -- handlers "${@:2}" ;;

  ( --commands|commands )      # ....
                               set -- commands "${@:2}" ;;

  ( --env|variables )          set -- envvars "${@:2}" ;;

  esac

  # [[ $1 = "${script_defcmd:?}" ]] || script_defenv[script_cmdals]=

  # Print everything using appropiate quoting
  args_dump "$@" &&

  # XXX: do so more script/shell session/mode, but note that defarg almost
  # always runs in a subshell.
  user_script_stdv_defenv &&

  # Print defaults for some vars wanted/needed before entering script
  # (ie. for the particular bootstrap, loadenv, hooks, etc. we expect).
  for var in "${!script_defenv[@]}"
  do
    [[ ${!var-} = "${script_defenv["$var"]}" ]] ||
      printf '; %s=%s' "$var" "${script_defenv["$var"]}"
  done
}

user_script_envvars () # ~ # Grep env vars from loadenv
{
  local bid h
  for bid in $(user_script_baseids)
  do
    for h in loadenv ${script_xtra_envvars:-defaults}
    do
      sh_fun "${bid}_$h" || continue
      echo "# ${bid}_$h"
      type "${bid}_$h" | grep -Eo -e '\${[A-Z_]+:=.*}' -e '[A-Z_]+=[^;]+' |
            sed '
                  s/\([^:]\)=/\1\t=\t/g
                  s/\${\(.*\)}$/\1/g
                  s/:=/\t?=\t/g
              '
      true
    done
  done | {

    # Handle output formatting
    test -n "${u_s_env_fmt:-}" || {
      test ! -t 1 || u_s_env_fmt=pretty
    }
    case "${u_s_env_fmt:-}" in
        ( pretty ) grep -v '^#' | sort | column -s $'\t' -t ;;
        ( ""|plain ) cat ;;
    esac
  }
}

# FIXME: fixup before calling lib-init shell-uc
user_script_fix_shell_name ()
{
  PID_CMD=$(ps -q $$ -o command= | cut -d ' ' -f 1)
  test "${SHELL_NAME:=$(basename -- "$SHELL")}" = "$PID_CMD" || {
    test "$PID_CMD" = /bin/sh && {
      ${LOG:?} note "" "$SHELL_NAME running in special sh-mode"
    }
    # I'm relying on these in shell lib but I keep getting them in the exports
    # somehow
    SHELL=
    SHELL_NAME=
    #|| {
    #  $LOG warn ":env" "Reset SHELL to process exec name '$PID_CMD'" "$SHELL_NAME != $PID_CMD"
    #  #SHELL_NAME=$(basename "$PID_CMD")
    #  #SHELL=$PID_CMD
    #}
  }
}

user_script_graph_init () # ~ <Base ...> # Traverse (env) nodes, and record paths
# and roots in script-node{,-base} resp.
{
  local base{,id,s}
  stderr echo "user-script:graph-init base($#): $*"
  while [[ $# -gt 0 ]]
  do
    stderr echo graph-init $1 ${us_node_base["${1:?}"]+base:set} ${us_node_base["${1:?}"]-base:unset}

    [[ ${us_node_base["${1:?}"]+set} ]] && {
      set -- ${us_node_base["$1"]} "${@:2}"
      continue
    }
    : "${1:?}"
    baseid="${_//[:.-]/_}"
    : "${baseid}__grp"
    : "${!_:-}"
    bases=${_//,/ }
    test -n "$bases" || {
      str_globmatch " $ENV_SRC " "* */$1.sh *" &&
        shift && continue
      # Load script base or fail graph-init.
      uc_script_load "$1" || return
      # Retry but with base source file loaded.
      continue
    }
    [[ $bases ]] ||
      $LOG error "" "Unable to init graph for group '$1'" "$baseid" $? || return

    #stderr echo "$FUNCNAME node $1: bases: $bases" &&
    for base in $bases
    do
      sys_nconcatl "us_node[\"${base:?}\"]" "$1" &&
      sys_nconcatn "us_node_base[\"$1\"]" base || return
    done
    set -- $bases "${@:2}"
  done
}

# Transform glob to regex and invoke script-listfun for libs and other source
# files. This turns on script-listfun flag h by default.
user_script_handlers () # ~ [<Name-globs...>] # Grep function defs from main script
{
  test $# -eq 0 && set -- ".*" || set -- "\([a-z0-9_]*_\)\?$(grep_or "$@")"

  # NOTE: some shell allow all kinds of characters in functions.
  # sometimes I define scripts as /bin/bash and use '-', maybe ':'.

  local name slf_h=${slf_h:-1} exec

  for name in ${script_lib:-}
  do
    $LOG debug :handlers "Listing from lib" "$name:$1"
    script_listfun "$name" "$1" || true
  done

  for name in ${script_src:?}
  do
    exec=$(command -v "$name")
    $LOG debug :handlers "Listing from source" "$name:$exec:$1"
    script_listfun "$exec" "$1" || true
  done
}

# By default show short help of only usage and main commands if available.
# About 10, 20, 25 lines tops telling about the script and its entry points.
#
# Through other options, display every or specific parts. Help parts are:
# global aliases, envvars, handlers and usage per handler.
#
# The main options are:
#  -h|help for short help, like usage
#  --help|long-help for help with all main commands, aliases and env
#
# With argument, display only help parts related to matching function(s).
user_script_help () # ~ [<Name>]
{
  local _baseid
  for _baseid in $(user_script_baseids)
  do
    ! sh_fun "${_baseid}"_usage || break
  done
  "${_baseid}"_usage "$@" || return
  #at_ user-script usage --first "$@"
  #user_script_ usage "$@" || return

  test $# -gt 0 -o "${longhelp:-0}" -eq 0 || {

    # Add env-vars block, if there is one
    test "${longhelp:-0}" -eq 0 || {
      envvars=$( user_script_envvars | grep -v '^#' | sed 's/^/\t/' )
      test -z "$envvars" ||
          printf '\nEnv vars:\n%s\n\n' "$envvars"
    }
  }
}

# init-required-libs
# Temporary helper to load and initialize given libraries and prerequisites,
# and run init hooks. Libs should use lib-require from load or init hook to
# indicated the prerequisites.
# XXX: lib-init is protected against recursion.
#
user_script_initlibs () # ~ <Required-libs...>
{
  local pending lk=${lk:-}:initlibs
  lib_require "$@" ||
    $LOG error "$lk" "Failure loading libs" "E$?:$*" $? || return

  set -- $(user_script_initlibs__needsinit ${lib_loaded:?})
  test 0 -eq $# && return
  while true
  do
    # remove libs that have <libid>_init=0 ie. are init OK
    set -- $(user_script_initlibs__initialized "$@")
    test 0 -lt $# || {
        # XXX: if debug
        declare -a loaded=( $lib_loaded ) initialized
        if_ok "$(std_noerr lib_uc_hook var _lib_init)" &&
          initialized=( $_ ) && : "${#initialized[@]}" || : "?"
        $LOG info "$lk" "Done" "loaded=${#loaded[@]};initialized=$_"
        break
      }
    pending=$#

    $LOG info "$lk" "Initializing" "[:$#]:$*"
    INIT_LOG=$LOG lib_init "$@" || {
      test ${_E_retry:-198} -eq $? && {
        set -- $(user_script_initlibs__initialized "$@")
        test $pending -gt $# || {
          set -- "${@:2}" "$1"
        }
        #  $LOG error :us-initlibs "Unhandled next" "[:$#]:$*" 1 || return
        continue
      } ||
        $LOG error "$lk" "Failure initializing libs" "E$_:$lib_loaded" $_ ||
          return
    }
  done
}
user_script_initlibs__needsinit ()
{
  declare lib
  for lib in "${@:?}"
  do
    : "${lib//[^A-Za-z0-9_]/_}_lib__init"
    ! sh_fun "$_" || echo "$lib"
  done
}
user_script_initlibs__initialized ()
{
  declare lib
  for lib in "${@:?}"
  do
    : "${lib//[^A-Za-z0-9_]/_}_lib_init"
    test 0 = "${!_:-}" || echo "$lib"
  done
}

# TODO: deprecate
user_script_libload ()
{
  : "$(sys_exc user-script:libload Deprecated)"
  test $# -gt 0 || return
  while test $# -gt 0
  do
    . "${1:?}" || return
    script_lib=${script_lib:-}${script_lib:+ }$1
    shift
  done
}

# Helper functions that groups several setup script parts, used for static
# init, loadenv, etc.
#
#   defarg: Load/init user-script base. Call before using defarg etc.
#   groups: Scan for [<base>_]<script-part>__{grp,libs,hooks}
#   usage: Load/init libs for usage
#
user_script_load () # (y*) ~ <Actions...>
{
  [[ $# -gt 0 ]] || set -- defarg
  while [[ $# -gt 0 ]]
  do
    #! uc_debug ||
    ! sys_debug ||
        $LOG info :user-script:load "Running load action" "$1"
    case "${1:?}" in

    ( baseenv ) # Entire pre-init for script, ie. to use defarg
        [[ ${script_base-} ]] || {

          : "${SCRIPTNAME:?}"
          : "${_//[^A-Za-z0-9_-]/-}"
          script_base=$_

          local -n group="${script_base//-/_}__grp"
          # XXX: local -n group="$(str_word "${script_base:?}")__grp"
          : "${group:=user-script}"
        }
        script_envinit ${script_base//,/ }
      ;;

    ( defarg ) # Entire pre-init for script, ie. to use defarg
        : "${script_defcmd:=usage-nocmd}"
        lib_require us-fun us user-script shell-uc args &&
        lib_init shell-uc &&
        set -- "$@" log baseenv screnv
      ;;

    ( log )
        #lib_uc_hook pairs _lib_load &&
        #lib_uc_hook pairs _lib_init &&
        #export UC_LOG_BASE="${UC_LOG_BASE-}${UC_LOG_BASE+/}${SCRIPTNAME}[$$]"
        lib_require user-script &&
        user_script_initlog
      ;;

    ( screnv )
        # Only INTERACTIVE/BATCH_MODE is inheritable (obviously, but with
        # caution as well). FIXME: ASSERT is taken by lib as well.
        # XXX:
        for scriptenv in DEV DEBUG DIAG INIT ASSERT QUIET VERBOSE
        do
          ! [[ ${!scriptenv+set} ]] || {
            declare +x ${scriptenv}=${!scriptenv?}
          }
        done

        test -t 0 -o -t 1 &&
          : "${INTERACTIVE:=true}" ||
          : "${INTERACTIVE:=false}"

        # Now default verbosity to 3 (error) for batch-mode, or 5 (notice) for user
        # script commands.
        # Also make a note during (interactive) user-mode about any batch-mode
        # command handlers ie. that dont generate notice level messages about
        # command handling at all but focus on reliability and integrity and only
        # report on non-nominal events?
        : "${DIAG:=false}"
        : "${ASSERT:=true}"
        : "${INIT:=false}"
        : "${INTERACTIVE:=false}"

        "${INTERACTIVE:?}" &&
          : "${BATCH_MODE:=false}" ||
          : "${BATCH_MODE:=true}"

        "${BATCH_MODE:?}" && {
          : "${QUIET:=true}"
          : "${verbosity:=${v:-3}}"
        } || {
          : "${QUIET:=false}"
          : "${verbosity:=${v:-5}}"
        }

        v=$verbosity

        # I really want every script to trigger, so we can adjust env properly
        export verbosity v
      ;;

    ( groups )
        local name=${script_part:-${script_cmd:?}} libs hooks \
          lk lctx plk=${lk:-}
        lk=${plk:-}:user-script:load[group:$name]
        lctx=
        ! "${VERBOSE:-false}" ||
          $LOG notice "$lk" "Loading groups " "$lctx"

        stderr echo script_base=$script_base
        stderr echo script_part=$script_part
        stderr echo for $script_part at bases $(user_script_bases "$name" | tac)
        stderr echo all bases $(user_script_bases | tac)
        #stderr echo groups for $script_part at bases $(user_script_bases "$name" | tac)
        #if_ok "$(user_script_bases "$name" | tac)" || return
        if_ok "$(user_script_bases | tac)" || return
        for base in $_
        do
          : "${base//[:.-]/_}__libs"
          test -z "${!_-}" || {
            us_node_libs["$base"]=${_//,/ }
            libs=${libs:-}${libs:+ }${us_node_libs["$base"]}
          }
          : "${base//[:.-]/_}__hooks"
          test -z "${!_-}" || {
            us_node_hooks["$base"]=${_//,/ }
            hooks=${hooks:-}${hooks:+ }${us_node_hooks["$base"]}
          }
        done

        test -z "${libs:-}" && {
          test -n "${hooks:-}" || {
            "${QUIET:-false}" ||
              $LOG warn "$lk" "No grp, libs or hooks for user-script sub-command" "$lctx"
            return ${_E_next:-196}
          }
        } || {
          "${QUIET:-false}" ||
            $LOG info "$lk" "Initializing libs for group" "$name:$libs"
          user_script_initlibs $libs ||
            $LOG error "$lk" "Initializing libs for group" "E$?:$name:$libs" $?
        }
        test -z "${hooks:-}" && return
        local \
          us_cmdhooks_stat \
          us_cmdhook_group=$name \
          us_cmdhook_lk="$plk:user-script:hooks[group:$name]" \
          us_cmdhook_name \
          us_cmdhook_idx
        local -a us_cmdhook_arr
        <<< "${hooks// /$'\n'}" mapfile -t us_cmdhook_arr || return

        "${QUIET:-false}" ||
        ! "${VERBOSE:-false}" ||
        ! "${DEBUG:-false}" ||
        ! "${INIT:-false}" ||
          $LOG debug "$lk" "Running hooks (${#us_cmdhook_arr[*]})" "${hooks// /,}"

        for us_cmdhook_idx in "${!us_cmdhook_arr[@]}"
        do
          us_cmdhook_name=${us_cmdhook_arr[us_cmdhook_idx]}
          "$us_cmdhook_name" || {
            us_cmdhooks_stat=$?
            : "$us_cmdhooks_stat"
            $LOG error "$lk" "Failure in hook" "E$_:$us_cmdhook_name" $_ || return
          }
        done
        return ${us_cmdhooks_stat-0}
      ;;

    ( rulesenv )
        user_script_initlibs std-uc shell-command-script cached-timer
      ;;

    ( scriptenv )
        user_script_initlibs sys || return
        "${QUIET:-false}" ||
        ! "${ASSERT:-false}" || {
          user_script_initlibs sys assert || return
        }
      ;;

    ( node )
        script_part=${script_cmd:-}
      ;;

    ( usage )
      lib_load user-script str-htd shell-uc us &&
      lib_init shell-uc ;;

    ( help ) set -- "" usage ;;
    ( -- ) break ;;

    ( bash-uc ) lib_load bash-uc && lib_init bash-uc ;;

    ( self-lib ) user_script_initlibs ${script_name} ;;

    ( * ) $LOG error :user-script:load "No such load action" "$1" \
        ${_E_nsk:-67} || return
    esac ||
        $LOG error :user-script:load "In load action" "E$?:$1" $? || return
    shift
  done
}

# Default loadenv for user-script, run at the end of doenv just before
# deferring to handler. Really only to set some defaults copied from other
# places for convenience.
user_script_loadenv ()
{
  [[ ${user_script_loaded-} -eq 1 ]] && return

  : "${US_BIN:="$HOME/bin"}"
  : "${PROJECT:="$HOME/project"}"
  : "${U_S:="$PROJECT/user-scripts"}"
  : "${LOG:="$U_S/tool/sh/log.sh"}"

  user_script_stdstat_env

  test -d "$US_BIN" || {
    $LOG warn :loadenv "Expected US-BIN (ignored)" "$US_BIN"
  }

  user_script_fix_shell_name &&
  # TODO: user-script should know about the current user client (terminal and
  # shell) session, and set modes and register callbacks
  user_script_shell_mode &&

  # XXX: Load bash-uc because it sets errexit trap, should cleanup above shell-mode
  {
    test "$SCRIPTNAME" != user-script.sh && {
      user_script_load bash-uc || return
    } || {
      user_script_load "${script_cmdals:-$script_cmd}" bash-uc
    }
  } && {
    # XXX: run again or guard against redefs?
    #user_script_stdv_defenv

    "${INTERACTIVE:?}" && {
      ! "${QUIET:-false}" ||
      ! {
            "${DIAG:-false}" || "${INIT:-false}"
      } || {
        : "${QUIET:=false}"
        : "${CT_VERBOSE:=true}"

        [[ "$v" -gt 3 ]] &&
          $LOG alert "${lk-}:loadenv" "Running interactively"
      }
    } || {
      ! "${QUIET:-false}" ||
      ! {
          "${DIAG:-false}" || "${INIT:-false}"
      } ||
        $LOG notice "${lk-}:loadenv" "Running non-interactively"
    }

    # If verbosity is low, warn or notices if there are special verbosity modes
    # active
    [[ "$v" -le 5 ]] && {

      ! "${INTERACTIVE:?}" || {
        [[ "$v" -le 3 ]] && {
          ! "${QUIET:-false}" ||
          ! {
            "${DEBUG:-false}" || "${DIAG:-false}" || "${INIT:-false}"
          } ||
            $LOG alert "${lk-}:loadenv" \
              "Script is running at reduced verbosity" \
              "debug-modes: $(sys_debug_tag)"
        } || {
          ! "${QUIET:-false}" ||
          ! {
            "${DEBUG:-false}" || "${DIAG:-false}" || "${INIT:-false}"
          } ||
            $LOG warn "${lk-}:loadenv" \
              "Script is running quietly" \
              "debug-modes: $(sys_debug_tag)"
        }
      }
      # No additional log/std notices for non-interactive runs?

    } || {
      ! "${QUIET:-false}" || {
        ! "${DEBUG:-false}" ||
        ! "${DIAG:-false}"
      } ||
        $LOG warn "${lk-}:loadenv" "Script is running quietly" \
            "debug-modes: $(sys_debug_tag)"
    }

    #declare +x DEV DEBUG DIAG INIT ASSERT QUIET VERBOSE

    true
  } &&
    user_script_loaded=1 &&
    return ${_E_continue:-195}
}

user_script_longhelp () # ~ [<Name>]
{
  longhelp=1 user_script_help "$@"
}

# TODO: prototype better sh-mode parts here

#declare -g US_MODE
#declare -gA US_MODES US_MODES_BI
#
#US_MODE_BI[strict]="private-group exception-log strict-shell"
#US_MODE_BI[dev]="private-sharegroup exception-log strict-shell"

# TODO: integrate accum. setup script from US:tools:sh-mode
user_script_mode () # ~ <Modes...>
{
  local mode changed
  for mode
  do
    [[ "${US_MODES["$mode"]:+set}" ]] && continue
    case "${mode:?}" in
    ( strict | dev | debug | diag | init | assert )
    ;;
    esac
  done

  ! "${DIAG:-false}" ||
  ! "${changed:-false}" || {
    str_globmatch "$US_MODE" "$- *" || {
      "${ASSERT:-false}" || "${DEBUG:-false}" && : "$- <> $US_MODE" || : ""
      $LOG warn "" "us-mode is not in sync with sh-mode" "$_"
    }
  }

  #us_mode +dev +strict
  ! "${changed:-false}" || US_MODE="$- ${!US_MODES[*]}"
}

user_script_resolve_alias () # ~ <Name> #
{
  echo "$us_aliases" | {
      while read -r handler aliases
      do
        test "$handler" != "$handle" && {
            case " $aliases " in
                ( *" $handle "* ) echo $handler ; return ;;
                ( * ) continue ;;
            esac
        } || {
          echo $handler
          return
        }
      done
      return 3
  }
}

user_script_resolve_aliases () # ~ <Handlers...> # List aliases for given names
{
  for handle
  do
      {
          user_script_resolve_alias "$handle" || echo
      } | sed "s#^#$handle #"
  done
}

user_script_resolve_alias () # ~ <Name> # Give aliases for handler
{
  echo "$us_aliases" | {
      while read -r handler aliases
      do
        test "$handler" != "$handle" && {
            case " $aliases " in
                ( *" $handle "* ) echo $aliases ; return ;;
                ( * ) continue ;;
            esac
        } || {
          echo $aliases ; return
        }
      done
      return 3
    }
}

user_script_resolve_handlers () # ~ <Handlers...> # List handlers for given names
{
  for handle in "$@"
  do
    echo "$us_aliases" | {
        while read -r handler aliases
        do
          test "$handler" = "$handle" && {
              echo $handler
          } || {
              case " $aliases " in
                  ( *" $handle "* ) echo $handler ; break ;;
                  ( * ) false ;;
              esac
          }
        done
      } || echo $handle
  done
}

user_script_script ()
{
  case "${1:?}" in
  ( --bases )
      $LOG info "" preseed-bases "${script_bases:-(unset)}"
      ( user_script_bases "${@:2}" )
    ;;
  ( --baseids )
      $LOG info "" preseed-baseids "${script_bases:-(unset)}"
      ( user_script_baseids "${@:2}" )
    ;;
  ( * ) $LOG error :script "?" "$1" 127
  esac
}

user_script_shell_mode ()
{
  test -n "${user_script_shell_mode:-}" && return
  user_script_shell_mode=0

  # XXX: see bash-uc init hook

  #test -z "${DEBUGSH:-}" || set -x

  #"${U_S:?}"/tool/sh/part/sh-mode.sh &&
  #test "${DEBUG:-0}" = "0" && {
  #    sh_mode strict || return
  #  } || {
  #    sh_mode strict dev || return
  #  }

  test -z "${BASH_VERSION:-}" || {
  # XXX: test "$IS_BASH" = 1 -a "$IS_BASH_SH" != 1 && {

  #  set -u # Treat unset variables as an error when substituting. (same as nounset)
  #  set -o pipefail #

  #  test -z "${DEBUG:-}" || {

  #    set -h # Remember the location of commands as they are looked up. (same as hashall)
      set -E # If set, the ERR trap is inherited by shell functions.
      set -T
      set -e
      shopt -s extdebug

      lib_require sys || return
      trap 'sys_exc_trc' ERR

      #lib_require bash-uc || return
      #trap 'bash_uc_errexit' ERR
      #trap 'bash_uc_errexit Bash Exit:$? 2' EXIT
  #  }
  }

  ! "${DEBUG:-false}" || {
    : "${BASH_VERSION:?"Not sure how to do debug"}"
  }

  test -z "${ALIASES:-}" || {
    : "${BASH_VERSION:?"Not sure how to do aliases"}"

    # Use shell aliases and templates to cut down on boilerplate for some
    # user-scripts.
    # This gives a sort-of macro-like functionality for shell scripts that is
    # useful in some contexts.
    shopt -s expand_aliases &&

    us_shell_alsdefs &&
    user_script_alsdefs ||
        $LOG error : "Loading aliases" E$? $? || return
  }

  user_script_shell_mode=1
}

user_script_stdstat_env ()
{
  # See U-C:std-uc.lib for latest definitions
  : "${_E_fail:=1}"
  # 1: fail: generic non-success status, not an error per se
  : "${_E_script:=2}"
  # 2: script: error caused by broken syntax or script misbehavior
  : "${_E_user:=3}"
  # 3: user: usage error or faulty data

  : "${_E_nsk:=67}"
  #: "${_E_nsa:=68}"
  #: "${_E_cont:=100}"
  : "${_E_recursion:=111}" # unwanted recursion detected

  #: "${_E_bug:=121}" # BUG: known issue
  #: "${_E_fixme:=122}" # FIXME/task: cleanup required or incomplete specs/code/...
  : "${_E_xxx:=123}" # XXX/deprecated: attention/removal required
  : "${_E_NF:=124}" # no-file/no-such-file(set): file missing or nullglob
  : "${_E_missing:=125}" # TODO: impl. missing
  : "${_E_not_exec:=126}" # NEXEC not-an-executable
  : "${_E_not_found:=127}" # NSFC no-such-file-or-command
  # 128+ is mapped for signals (see trap -l)
  # on debian linux last mapped number is 192: RTMAX signal
  : "${_E_GAE:=193}" # generic-argument-error/exception
  : "${_E_MA:=194}" # missing-arguments
  : "${_E_continue:=195}" # fail but keep going
  : "${_E_next:=196}"  # Try next alternative
  : "${_E_break:=197}" # success; last step, finish batch, ie. stop loop now and wrap-up
  : "${_E_retry:=198}" # failed, but can or must reinvoke
  : "${_E_limit:=199}" # generic value/param OOB error?

  TODO () { test -z "$*" || stderr echo "To-Do: $*"; return ${_E_missing:?}; }

  error () { $LOG error : "$1" "E$2" ${2:?}; }
  warn () { $LOG warn : "$1" "E$2" ${2:?}; }
}

user_script_stdv_defenv ()
{
  [[ ${script_defenv[QUIET]-} ]] || script_defenv[QUIET]=${QUIET:-false}
  [[ ${script_defenv[QUIET]:?} ]] && {
    "${script_defenv[QUIET]:?}" &&
      script_defenv[VERBOSE]=false ||
      script_defenv[VERBOSE]=true

  } || {
    [[ ${script_defenv[VERBOSE]-} ]] || script_defenv[VERBOSE]=${VERBOSE:-false}
    "${script_defenv[VERBOSE]:?}" &&
      script_defenv[QUIET]=false ||
      script_defenv[QUIET]=true
  }
}

user_script_unload ()
{
  # reset error handler so main can do non-zero exit now
  trap ERR
}

# Display description how to evoke command or handler
user_script_usage () # ~ [<Cmd>]
{
  local short=0 slf_l

  test $# -eq 0 && {
    short=1 # Make it a list of brief descriptions
    slf_l=0
    printf 'Usage:\n\t%s <Command <Arg...>>\n' "${script_base%[, ]*}"
    set -- ${script_maincmds:?}
  } || {
    slf_l=1 # Strip brief description, just show arg spec
    printf 'Usage:\n'
  }

  lib_load str-htd || return

  # Resolve handler (if alias) and output formatted spec
  local us_aliases alias_sed handlers
  test $slf_l -eq 0 && {
      user_script_usage_handlers "$@" || {
        $LOG error :usage "handlers for" "E$?:$*" $? || return
      }
    } || {
      user_script_usage_handlers "$1" || true
    }

  # XXX: could jsut use bash extdebug instead of script-{src,lib}
  # however these all have to be loaded first, creating a chicken and the egg
  # problem
  # TODO func-comment Needs abit of polishing. and be moved to use for other
  # functions as well
  test -n "$handlers" || {
    $LOG error :user-script:usage "No handler(s) found" "$*"
    #return 1

    "${baseid}"_loadenv all || return
    user_script_usage_ext "$1" || return
    echo "Shell Function at $(basename "$fun_src"):$fun_ln:"
    script_listfun $fun_src "$handlers" &&
    lib_load src &&
    #. $U_S/src/sh/lib/os.lib.sh
    #. $U_S/src/sh/lib/src.lib.sh
    func_comment "$handlers" "$fun_src" ||
      $LOG warn :user-script:usage "No function comment" "$*"
    return
  }

  # Gather functions again, look for choice-esacs
  test -z "$handlers" || {
    local sub_funs actions
    test $slf_l -eq 0 && {
        user_script_usage_choices "$handlers" ||
          $LOG info :user-script:usage "No choice usage" "E$?:$handlers"
      } || {
        user_script_usage_choices "$handlers" "${2:-}" ||
          $LOG info :user-script:usage "No choice usage" "E$?:${2:-}:$handlers"
      }
  }

  test $short -eq 1 && {
    test -z "${script_defcmd-}" ||
      printf '\t%s (%s)\n' "${script_base%[, ]*}" "$script_defcmd"
    printf '\n%s\n' "${script_shortdescr:-(no-shortdescr)}"
  } || {
    true # XXX: func comments printf '%s\n\n' "$_usage"
  }
}

user_script_version () # ~
{
  script_version
}

# TODO: sort out parsing from src comments and AST exclusive usage definitions.
# E.g. (y) is AST, (x) is source or something like that.
user_script_usage_choices () # ~ <Handler> [<Choice>]
{
  sub_funs=$( slf_t=1 slf_h=0 user_script_handlers ${1:?} |
      while IFS=$'\t' read -r fun_name fun_spec fun_descr
      do
        fnmatch "* ?y? *" " $fun_spec " || continue
        echo "$fun_name"
      done)
  [[ $sub_funs ]] ||
    $LOG debug "${lk-}:usage-choices" "No choice specs" "handler:$1" 1 || return

  # Always use long-help format if we're selecting a particular choice (set)
  test -n "${2:-}" -o ${longhelp:-0} -eq  1 && {

    test -z "${2:-}" && {
       actions=$( for fun_name in $sub_funs
         do
           sh_type_esacs_tab $fun_name
         done |
             grep -v '^\*'$'\t' |
             sed 's/\t/\t$ /' | column -c2 -s $'\t' -t )

        true
    } || {

       actions=$( for fun_name in $sub_funs
         do
           sh_type_esacs_tab $fun_name
         done |
             grep '\(^\|| \)'"${2:-".*"}"'\( |\|'$'\t''\)' |
         while IFS=$'\t' read -r case_key case_script
         do
           echo -e "$case_key\t$ $case_script"
           # XXX: take last command and use as primary nested routine that
           # implements action
           #str_globmatch "$case_script" "* && *"
           #str_globmatch "$case_script" "* || *"
           #: "${case_script// && *}"
           #: "${case_script// || *}"

           : "${case_script//*; }"
           alias_cmd=$_
           alias_cmdname=${alias_cmd// *}
           test -n "$alias_cmdname" &&
           sh_fun "$alias_cmdname" || {
             $LOG error "" "No case handler found" "$case_key:${2:-} case:$case_script"
             continue
           }
           # Fetch usage as well for called routine
           user_script_usage "$alias_cmdname" | tail -n +3 | sed 's/^/ \t \t/'
         done | column -c2 -s $'\t' -t )

       true
    }

  } || {
    actions=$(for fun_name in $sub_funs
        do sh_type_esacs_choices $fun_name
        done | grep -v '^\*$' )

  }
  test -n "$actions" || {
    $LOG error "" "Cannot get choices" "fun:${1:?}"
    return 1
  }
  test -n "${2:-}" && {
    printf "\nChoice '%s':\n" "$2"
  } || {
    printf "\nAction choices '%s':\n" "$1"
  }
  echo "$actions" | sed 's/^/\t/'
}

user_script_usage_ext ()
{
  local h=$1 fun=${1//-/_} fun_def

  shopt -s extdebug
  fun_def=$(declare -F "$fun") || {
    $LOG error "" "No such type loaded" "fun?:$fun"
    return 1
  }

  fun_src=${fun_def//* }
  fun_def=${fun_def% *}
  fun_ln=${fun_def//* }

  script_lib=${script_lib:-}${script_lib:+ }$fun_src
  handlers=$fun
}

user_script_fetch_handlers ()
{
  us_aliases=$(user_script_aliases "$@" |
        sed 's/^\(.*\): \(.*\)$/\2 \1/' | tr -d ',' )
  alias_sed=$( while read -r handler aliases
          do
              printf 's/^\<%s\>/( %s | & )/\n' "$handler" "${aliases// / | }"
          done \
        <<< "$us_aliases"
      )
  handlers=$(user_script_resolve_handlers "$@" | remove_dupes | lines_to_words)
}

# Output formatted help specs for one or more handlers.
user_script_usage_handlers () # ~ <Actions...>
{
  user_script_fetch_handlers "$@" || return

  # FIXME:
  # Do any loading required for handler, so script-src/script-lib is set
  #! sh_fun "${baseid}"_loadenv || {
  #  "${baseid}"_loadenv $handlers || {
  #      $LOG error :handlers "Loadenv error" "E$?" $? || return
  #  }
  #}

  # Output handle name(s) with 'spec' and short descr.
  slf_h=1 user_script_handlers $handlers | sed "$alias_sed" | sed "
        s/^\t/\t\t/
        s/^[^\t]/\t${script_base%[, ]*} &/
    "
}

user_script_usage_nocmd ()
{
  user_script_usage && return ${_E_user:-3}
}

script_version () # ~ # Output {name,version} from script-baseenv
{
  echo "${script_name:?}/${script_version:-null}"
}

# Use alsdefs set to cut down on small multiline boilerplate bits and reduce
# those idiomatic script parts to oneliners, tied with re-usable patterns.
# See us-shell-alsdefs.
#
# This defines the basic set provided and used? by user-scripts,
# and doubles as a oneliner for user-scripts to add their own.
user_script_alsdefs ()
{
    # alias-name   alsdef-key     input-1,2,3...  --
  us_shell_alias_defs \
  \
    sa_a1_act_lk   l-argv1-lk   act :-\$actdef ""   \${lkn:-\$act} -- \
    sa_a1_act_nlk  l-argv1-lk   act :-\$actdef ""   \${n:?}:\${act:?} -- \
  \
    sa_a1_d_lk     de-argv1-lk      \$_1def    :?         \${lkn:-\$1} -- \
    sa_a1_d_lk_b   de-argv1-lk      \$_1def    :-\$script_base   \${lkn:-\$1} -- \
    sa_a1_d_nlk    de-argv1-lk      \$_1def    :?         \${lkn:-\${n:?}:\$1} -- \
    sa_a1_d_nlk_b  de-argv1-lk      \$_1def    :-\$script_base   \${lkn:-\${n:?}:\$1} -- \
  \
    sa_E_nschc     err-u-nsk   \$lk "No such choice" "" 67 -- \
    sa_E_nsact     err-u-nsk   \$lk "No such action" \$act 67 -- \
  \
    "$@"
}

# Shell aliases can be useful, except when used as macro then they don't even
# have some variable expansion. But if we escape their definitions for eval,
# we can still declare new specific aliases from re-usable patterns.
#
# See us-shell-alias-def.
us_shell_alsdefs ()
{
  # XXX: note the us vs uc. ATM not sure I really want these 'expansions' in US.
  declare -g -A uc_shell_alsdefs=()

  # Some current patterns. Probably want to move to compose.

  # Take first argument and set to variable, and update LOG scope
  # This can both do optional or required, if $2 uses :? it will fail on empty
  # and unset.
  uc_shell_alsdefs[l-argv1-lk]='
    local ${1:?}=\${1${2:?}}
    test \$# -eq 0 || shift
    local lk=\"\${lk${3:-":-\${script_base}[$$]"}}${4:+:}${4:-}\"
  '

  uc_shell_alsdefs[d-argv1-lk]='
    test -n "\${1:-}" || {
      test $# -eq 0 || shift; set -- \"${1:?}\" "$@";
    }
    local lk=\"\${lk${2:-:-\$script_base}}${3:+:}${3:-}\"
  '

  uc_shell_alsdefs[de-argv1-lk]='
    test \$# -gt 0 || set -- \"${1:?}\"
    local lk=\"\${lk${2:-:-\$script_base}}${3:+:}${3:-}\"
  '

  # Take first argument and set to variable, and test for block device.
  uc_shell_alsdefs[l-argv1-bdev]='
    local ${1:?}=\${1${2:-":?"}}
    shift
    test -b \"\$${1:?}\" || {
      \$LOG warn \"${3:-\$script_base}\" \"Block device expected\" \"\" \$?
      return ${4:-3}
    }
  '

  # Argument helpers

  # Move to next sequence in arguments or return if empty
  uc_shell_alsdefs[argv-next-seq]='
      test \$# -eq 0 && return ${1:-0}
      while test \$# -gt 0 -a \"\${1:-}\" != \"--\"; do shift || return; done
      test \$# -eq 0 && return ${2:-0}
      shift
  '

  # Generic error+return
  uc_shell_alsdefs[err-u-nsk]='
    \$LOG error \"${1:-\$lk}\" \"${2:-"No such key/selection"}\" \
      \"${3:-\$1}\" ${4:-1}
  '
}

# NOTE: to be able to use us_shell_alias_defs, make sure you always call with
# fixed argument lengths to your templates.
us_shell_alias_def ()
{
  local als_name=${1:?} als_tpl=${2:?}
  shift 2
  eval "alias $als_name=\"${uc_shell_alsdefs[$als_tpl]}\"" ||
      $LOG error : "Evaluating template for alias" "E$?:$als_name:$als_tpl" $?
}

# Call us-shell-alias-def for each argv sequence (separated by '--')
# XXX: a better version would use arrays I guess
us_shell_alias_defs ()
{
  while test $# -gt 0
  do
    { ${alsdef_override:-false} && {
        ! ${US_DEBUG:-${DEBUG:-false}} ||
            test "$(type -t "${1:?}")" != alias || {
              unalias $1
              $LOG info : "Overriding alsdef" "$1:$2"
            }
      } ||
        test "$(type -t "${1:?}")" != alias
    } && {
      us_shell_alias_def "$@" || return
      ! ${US_DEBUG:-${DEBUG:-false}} ||
          $LOG debug : "Defined alsdef" "$1:$2"
    } || {
      ! ${US_DEBUG:-${DEBUG:-false}} ||
          $LOG debug : "Skipped alsdef" "$1:$2"
    }
    shift 2
    while test "${1:-}" != "--"
    do test $# -gt 0 || return 0
      shift
    done
    shift
  done
}


## Other functions

args_dump () # ~ <Argv...> # Print argv for re-eval
{
  while test $# -gt 0
  do
    # TODO: str_quote_shprop "$1"
    str_quote "$1"
    shift
    test $# -gt 0 || break
    printf ' '
  done
}
# copy

# TODO: eval this as part of us-load. Maybe use $3 or $6 or $9...
#
# use alt-io to comm with user, message class indicates severity usage,
# and may include requested facility or script basename. The caller has no
# control over where the messages go, different systems and execution
# environments may place specific restrictions. However at least some of the
# severity levels cannot be ignored, if the given base matches the current
# scripts' basename. Giving no base results in a warning in itself, unless
# some other preconditions are met usually indicating a prepared script (ie.
# batch not interactive user) environment.
#
stdmsg () # (e) ~ <Class> <Message> [<Context>]
{
  ${quiet:-false} && return
  true "${v:="${verbosity:-4}"}"
  case "${1:?}" in
      ( *"emerg" ) ;;
      ( *"alert" ) test "$v" -gt 0 || return 0 ;;
      ( *"crit" )  test "$v" -gt 1 || return 0 ;;
      ( *"err" )   test "$v" -gt 2 || return 0 ;;
      ( *"warn" )  test "$v" -gt 3 || return 0 ;;
      ( *"note" )  test "$v" -gt 4 || return 0 ;;
      ( *"info" )  test "$v" -gt 5 || return 0 ;;
      ( *"debug" ) test "$v" -gt 6 || return 0 ;;
  esac
  echo "${2:?}" >&2
}

stdstat () # ~ <Status-Int> <Status-Message> # Exit handler
{
  type sh_state_name >/dev/null 2>&1 &&
    stdmsg '*note' "$(sh_state_name "$1"): $2" ||
    stdmsg '*note' "Status was $1: $2"
  exit $1
}

# Lists name, spec and gist fields separated by tabs.
# Fun flag t turns off column formatting
# Fun flag h enables an alternative semi-readable help outline format
script_listfun () # (s) ~ [<Grep>] # Wrap grep for function declarations scan
{
  local script_src="${1:-"$(script_source)"}"
  shift 1
  fun_flags slf ht l
  grep "^$1 *() #" "$script_src" | {
    test $slf_h = 1 && {
      # Simple help format from fun-spec
      sed '
            s/ *() *# [][(){}a-zA-Z0-9=,_-]* *~ */ /g
            s/# \([^~].*\)/\n\t\1\n/g
          ' | {
                # Strip short usage descr
                test $slf_l = 1 && cat ||
                    grep -v -e '^'$'\t' -e '^$'
              }

    } || {

      # Turn into three tab-separated fields: name, spec, gist
      sed '
            s/ *() *//
            s/# \~ */#/
          ' | tr -s '#' '\t' | {
        test $slf_t = 1 && {
          cat
        } || {
          column -c3 -s "$(printf '\t')" -t | sed 's/^/\t/'
        }
      }
    }
  }
}

sh_type_fun_body ()
{
  { declare -f -- "${1:?}" || return
  } | tail -n +3 | head -n -1
}
# derive

str_quote ()
{
  case "$1" in
    ( "" ) printf '""' ;;
    ( *" "* | *[\[\]\<\>$]* )
      case "$1" in
          ( *"'"* ) printf '"%s"' "$1" ;;
          ( * ) printf "'%s'" "$1" ;;
      esac ;;
    ( * ) printf '%s' "$1" ;;
  esac
}
# copy str.lib

sys_loop () # ~ <Callback> <Items ...>
{
  local fun=${1:?}
  shift
  while [[ $# -gt 0 ]]
  do
    "$fun" "${1:?}" && break
    test ${_E_done:-200} -eq $? && return
    test ${_E_continue:-195} -eq $_ || return $_
    shift
  done
}


# FIXME: determine script listing method: find, locate, compgen or user data
user_script_sh_list ()
{
  case "${1:?}" in
  ( --find ) user_script_find "${@:2}"
    ;;
  ( * ) $LOG error "$lk" "No such action on list" "$1" 127
  esac
}


user_script_sh_defarg ()
{
  case "$1" in
  ( scripts-find|--find-scripts )            set -- find "${@:2}" ;;
  esac
}

user_script_sh_loadenv ()
{
  local script_part fail
  set -- ${script_cmdname:?} ${script_base//,/ }
  for script_part
  do
    # Start at first script node, load all libs and then execute hooks.
    # XXX: use status to coordinate groups from multiple bases?
    user_script_load groups && {
      $LOG notice "${lk-}:user-script[$script_part]" "Finished libs & hooks for group"
      break
    } || {
      test ${_E_next:-196} -eq $? && fail=true ||
      test ${_E_continue:-195} -eq $_ || return $_
      fail=false
    }
  done
  ! "${fail:-false}"
}

usage ()
{
  local failcmd ; test "${1-}" != "--" || { shift; failcmd="$*"; shift $#; }
  script_version "$@" >&2
  user_script_help "$@" >&2
  test -z "${failcmd-}" || {
    $LOG error ":usage" "No such command" "$failcmd"
    return 2
  }
  # Exit non-zero unless command was given
  test "${script_cmddef-}" = "0"
}


# Main boilerplate (mostly useless except for testing this script)
# To list all user-script instances, see user-script.sh all.

#us-env -r user-script || ${us_stat:-exit} $?
#test -n "${uc_lib_profile-}" || . "${UCONF:?}/etc/profile.d/bash_fun.sh"

test -n "${uc_fun_profile-}" ||
  . "${UCONF:?}/etc/profile.d/uc_fun.sh" ||
  ${us_stat:-exit} $?

! script_isrunning "user-script" .sh || {

  script_base=user-script-sh,user-script
  : "${US_EXTRA_CHAR:=:-}"
  user_script_load default || ${us_stat:-exit} $?

  # Strip extension from SCRIPTNAME (and baseid)
  SCRIPT_BASEEXT=.sh
  # Default value used when argv is empty
  #script_defcmd=usage
  # Extra handlers for user-script-aliases to extract from
  user_script_defarg=defarg\ aliasargv

  # Pre-parse arguments and reset argv: resolve aliased commands or sets default
  if_ok "$(user_script_defarg "$@")" &&
  eval "set -- $_" &&

  # Execute argv and end shell
  script_run "$@" || ${us_stat:-exit} $?
}

user_script_loaded=0
#
