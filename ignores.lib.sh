#!/usr/bin/env bash

### Ignores: Filename and path ignore rules from lists of globs

# Created: 2016-10-02

# Most functions have moved to globlist.lib

#      scm ) set -- "$@" $1-git $1-bzr $1-svn ;;
#      scm-git ) set -- "$@" $1-global $1-local ;;
#      scm-git-global )
#          echo ~/.gitignore-global
#          echo ~/.gitignore-clean-global
#          echo ~/.gitignore-temp-global
#        ;;
#      scm-git-local )
#          echo .gitignore
#          echo .git/info/exclude
#          # TODO: .attributes see pd:list-paths opts parsing;
#        ;;
#
#      scm-svn ) ;;
#      scm-hg ) ;;
#      scm-bzr )
#          echo .bzrignore
#        ;;


ignores_lib__load()
{
  lib_require str-htd date-htd meta || return

  : "${CONFIG_INCLUDE:=$HOME/bin/etc:${XDG_CONFIG_HOME:-$HOME/.config}:/etc}"

  : "${ignores_basename:=ignore}"
  : "${ignores_prefix=${base:-htd}}"
  : "${IGNORES_BASE:=$ignores_prefix$ignores_basename}"
  # Groups for primary globlist. This will depend on stddef and user prefs.
  : "${IGNORE_GROUPS:="global local"}"
  # Additionally to globs matches, ignore any directory with this entry
  # XXX: only used in other libs currently
  : "${IGNORE_DIR=.$IGNORES_BASE-dir}"
  # Default file for main ignore globlist, listing every glob from IGNORE_GROUPS
  : "${IGNORES_FILE:=.$IGNORES_BASE}"
  # Filename extension, used for files that do not start with IGNORE_FILE prefix
  : "${IGNORES_EXT=.globlist}"
  # XXX: Currently using TTL to validate cache. Can be set empty to force
  # explicit settings
  : "${IGNORES_TTL=$_1DAY}"

  # Template path for local/global config location
  : "${ignores_use_local_config_dirs:=true}"
  : "${IGNORES_CONFIG_BASE:=etc/$ignores_prefix$ignores_basename}"

  # Select mode to track cache-files: as neighbour to IGNORES_FILE or separately
  : "${ignores_use_cachedir:=true}"
  "$_" && {
    : "${CACHE_DIR:-${METADIR:?}/cache}"
    : "${IGNORES_CACHE_BASE:="$_/$IGNORES_BASE"}"
  } || {
    : "${IGNORES_CACHE_BASE:="$IGNORE_FILE-cache"}"
  }

  # Select file that will contain primary ignore globlist
  : "${ignores_build:=true}"
  "$_" && {
    # Use main file as primary globlist, to be updated using IGNORE_GROUPS
    : "${IGNORES:=$IGNORES_FILE}"
  } || {
    # Use cache file as generated for IGNORE_GROUPS directly
    : "${IGNORES:=$IGNORES_CACHE_BASE-${IGNORE_GROUPS// /,}$IGNORES_EXT}"
  }
}

ignores_lib__init()
{
  test -z "${ignores_lib_init:-}" || return $_

  # XXX: fill in ignore-groups and ignores array with groups/globlists
  ignores_stddef &&

  # Begin with an initial IGNORE_GLOBFILE value with local filename based on
  # frontend, i.e. for `htd` this by default would be HTD_IGNORE=.htdignore
  true #globlist_init "$ignores_prefix" "" IGNORE
}


# Return find options sequence to ignore (prune) globs from groups
ignores_find_expr () # ~ <Groups...>
{
  local glob ctx=${at_GlobList:-globlist}
  for glob in $(${ctx}_cat "$@")
  do
    ignores_find_glob_expr "$glob" || return
  done
}

# Execute find, ignoring globs from groups
ignores_find_files () # ~ <Prune-groups...>
{
  local find_ignores find_pwd=. find_arg="-a -print"
  find_ignores="-false $(ignores_find_expr "$@")"\
" -o -exec test -e \"{}/$IGNORE_DIR\" ';' -a -prune -o -true"
  eval find ${find_opts:-"-H"} ${find_pwd:-.} \\\( $find_ignores \\\) $find_arg
}

ignores_find_glob_expr ()
{
  case "${1:?}" in
    ( /*/ ) echo "-o -path \"$1*\" -a -prune" ;;
    (  */ ) echo "-o -path \"*/$1*\" -a -prune" ;;
    ( /*  ) echo "-o -path \"$1*\" -a -prune" ;;
    ( */* ) echo "-o -path \"*/$1*\" -a -prune" ;;
    (  *  ) echo "-o -name \"$1\" -a -prune" ;;
  esac
}

ignores_stddef ()
{
  declare -gA ignore_groups
  declare -gA ignores

  # Groups: every permutation of a few tags
  ignore_groups[purge]=$(echo {local,global}-purge)
  ignore_groups[clean]=$(echo {local,global}-clean)
  ignore_groups[drop]=$(echo {local,global}-drop)
  ignore_groups[local]=$(echo local-{purge,clean,drop})
  ignore_groups[global]=$(echo global-{purge,clean,drop})

  # Files
  "${ignores_use_local_config_dirs:=true}" && {
    ignores[local-purge]=$(echo ${IGNORES_CONFIG_BASE:?}/purge{,able}$IGNORES_EXT)
    ignores[local-clean]=$(echo ${IGNORES_CONFIG_BASE:?}/clean{,able}$IGNORES_EXT)
    ignores[local-drop]=$(echo ${IGNORES_CONFIG_BASE:?}/drop{,pable}$IGNORES_EXT)
  } || {
    ignores[local-purge]=$(echo ${IGNORES_FILE:?}-purge{,able})
    ignores[local-clean]=$(echo ${IGNORES_FILE:?}-clean{,able})
    ignores[local-drop]=$(echo ${IGNORES_FILE:?}-drop{,pable})
  }

  ignores[global-purge]=$(echo etc:purgeable)
  ignores[global-clean]=$(echo etc:cleanable)
  ignores[global-drop]=$(echo etc:droppable)

  #ignores[ignore]=${IGNORES_FILE?}
  #ignores[dir-ignore]=${IGNORE_DIR?}
}

#
