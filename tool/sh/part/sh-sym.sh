#!/usr/bin/env bash


## sh-sym: identify given symbol


# Show usage text or other information for shell keywords, buitins, other
# commands, aliases, but also paths and various sorts of packages, units and
# any item that is part of the current system. For this a set of callback
# handlers is needed that indicate what any given symbol represents and give
# sh-sym-ref clues how to handle it.

# E.g. this prints function source locations, the typeset for functions or
# complex aliases, includes the auto-complete declarations (interactive sessions
# only), and variable declarations matching <Name> as well.

# The sh-sym-det symbol is for an id-command mapping that serves as a registry
# for callback handlers that has two purposes: give a command to recognize and
# and Id for resulting set of symbols, the Id then is used to find a sh-sym-ref
# handler specific to that type of symbol.
declare -gA sh_sym_det=(
  [shell-lang-name]="type -t"
  [shell-lang-cmd]="sys_os_name" # As command -v but only return where type is file
  [sys-os-path]="sys_os_path"
  [shell-lang-var]="std_noerr declare -p" # aka sh-vspec
  [shell-lang-ac]="complete -p"
  [sys-os-package]="sys_os_package" # Dont know of exact-match query for dpkg -S
)

sh_sym_ref () # ~ <Names...>
{
  : source "sh-sym.sh"
  local __{cb{,i},sym,tp{,d}}
  # TODO: allow to request other formats from detectors
  : "${sh_sym_ref_fmt:=bash}"
  # Iterate given literal symbols
  for __sym in "${@:?"Expected one or more symbols"}"
  do
    # Attempt to resolve by trying 'detector' command and then handler
    for __cbi in ${!sh_sym_det[*]}
    do
      ! "${DEBUG:-false}" ||
        stderr echo "Found $__cbi symbol '$__sym'"
      ! __tpd=$(std_noerr ${sh_sym_det[$__cbi]} "$__sym") || {
        #stderr echo "found, '$__cbi' has symbol '$__sym' declared as '$__tpd'"
        sh_sym_ref__${__cbi//[^A-Za-z0-9_]/_}
      }
    done
  done | sh_sym_refpager
}
# Copy: Shell/symbol-reference

sh_sym_refpager ()
{
  IF_LANG=${sh_sym_ref_fmt?} ${REFPAGER:-${PAGER:?}}
}

sh_sym_ref__shell_lang_ac ()
{
  echo "$__tpd"
}

sh_sym_ref__shell_lang_cmd ()
{
  echo "${__tpd%%: *}"
  echo "# ${__tpd#*: }"
  #if_ok "$(ac_spec "$__sym" | sed 's/^/  /')" &&
  #echo -e "\nCompletions:\n$_"
}

sh_sym_ref__shell_lang_name ()
{
  case "$__tpd" in
  ( alias )
      if_ok "$(sh_als_exp "$__sym")" || return
      als="$_"
      : "${als%% *}"
      : "${_## }"
      test "$als" = "$_" && {
        echo "alias $__sym=$als"
        ! "${DEBUG:-false}" ||
          stderr echo "Recursing for symbol '$als' from alias '$__sym'"
        sh_sym_ref "$als" || return
      } || {
        echo "alias $__sym='${BASH_ALIASES[$__sym]}'"
        [[ ${BASH_ALIASES[$__sym]} = "$als" ]] || {
          ! "${VERBOSE:-false}" ||
            echo "# alias \`$__sym' expands to script:"
          echo "$als" | sed 's/^/   /'
        }
      }
      ! if_ok "$(which -- "$__sym" 2>/dev/null)" ||
        echo "# ! alias shadows \`$__sym' exec $_"
    ;;
  ( keyword | builtin )
      if_ok "$(help "$__sym")" && echo -e "Usage: $_\n" || r=$?
      echo " \`$__sym' is a shell $__tp"
      #! if_ok "$(ac_spec "$__sym" | sed 's/^/  /')" ||
      #  echo -e "\nCompletions:\n$_"
      #! if_ok "$(sh_vspec "$__sym")" ||
      #  echo -e "\nVariable:\n  $_"
      return ${r-}
    ;;
  ( file )
        [[ -x "$file" ]] && {
          "$__sym" --help 2>&1 || r=$?
        }
        #test "$__sym" = "$(command -v $__sym)" ||
        #  echo -e "\n \`$__sym' is exec $_"
        #! if_ok "$(ac_spec "${__sym##*/}" | sed 's/^/  /')" ||
        #  echo -e "\nCompletions:\n$_"
        #! if_ok "$(sh_vspec "$__sym")" ||
        #  echo -e "\nVariable:\n  $_"
        return ${r-}
    ;;
  ( function )
      local srcln srcfn
      if_ok "$(declare -F "$__sym")" &&
      read -r _ srcln srcfn <<< "$_" &&
      {
        declare -f "$__sym"
        echo "# source <$srcfn> line $srcln"
        #ac_spec "$__sym" || true
        sh_sym_fexp "$__sym"
      }
    ;;

  ( * )
      $LOG alert : "Symbol type?" "$__tpd:$__sym" 1
  esac
}

sh_sym_ref__shell_lang_var ()
{
  : "$__tpd
# Length: $( declare -n __symval=$__sym
sh_arr "$__sym" &&  {
  echo "${#__symval[@]}"
} || {
  echo "${#__symval}"
})" &&
  echo "$_"
}

