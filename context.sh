#!/usr/bin/env bash


context__grp=user-script
context_sh__grp=context

context_sh_entries__libs=os-htd\ context
context_sh_entries () # ~ <Switch:-list> <...>
{
  local act=${1-}
  act="${act:+$(str_globstripcl "$act" "-")}" || return
  : "${act:=list}"
  test $# -eq 0 || shift
  local lk=${lk:-:context}:entries:-$act
  case "$act" in

    ( all-tags )
        context_tag_list
      ;;
    ( c|count )
        context_tab_cache && ctx_grep_f=Evc context_tab
      ;;
    ( check-tags ) # ~ # Look for (sub)tag and warn about case
        context_tab_cache && context_check "$@"
      ;;
    ( d|data ) context_tab_cache &&
        read_nix_user_data "${CTX_TAB_CACHE:?}" ;;
    ( e|exists|tags-exist )
        context --exists "$@"
      ;;
    ( f|fetch )
          if_ok "$(context_tag_entry "${1:?}")" &&
          context_parse "$_"
        ;;
    #( i|ids )
    #    ;;
    ( F|fr|fetch-raw )
          context_tag_entry "${1:?}"
        ;;
    ( g|any|grepi )
          test $# -gt 1 || set -- "${1:?}" -any
          {
            : "${ctx_grep_f:-Ev}"
            echo "# $ grep_f=-i ctx_grep_f=$_ generator=context_tab stattab_grep ${@@Q}"
            grep_f=-i generator=context_tab stattab_grep "$@"
          } |
            IF_LANG=todo.txt $PAGER
        ;;
    ( l|list )
          context_tab
        ;;
    ( f|files )
          # Get file references from other table
          context_sh_files tab | sed 's/^/#id /'
        ;;
    ( r|raw ) context_tab_cache &&
        read_nix_data "${CTX_TAB_CACHE:?}" ;;
    ( rel|related-tags )
          context_tab_cache &&
          contexttab_related_tags "$@"
          echo "Related tags: $tag_rel"
        ;;
    ( tagged )
          grep_f=-n generator=context_tab stattab_grep "$1" -tagged
        ;;

    ( * ) $LOG error "$lk" "No such action" "-$act:$*" 67
  esac
}

context_sh_files__libs=os-htd\ context
context_sh_files () # ~ <Switch:-list> <...>
{
  local act=${1-}
  act="${act:+$(str_globstripcl "$act" "-")}" || return
  : "${act:=list}"
  test $# -eq 0 || shift
  local lk=${lk:-:context}:files:-$act
  case "$act" in ( c|check ) ;; * ) context_sh_files --check; esac
  case "$act" in
    ( a|all )
        context_files
      ;;
    ( c|check )
        context_sh_files --check-global &&
        context_sh_files --check-local
      ;;
    ( check-global )
        local files
        : "$(context_files)" &&
        mapfile -t files <<< "$_" &&
        TODO
      ;;
    ( check-local )
        # TODO: use statusdir or other to go over unique names
        test ! -e .meta/stat/index/context.list ||
            $LOG warn "$lk" "Should not have context.list" ;;
    ( c-a|count-all )
        wc -l <<< "$(context_files)"
      ;;
    ( e|enum )
        local cached=${CTX_CACHE:?}/context-file-includes.tab
        context_files_cached "$cached" &&
        cat "$cached"
      ;;
    ( f|find ) # XXX: get look path
        files_existing ".meta/stat/index/{context,ctx}{,-*}.list"
      ;;
    ( l|ls|list )
        context_sh_files -all && context_sh_files -find
      ;;
    ( sc|sed-script )
        #preproc_resolve_sedscript "" "$CTX_TAB"
        preproc_expand_1_sed_script "" "$CTX_TAB"
        echo "$sc"
      ;;
    ( tab|ids )
        local cached=${CTX_CACHE:?}/context-file-ids.tab
        context_files | os_up_to_date "$cached" || {
          context_files | while read -r context_tab
          do echo "$(context_file_attributes id) $context_tab"
          done >| "$cached" || return
        }
        cat "$cached"
      ;;

    ( * ) $LOG error "$lk" "No such action" "$act"; return 67 ;;
  esac
}

context_sh_path ()
{
  local act=${1-}
  act="${act:+$(str_globstripcl "$act" "-")}" || return
  : "${act:=list}"
  test $# -eq 0 || shift
  local lk=${lk:-:context}:path:-$act
  case "$act" in
    ( s|short )
        out_fmt=list cwd_lookup_path .
      ;;

    ( * ) $LOG error "$lk" "No such action" "$act" 127 ;;
  esac
}
context_sh_path__libs=sys