sh_sym_ref__sys_os_path ()
{
  echo "${__tpd%%: *} ()"
  echo "{"
  echo "  : description \"${__tpd#*: }\""
  stat --format '  : access "%A %U(%u):%G(%g)"
  : size %s' "${__tpd%: *}"
  echo "}"
}

sh_sym_ref__sys_os_package ()
{
  echo "# $__tpd"
}

# Print export line for function, if found exported for current env
# XXX: there is no flag or attribute spec retrievable for functions? Using
# `env|grep` here as that seems like the only option, cannot check for variable
# if variable is special name with %-char. Ie. no syntax such as:
# ${BASH_FUNC_<fun>+set}
# ${BASH_FUNC_<fun>%+set}
# ${BASH_FUNC_<fun>%%+set}
sh_sym_fexp () # ~ <Name>
{
  : source "sh-sym.sh"
  if_ok "$(printf 'BASH_FUNC_%s%%%%=() { ' "${1:?}")" &&
  env | grep -q "$_" || return 0
  echo "declare -fx $1"
}

sh_vspec () # ~ <Shell-sym> # Print declaration for shell variable
{
  : source "sh-sym.sh"
  declare -p "${1:?}" 2>/dev/null
}

std_if ()
{
  : source "sh-sym.sh"
  if_ok "$("$@")" && echo "$_"
}

sys_os_package ()
{
  : "${1:?"sys-os-package: symbol expected"}"
  : source "sh-sym.sh"
  [[ ${1:0:1} = / ]] && : "$1" || if_ok "$(command -v "$1")" || return
  test -n "$_" &&
  dpkg -S "$_"
}

sys_os_name ()
{
  : "${1:?"sys-os-name: command name expected"}"
  : source "sh-sym.sh"
  [[ ${1:0:1} = / ]] && : "$1" || {
    local __path
    __path="$(command -v "$1")" &&
    [[ ${__path:0:1} = / ]] || return
    : "$__path"
  }
  test -n "$_" &&
  test -x "$_" &&
  echo "$_"
}

sys_os_path ()
{
  : "${1:?"sys-os-path: name or path reference expected"}"
  test "${_:0:1}" = / ]] && : "$1" || if_ok "$(sys_os_path_lookup "$1")" || return
  test -n "$_" &&
  file -s "$_"
}

# Unfortunately I dont know of any command to locate (any, ie. including
# non-executable) paths using PATH. So for that we need little routines such
# as these.
sys_os_path_lookup ()
{
  : "${1:?"sys-os-path-lookup: name or path reference expected"}"
  local __bd
  local -a __path
  sys_execmap __path echo "${PATH//:/$'\n'}" &&
  for __bd in "$PWD" "${__path[@]}"
  do
    [[ -e "$__bd/$1" || -h "$__bd/$1" ]] || continue
    echo "$__bd/$1"
    return
  done
  false
}

#