context_sh_shell () # ~ <Switch:-user> ~ [-i] [-l] [-c "<Command...>"] [<Shell-args...>]
{
  local switch=${1-}
  switch="${switch:+$(str_globstripcl "$switch" "-")}" || return
  : "${switch:=user}"
  local lk=${lk:-:context}:shell:-$switch

  user_script_ bases
  echo shell foo
  exit $?

  lib_load user-script-htd || return
  case "${switch##-}" in
    ( user-scripts )
        scripts=$(user_script_list_scripts | user_script_filter_userdirs)
        wc -l <<< "$scripts"
      ;;
    ( executable-scripts )
        scripts=$(user_script_list_scripts)
        wc -l <<< "$scripts"
      ;;
    ( count-shell-lib-lines )
        locate -b '*.lib.sh' |
                user_script_unique_names_count_script_lines
      ;;
    ( count-shell-script-lines )
        {
            user_script_list_scripts &&
            locate -b '*.sh'
        } | user_script_filter_userdirs |
                user_script_unique_names_count_script_lines
      ;;
    ( s|short )
      ;;
    ( * ) $LOG error "$lk" "No such action" "$switch" 127 ;;
  esac
}
context_sh_shell__libs=user-script-htd

context_sh_status () # ~
{
  local act=${1-}
  act="${act:+$(str_globstripcl "${act-}" "-")}" || return
  : "${act:=short}"
  test $# -eq 0 || shift
  local lk=${lk:-:context}:status:-$act
  case "$act" in
    ( i|info )
            stderr echo "Main file: ${CTX_TAB:-(unset)}"
            stderr echo "Main Cache file: ${CTX_TAB_CACHE:-(unset)}"
            stderr echo "File count: $(context_sh_files c-a)"
        ;;
    ( s|short )
            script_part=files user_script_load groups &&
            context_sh_files check
            $LOG info "$lk" "Files check" E$? $? || return
            wc -l $(context_sh_files -a)
        ;;

    ( * ) $LOG error "$lk" "No such action" "$act"; return 67 ;;
  esac
}

context_sh_tags__libs=context
context_sh_tags () # ~ <Switch:-list> <...>
{
  local act=${1-}
  act="${act:+$(str_globstripcl "${act-}" "-")}" || return
  : "${act:=list}"
  test $# -eq 0 || shift
  local lk=${lk:-:context}:tags:-$act
  case "$act" in
    ( for )
        contexttab_related_tags "${2:-}" && echo $tag_rel
        ;;
    ( list )
        context_tags_list ;;

    ( * ) $LOG error "$lk" "No such action" "$act" 67
  esac
}


## User-script parts

#context_sh_name=foo
#context_sh_version=xxx
context_sh_maincmds="entries files help list path shell status short version"
context_sh_shortdescr='Provide context entities and relations based on tags'

# Not using shell aliases in this script because they are a pain. But I wonder
# if they could make below setup a bit nicer.

context_sh_aliasargv ()
{
  case "$1" in
      ( e|entries ) shift; set -- context_sh_entries "$@" ;;
      ( l|list ) shift; set -- context_sh_entries -l "$@" ;;
      ( s|short ) shift; set -- context_sh_status --short ;;
      ( f|files ) shift; set -- context_sh_files "$@" ;;
  esac
}

context_sh_loadenv ()
{
  user_script_loadenv || return
  shopt -s nullglob || return
  user_script_baseless=true \
  script_part=${1#context_sh_} user_script_load groups || {
      # E:next means no libs found for given group(s).
      test ${_E_next:?} -eq $? || return $_
    }
  # Fallback if no group/libs defined for given cmd-name is to load base lib
  user_script_initlibs "${base//.*}" || return
  lk="$UC_LOG_BASE" &&
  $LOG notice "$lk:loadenv" "User script loaded" "[-$-] (#$#) ~ ${*@Q}"
}

context_sh_unload ()
{
  shopt -u nullglob
}


# Main entry (see user-script.sh for boilerplate)

test -n "${uc_lib_profile:-}" || . "${UCONF:?}/etc/profile.d/bash_fun.sh"
uc_script_load user-script

! script_isrunning "context.sh" || {
  export UC_LOG_BASE="${SCRIPTNAME}[$$]"
  user_script_load defarg || exit $?
  # Default value used if argv is empty
  script_defcmd=short
  user_script_defarg=defarg\ aliasargv
  # Resolve aliased commands or set default
  eval "set -- $(user_script_defarg "$@")"
  script_run "$@"
}
