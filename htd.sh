#!/usr/bin/env bash
# Created: 2014-12-17

## Htdocs: work in progress 'daily' shell scripts

htd_src=$_

#set -o posix
set -euETo pipefail

# Remove DEBUG and other log control vars from exported env
us-env -r us:boot.screnv

version=0.0.4-dev # script-mpe

# Generic load/unload for subcmd

htd_inputs="arguments prefixes options"
htd_outputs="passed skipped error failed"

htd_subcmd_load ()
{
  # -- htd box load insert sentinel --
  local scriptname_old=$scriptname; export scriptname="htd-subcmd-load[$$]"

  sh_include debug-exit

  main_subcmd_func "$subcmd" || true # Ignore, check for function later
  c=1 ; shift

  # Default-Env upper-case: shell env constants (see str-{,v}word)
  local upper=true title=false

  ! "${DEBUG:-false}" || {
    : "${PWP:=$(pwd -P)}"
    ! "${DIAG:-false}" || {
      stderr declare -p PWD CWD EWD PWP
    }
    [[ ${CWD?} = "${_}" ]] || warn "Current path seems to be aliased ($CWD)"
  }

  default_env EDITOR vim || debug "Using EDITOR '$EDITOR'"
  default_env FIRSTTAB 50
  default_env GitVer-Attr ".version-attributes"

  #test -n "$stdio_0_type" -a  -n "$stdio_1_type" -a -n "$stdio_2_type" ||
  #    stderr error "stdio lib should be initialized" 1

  # Check stdin/out are t(ty), unless f(file) or p(ipe) set interactive mode
  test -t 0 -a -t 1 && interactive_io=1 || interactive_io=0
  default_env Choice-Interactive $interactive_io

  # Assume a file or pipe on stdin means batch-mode and data-on-input available
  test -t 0 && has_input=0 || has_input=1
  #test "$stdio_0_type" = "t" && has_input=0 || has_input=1
  default_env Batch-Mode $has_input

  # Get project dir and version-control system name
  vc_getscm
  { test -n "${scm-}" && go_to_dir_with ".$scm"
  } && {
    # $localpath is the path from the project base-dir to the CWD
    localpath="$(normalize_relative "$go_to_before")"
    # Keep an absolute pathref for project dir too for libs not willing to
    # bother with or specify super-project refs, local name nuances etc.
    projdir="$(pwd -P)"
  } || {
    export localpath='' projdir=''
  }

  local lpwd=$PWD
  # Find workspace super-project, and then move back to this script's CWD
  go_to_dir_with .cllct/local.id && {

    # Workspace is a directory of projects, or a super project on its own.
    workspace=$(pwd -P)
    # Prefix is a relative path from the workspace base to the current projects
    # checkout.
    prefix="$(normalize_relative "$go_to_before")"
    test -z "$prefix" && stderr error "prefix from go-to-before '$go_to_before'" 1
    test "$prefix" = "." || {

      # Add a little warning our records are incomplete
      grep -qF "$prefix"':' .projects.yaml || {
        warn "No such project prefix '$prefix'"
      }
      test "$verbosity" -ge 5 &&
      $htd_log info "htd:load" "Workspace '$workspace' -> Prefix '$prefix'" >&2
      cd "$lpwd"
    }
  } || {
    $htd_log warn "htd:load" "No local workspace" >&2
    cd "$lpwd"
  }

  # NOTE: other per-dir or project vars are loaded on a subcommand basis, e.g.
  # run flag 'p'.

  # TODO: clean up git-versioning app-id
  test -n "${APP_ID:-}" -o ! -e .app-id || read -r APP_ID < .app-id
  test -n "${APP_ID:-}" -o ! -e "${GITVER_ATTR-}" ||
      APP_ID="$(get_property "$GITVER_ATTR" "App-Id")"
  test -n "${APP_ID:-}" -o ! -e .git ||
      APP_ID="$(basename "$(git config "remote.$vc_rt_def.url")" .git)"

  # TODO: go over above default-env and see about project-specific stuff e.g.
  # builddir and init parameters properly

  # Default locations for user-workspaces
  projectdirs="$(echo ~/project ~/work/*/)"

  test -e table.sha1 && R_C_SHA3="$(wc -l < table.sha1)"

  stdio_type 0
  test -t 0 && {
    rows=$(stty size|awk '{print $1}')
    cols=$(stty size|awk '{print $2}')
  } || {
    rows=32
    cols=79
  }

  test -n "${htd_tmp_dir-}" || htd_tmp_dir="$sys_tmp"
  test -n "$htd_tmp_dir" || stderr error "htd_tmp_dir load" 1
  main_isdevenv || {
    #rm -r "${htd_tmp_dir:?}"/*
    test "$(echo $htd_tmp_dir/*)" = "$htd_tmp_dir/*" || {
      rm -r ${htd_tmp_dir:?}/*
    }
  }

  test -n "${htd_session_id-}" || { htd_session_id=$(htd__uuid) || return; }

  # Process subcmd 'run' flags, single letter code triggers load/unload actions.
  # Sequence matters. Actions are predefined, or supplied using another subcmd
  # attribute. Action callbacks can be a first class function, or a string var
  # with the actual callback-function name.
  main_var flags "$baseids" flags "${flags_default:=""}" "$subcmd"
  test -z "$flags" -o -z "$DEBUG" || stderr debug "Flags for '$subcmd': $flags"
  for x in $(echo $flags | sed 's/./&\ /g')
  do
    case "$x" in

    A ) # 'argsv' callback gets subcmd arguments, defaults to opt_arg.
    # Underlying code usually expects env arguments and options set. Maybe others.
    # See 'i'. And htd_inputs/_outputs env.
        test -n "$options" -a -n "$arguments" ||
            stderr error "options/arguments env paths expected" 1
        local htd_subcmd_argsv
        main_var htd_subcmd_argsv $base "" argsv $subcmd
        func_exists "$htd_subcmd_argsv" || {
          htd_subcmd_argsv="$(eval echo "\${$htd_subcmd_argsv-}")"
          # std. behaviour is a simmple for over the arguments that sorts
          # '-' (hyphen) prefixed words into $options, others into $arguments.
          test -n "$htd_subcmd_argsv" || htd_subcmd_argsv=opt_args
        }
        $htd_subcmd_argsv "$@"
      ;;

    a ) # trigger 'argsv' attr. as argument-process-code
        local htd_args_handler
        main_var htd_subcmd_argsv $base "" argsv $subcmd
        case "$htd_args_handler" in

          arg-groups* ) # Read in '--' separated argument groups, ltr/rtl
            test "$htd_args_handler" = arg-groups-r && dir=rtl || dir=ltr

            local htd_arg_groups
            main_var htd_arg_groups $base "" arg-groups $subcmd

            # To read groups from the end instead,
            test $dir = ltr \
              || { set -- "$(echo "$@" | words_to_lines | reverse_lines )"; }
            test $dir = ltr \
              || htd_arg_groups="$(words_to_lines $htd_arg_groups | reverse_lines )"

            for group in $htd_arg_groups
            do
                while test $# -gt 0 -a "$1" != "--"
                do
                  echo "$1" >>$arguments.$group
                  shift
                done
                shift

              test -s $arguments.$groups || {
                local htd_defargs
                main_var htd_defargs $base "" defargs-$group $subcmd
                test -z "$htd_defargs" \
                  || { echo $htd_defargs | words_to_lines >>$arguments.$group; }
              }
            done
            test -z "$DEBUG" || wc -l $arguments*

          ;; # /arg-groups*
        esac
      ;; # /argv-handler

    e ) # env: default/clear for env
        local htd_subcmd_env=$(main_value htd env "" $subcmd)
        test -n "$htd_subcmd_env" ||
          stderr error "run 'e': $subcmd env attr is empty" 1
        eval $htd_subcmd_env
        stderr info "1. Env: $(var2tags $(echo $htd_subcmd_env | sed 's/=[^\ ]*//g' ))"
      ;;

    f ) # failed: set/cleanup failed varname. See 'I' for other I/O files
        export failed=$(setup_tmpf .failed)
      ;;
    H )
        req_htdir || stderr error "HTDIR required ($HTDIR)" 1
      ;;

    I ) # setup (numbered) IO descriptors for htd-input/outputs (requires i before)
        req_vars $htd_inputs $htd_outputs || return
        local fd_num=2 io_dev_path=$(io_dev_path)
        for fd_name in $htd_outputs $htd_inputs
        do
          fd_num=$(( $fd_num + 1 ))
          # TODO: only one descriptor set per proc, incl. subshell. So useless?
          test -e "$io_dev_path/$fd_num" || {
            debug "exec $(eval echo $fd_num\\\>$(eval echo \$$fd_name))"
            eval exec $fd_num\>$(eval echo \$$fd_name)
          }
        done
      ;;

    i ) # io-setup: set all requested io varnames with temp.paths
        #inputs=$(try_value "" inputs htd)
        $LOG debug "" "Exporting inputs '$htd_inputs' and outputs '$htd_outputs'"
        setup_io_paths -$subcmd-${htd_session_id}
      ;;

    l ) lib_require package context &&
      sh_include subcommand-libs || return ;;

    m )
        # TODO: Metadata blob for host
        metadoc=$(statusdir.sh assert)
        exec 4>$metadoc.fkv
      ;;

    O ) # 'optsv' callback is expected to process $options from input(s)
        test ! -s "$options" || {
          local htd_subcmd_optsv=$(main_value htd optsv "" $subcmd)
          func_exists "$htd_subcmd_optsv" ||
            htd_subcmd_optsv="${!$htd_subcmd_optsv-}"
          : "${htd_subcmd_optsv:=htd_optsv}"
          : "$(< $options)"
          test -z "$_" || "$htd_subcmd_optsv" "$_"
        }
      ;;

    P )
        local prereq_func
        main_var prereq_func htd pre "" $subcmd && $prereq_func $subcmd
      ;;

    p ) # set (p)ackage -
        # Set package file and id, update. But don't require, see q.
        add_path "${US_BIN?}"/tool/sh/part &&
        package_lib_auto=true sh_run package-require package-init
      ;;

    q | Q ) # request or require package
        test "$x" = "Q" &&
          package_lib_auto=true package_require=true ||
          # test "$x" = "q" &&
            package_lib_auto=true package_require=false

        # Run function, sourcing package-init part first if not defined
        sh_run package-require package-init
      ;;

    r ) # register package - requires 'p' first. Sets PROJECT Id and manages
        # cache updates for subcommand data.

        # TODO: query/update stats?
      ;;

    t ) # more terminal tooling: load shell and init
        test "${shell_lib_load-}" = "0" || lib_require shell || return
        shell_lib__init
      ;;

    S )
        # Get a path to a storage blob, associated with the current base+subcmd
        S=$(try_value "${subcmd}" S htd)
        test -n "$S" \
          && status="$(setup_stat .json "" "${subcmd}-$(eval echo $S)")" \
          || status="$(setup_stat .json)"
        exec 5>$status.pkv
      ;;

    x ) # ignores, exludes, filters
        htd_load_ignores
      ;;

    * ) stderr error "No such run option ($subcmd): $x" 1 ;;

    esac
  done

  # load extensions via load/unload function
  for ext in $(try_value "${subcmd}" load htd || true)
  do
    htd_load_$ext || warn "Exception during loading $subcmd $ext"
  done

  scriptname=$scriptname_old
}

htd_subcmd_unload ()
{
  local scriptname_old=$scriptname; export scriptname=htd-unload
  local unload_ret=0

  test -z "$flags" -o -z "$DEBUG" || stderr debug "Flags for '$subcmd': $flags"
  for x in $(echo $flags | sed 's/./&\ /g')
  do case "$x" in

    I )
        local fd_num=2
        for fd_name in $htd_outputs $htd_inputs
        do
          fd_num=$(( $fd_num + 1 ))
          #eval echo $fd_num\\\<\\\&-
          eval exec $fd_num\<\&-
        done
        eval unset $htd_inputs $htd_outputs
        unset htd_inputs htd_outputs
      ;;

    i ) # remove named IO buffer files; set status vars
        clean_io_lists $htd_inputs $htd_outputs
        htd_report $htd_outputs || unload_ret=$?
      ;;

    P )
        local postreq_func
        main_var postreq_func htd post "" $subcmd && $postreq_func $subcmd
      ;;

    r )
        # Report on scriptnames and associated script-lines provided in $HTD_TOOLSFILE
        jsotk.py -O yaml --pretty dump - < $report
      ;;

    S )
        exec 5<&-
        test -s $status || echo '{}' >$status
        test ! -s $status.pkv \
          || {
            cat $status.pkv
            jsotk.py update --pretty $status $status.pkv
            rm $status.pkv
          }
        test ! -e $status.pkv || rm $status.pkv
        unset status
      ;;

  esac; done

  test -e "${failed:-}" && {
    clean_failed || unload_ret=1
  }

  for var in $(try_value "${subcmd}" vars htd || true)
  do
    eval unset $var
  done
  test -n "$htd_tmp_dir" || stderr error "htd_tmp_dir unload" 1
  #test "$(echo $htd_tmp_dir/*)" = "$htd_tmp_dir/*" \
  #  || warn "Leaving HtD temp files $(echo $htd_tmp_dir/*)"
  unset htd_tmp_dir

  scriptname=$scriptname_old
  return $unload_ret
}



# Misc. load functions


htd_load_ignores()
{
  # Initialize one IGNORE_GLOBFILE file.
  ignores_lib__load
  test -n "$IGNORE_GLOBFILE" -a -e "$IGNORE_GLOBFILE" ||
      stderr error "expected $base ignore dotfile" 1
  lst_init_ignores
  lst_init_ignores "" ignore
  #lst_init_ignores .names
  #match_load_table vars
}


# Static help echo's


htd__usage()
{
  htd_usage
}

htd_usage()
{
  echo "$scriptname.sh Bash/Shell script helper"
  echo 'Usage: '
  echo "  $scriptname <cmd> [<args>..]"
  echo ""
  echo "Possible commands are listed by help-commands or commands. "
  echo
  echo "See also: docs, todo"
}
htd__help_commands()
{
  echo 'Commands: '
  echo '  home                             Print htd dir.'
  echo '  info                             Print vars.'
  echo '  mk|make                          Run make (in htd dir).'
  echo '  st|stat                          Run make stat.'
  echo '  sys                              Run make sys.'
  echo '  edit-today                       Run htd today and start editor.'
  echo '  today [<prefix> [<ext>]]         Create symlinks of the format $PREFIX/{today,tomorrow,yesterday}.rst -> %Y-%m-%d.rst'
  echo ''
  echo 'Virtuals: '
  echo '  vbox-start <name>                Start headless VBoxVM for VM UUID with name in VBoxVM table. '
  echo '  vbox-suspend <name>              Suspend VBoxVM. '
  echo '  vbox-reset <name>                Reboot VBoxVM. '
  echo '  vbox-stop <name>                 Stop VBoxVM. '
  echo '  vbox-list                        List known and unknown VMs. '
  echo '  vbox-running                     List running VMs. '
  echo '  vbox-info [<name>]'
  echo ''
  echo '  lists [opts]                     List all lists. '
  echo '  tasks [<list>..]                 List tasks in lists'
  echo '  new-task <list> <title>          Add task to list with title'
  echo '  task-note <list> <num>           Edit notes of task in the $EDITOR'
  echo '  task-title <list> <num> [<title>]'
  echo '                                   Get or update title of task'
  echo '  done <list> <num>                Toggle task completed status'
  echo '  todo                             '
  echo ''
  echo 'Networking'
  echo '  wol <host>                       Send wol to mac for host from WOL table.'
  echo '  mac                              List ARP table: hwaddr for clients (once) connector to LAN. '
  echo ''
  echo 'File Versioning'
  echo '  git-remote [repo]                List all names remotely, or give the SSH url for given repo. '
  echo '  git-init-remote [repo]           Initialze remote bare repo if local path is GIT project'
  echo '  git-remote-info                  Show current ~/.conf/git/remotes/* vars.'
  echo '  git-files [REPO...] GLOB...      Look for file (pattern) in repositories'
  echo '  git-grep                         See htd help git-grep'
  echo ''
  echo 'Working tree utils'
  echo '  check-names [. [<tags>]]         Check names in path, according to tags.'
  echo '  list-paths [-d|-f|-l] [.|<dirpath]'
  echo '                                   List all paths, including dirs. '
  echo '  test-name <path>                 Test filename for unhandled characters. '
  echo '  find-name <path|localname>       TODO: Given (partial) path, try to find the file using find.  '
  echo '  update                           Fill checksums tables for all local files. TODO: find out what there is to know about file using settings, other commands, ext. tooling & services. And trigger resolve'
  echo '  '
  echo 'Rules'
  echo '  resolve                          XXX based on data and settings, pre-process and mark all files ready for commit, and bail on any irregularities. '
  echo '  commit                           XXX record metadata according to htd settings/commands. Commit is only a success, if the entire tree is either clean or ignored. '
  echo '  show-rules [<path>]              tabulate all rules that would apply to path'
    echo '  run-rules [<path>]               (re-)run rules on path'
  echo '  add-rule <pattern> <functions>|<script> '
  echo '                                   Add either function and inline script to run for every path matching pattern. '
  echo ''
  echo 'Working tree metadata'
  echo '  ck-init                          Initialize new checksum table'
  echo '  ck-consolidate [.|<path>]        TODO: integrate metadata from all metafiles (see ck-metafile)'
  echo '  ck-metafile <path>               TODO: integrate metadata from .meta/.rst/.sha1sum/etc.'
  echo ''
  echo 'Working tree checksum metadata [CK_TABLE=./]'
  echo "  ck-table [ck|md5|sha1] <path>    Tell if checksum exists for file, don\'t validate or update"
  echo '  ck-table-subtree [ck|md5|sha1] <path> '
  echo '                                   Like ck-table, but this takes a partial path starting at the root level and returns the checksum records for files below that'
  #echo '  ck-check [ck|md5|sha1]           Iterate table, move lines with non-existant paths to .missing table'
  #echo '  ck-fix [.|<path>]                TODO: If path exists, look for duplicates using ck-find-content and move this path to .duplicates marking it to be resolved interactively'
  #echo '                                   Or if path is missing, try find-name to find new location. If still missing, look for any copy using ck-find-content and move current entry to table .duplicate on success, or .gone on failure'
  #echo '  ck-check-missing [ck|md5|sha1]   TODO: see ck-clean; iterate .missing table, and call ck-fix. Move checksum to .gone if file stays missing'
  #echo '  ck-purge [|missing|duplicate|gone] TODO: drop missing-paths from indicate tables'
  #echo '  ck-dedup <path>                  With no path given, iterate the duplicate table. Otherwise deduplicate content, using given path as preferred location. '
  #echo '  ck-find-content <path>           TODO: Given path, try find-name or checksum tables and annex-backend to find copies and give all alternate locations. '
  echo '  ck-update [ck|md5|sha1] (<path>) Iterate all files, and create checksum table records for unknown files'
  echo '  ck-drop [ck|mk5|sha1] <path>     Remove row for given path from checksum table'
  echo '  ck-validate [ck|md5|sha1]        Verify each file by generating and comparing its checksum'
  echo '  ck-cksum [TABLE]                 check file size and cksum'
  echo '  ck-prune                         Drop non-existant paths from table, copy to .missing'
  echo '  ck-clean [ck|md5|sha1]           TODO: iterate .gone table, and call ck-fix. Move gone checksum if file stays missing'
  echo '  ck-metafile                      TODO: consolidate meta files'
  echo '  ck-torrent TORRENT               Check torrent download'
  echo ''
  echo 'System'
  echo '  ls-volumes                       Go over local online disks, see that '
  echo '                                   services symlinks are in place'
  echo ''
  echo 'Other commands: '
  other_cmds
}
other_cmds()
{
  echo '  -E|edit-main                     Edit this script.'
  echo '  -e|edit                          Edit a local document or script.'
  echo '  alias                            Show bash aliases for this script.'
  echo '  -h|help                          Give a combined usage, command and docs. '
  echo '  docs                             Echo documentation (for CWD). '
  echo '  commands                         Echo this comand description listing.'
  echo "  usage                            List all commands. "
  echo "  info                             List env info. "
  echo "  files                            List file used by htd. "
  echo '  mk|make                          Run make (in htd dir).'
  echo '  vt|edit-today                    '
  echo '  n|edit-node ID TAGS              '
  echo '  nnl|edit-note-nnl ID TAGS        '
  echo '  nen|edit-note-en ID TAGS         '
}


# Help (sub)commands:

htd__help_files()
{
  echo "Files"
  echo ""
  echo "    From config settings:"
  echo "  $vbox_names (\$vbox_names)"
  echo "  $wol_hwaddr (\$wol_hwaddr)"
  echo ""
  echo "    From CWD:"
  echo "  ./TODO.list"
  echo "  ./table.names"
  echo "  ./invalid.paths"
  echo "    TODO: uses path .git/.."
  echo "    TODO: paths used by matchbox"
  echo ""
  echo "    Temporary left after exec:"
  echo "  /tmp/gtasks-\$list-\$num-note"
  echo ""
  echo "    Config files"
  echo "  ~/.conf/etc/git/remotes/\$HTD_GIT_REMOTE.sh"
  echo "  ~/.conf/user/rules/\$host.sh"
  echo ''
  echo 'See dckr for container commands and vc for GIT related. '
}


htd_man_1__commands="List all commands"
htd__commands()
{
  choice_global='' choice_all=true std__commands
}
htd_grp__commands=std

htd__libs_raw()
{
  locate_name $base
  note "Raw lib routine listing for '$fn' script"
  dry_run='' box_list_libs "$fn"
}
htd_grp__libs_raw=std

htd__libs()
{
  locate_name $base
  note "Script: '$fn'"
  box_lib "$fn"
  note "Libs: '$box_lib'"
}
htd_grp__libs=std

htd_man_1__man='Access to built-in help strings

Man sections:
  1. (user) commands and tools
  2. System calls: OS plumbing, ie. kernel entry points, see syscalls(2)
  3. Library Fuctions: libc, libm, librt etc.
  4. Devices and special files
  5. File formats, protocols, and corresponding structs
  6. Games, screensavers
  7. Miscellenea (overviews, conventions, charsets, file hierarchy, misc.)
  8. SysAdmin and privileged commands and tools, daemons and isolated agents,
     hardware related; emulation, virtualization

  L. math library functions
  N. tcl functions

See also man-pages(7) and (linux.die.net)[https://linux.die.net/man/] on manual organization.
'
htd_spc__man='[Section] Id'
htd__man()
{
  std_man "$@"
}
htd_grp__man=std


htd_man_1__help="Echo a combined usage, command and docs. See also htd man and
try-help."
htd_spc__help="-h|help [<id>]"
htd__help()
{
  note "Listing all commands, see usage or composure"

  test -z "${1-}" || {
    # local cmd=$1 subcmd= subcmd_alias= subcmd_group=
    main_subcmd_alias "$1" && set -- $subcmd
    helpcmd_group="$( main_value "$baseids" "grp" "" "$1" )"
    test -z "$helpcmd_group" || {
      main_subcmd_func_load $_ || return
    }
  }

  std_help "$@"
}
htd_als___h=help
htd_als____help=help
htd_grp__help=std


htd_als___V=version
htd_als____version=version
htd_flags__version=p
htd_grp__version=std

htd_grp__output_formats=main
htd_grp__info=main

htd_grp__env_info=env
htd_grp__show=env
htd_grp__home=env


#htd__diagnostics
htd_man_1__doctor='Diagnose setup for deeper problems'
htd__doctor()
{
  test -n "$package_pd_meta_tasks_document" -a -n "$package_pd_meta_tasks_done" && {
    true
    #map=package_pd_meta_ package_sh tasks_document
    #map=package_pd_meta_ package_sh tasks_document tasks_done

  } || stderr warning "Missing todo/done.txt env"

  stderr info "Looking for empty files..."
  subcmd=find-empty htd__find_empty ||
      stderr ok "No empty files" && stderr warnning "Empty files above"

  # Go over named paths, see if there are any checks for its contexts
  # TODO: check prefixes state @Diagnostics
  #test -e "$ns_tab" && {

  #  info "Looking for contexts with 'checks' method..."
  #  fixed_table $ns_tab SID CONTEXTS | while read vars
  #  do
  #    eval local "$vars"
  #    upper=true str_vword vid "$SID"
  #    echo $vid

  #  done
  #} || warn "No namespace table for $hostname"

  prefix_names | while read -r prefix_name
  do
    base_path="$(eval echo \"\$$prefix_name\")"
    note "$prefix_name: $base_path"
  done
}


htd_man_1__fsck='Check file contents with locally found checksum manifests

Besides ck-validate and annex-fsck, look for local catalog.yml to validate too.
'
htd_flags__fsck=il
htd__fsck()
{
  note "Running: ck_tab='*' htd ck..."
  # Go over local cksum/filename table files
  ck_tab='*' htd__ck || return $?

  note "Running checksums from all catalogs..."
  # Look for catalogdocs, go over any checksums there too
  ck_run_catalogs || return $?

  test -e .sync-rules.list && {

    note "Checking synchronized annex.."
    # Use sync-rules to mark annex (sub)repos as fsck-enable/disable'd
    subcmd=annex-fsck htd__annex_fsck || return $?

  } || {

    # Look for and fsck local annex as last step
    vc_getscm || return 0
    vc_fsck || return
    test -d "$scmdir/annex" && {
        note "Checking local annex.."
        git annex fsck . || return
    } || true
  }
}
htd_libs__fsck=ck-htd\ htd-meta\ catalog
htd_als__file_check=fsck


htd_man_1__make='Go to HTDIR, make target arguments'
htd__make()
{
  req_dir_env HTDIR
  cd $HTDIR && make "$@"
}
htd_of__make=list
htd_flags__make=p
htd_als__mk=make


htd_grp__expand=main
htd_grp__edit_main=main


htd__ls_main_files()
{
  default_env columnize 1
  {
    for scr in $scriptpath/*.sh
    do
      fnmatch "*.inc.sh" "$scr" && continue
      fnmatch "*.lib.sh" "$scr" && continue
      test -x "$scr" || continue
      basename $scr
    done
  } | {
    trueish "${columnize-}" && column_layout || cat
  }
}


htd_man_1__edit_local='Edit an existing local file, or abort.

TODO: The search term must match an existing component, or set grep/glob mode
to edit the first file.
'
htd_spc__edit_local="-e|edit [-g|--grep] [--glob] <search>"
htd_flags__edit_local=iAO
htd__edit_local()
{
  test -n "$1" || error "search term expected" 1
  case "$1" in
    # NEW
    sandbox-jenkins-mpe | sandbox-mpe-new )
        cd $UCONF/vagrant/sandbox-trusty64-jenkins-mpe
        $EDITOR Vagrantfile
        return $?
      ;;
    treebox-new )
        cd $UCONF/vagrant/
        $EDITOR Vagrantfile
        return $?
      ;;
  esac

  local paths=$PWD
  #doc_path_args

  #find_paths="$(doc_find_name "$1")"
  #grep_paths="$(doc_grep_content "$1")"
  grep_paths="$(git grep -l "$1")"
  test -n "$find_paths" -o -n "$grep_paths" \
    || error "Nothing found to edit" 1

  case "$EDITOR" in
      # Execute search for Id, after editor opens.
      vim ) evoke="$evoke -c \"/$1\"" ;;
  esac
  eval $EDITOR $evoke $find_paths $grep_paths
}
htd_als__edit=edit-local
htd_als___e=edit-local



htd_man_1__volume='See htd volumes'
htd_man_1__volumes='Volumes

  volumes list - list volume paths
  also: ls-vol[umes]|list-volumes

  volumes check
  id DIR
'
htd_spc__volumes='volumes [--(,no-)catalog] [CMD]'
htd_env__volumes="catalog=true"
htd_of__volumes=list
htd_flags__volumes=eiAO
htd_grp__volumes=volume-htd\ disk
htd__volumes()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  test -n "${1-}" || set -- list
  case "$1" in

    list ) shift ; htd_list_volumes "$@" ;;
    check ) shift ; htd_check_volumes "$@" ;;
    path?tab ) shift ; htd_path_names "$@" ;;
    treemap ) shift ; htd_volumes_treemap "$@" ;;

    id ) shift
        get_cwd_volume_id "$1"
      ;;

    * ) error "? '$*'" 1 ;;
  esac
}

htd_als__ls_vol=volumes\ list
htd_als__ls_volumes=volumes\ list
htd_als__list_volumes=volumes\ list


htd_man_1__copy='Copy script from other project. '
htd_spc__copy='copy Sub-To-Script [ From-Project-Checkout ]'
htd__copy() # Sub-To-Script [ From-Project-Checkout ]
{
  test $# -gt 0 -a -n "${1-}" || return
  test -n "${2-}" || set -- "$1" $HOME/bin
  test -e "$2/$1" || {
    error "No Src $1 at $2" 1
  }
  test -e "$1" && {

    vimdiff "$1" "$2/$1" || return $?
  } || {
    local dir="$(dirname "$1")"
    test -z "$dir" || mkdir -vp $dir
    cp $2/$1 $1
    xsed_rewrite 's/Id:/From:/g' $1
    test ! -e .versioned-files.list || {
      echo "# Id: $(basename "$PWD")/" >> $1
      grep -F "$1" .versioned-files.list ||
        echo $1 >> .versioned-files.list
      git-versioning update
    }
    $EDITOR $1
  }
}



# Local or global context flow actions

htd__wf__libs=ctx-base,context,context-uc

htd_flags__current=fql
htd_libs__current=$htd__wf__libs\ htd-tasks
htd__current()
{
  test $# -gt 0 || set -- ${package_lists_contexts_default:?}
  # XXX: Old htd-wf
  #htd_wf_ctx_sub current "$@"
  # TODO: see context-run
  lib_init &&
  set -- $(context_class_names "$@") &&
  local ctx &&
  context_add "$@" &&
  shift &&
  for cn
  do
    $ctx.switch-class ctx "$cn" &&
    $ctx:current ||
    sys_astat -eq ${_E_not_found:?} && continue ||
      return
  done
}


htd_man_1__check='Update status

Run diagnostics for CWD and system.

- Show tags for which list buffers exist
- Check file names
- Check file contents (fsck, cksum)
'
htd_flags__check=fpqil
htd_libs__check=$htd__wf__libs\ htd-check
htd__check()
{
  htd_wf_ctx_sub check "$@"
}

htd_als__chk=check


htd_libs__init=$htd__wf__libs
htd__init () # ~ <@<Tag-ref>>
{
  htd_wf_ctx_sub init "$@"
}
htd_flags__init=ql


htd__list()
{
  htd_wf_ctx_sub list "$@"
}
htd_flags__list=ql
htd_libs__list=list\ htd-list\ src-htd\ context


htd_man_1__status='Quick context status

Per host, cwd info
'
htd_als__st=status
htd_als__stat=status
htd_flags__status=lq
htd_libs__status=package\ sys-htd\ htd-list\ htd-tasks\ ctx-base\ htd-prefix\ context
htd__status()
{
  htd_wf_ctx_sub status "$@"
}


htd_man_1__process='Process each item in list.  '
htd_spc__process='process [ LIST [ TAG.. [ --add ] | --any ]'
#htd_env__process=''
#htd_flags__process=epqlA
htd_flags__process=pql
htd_libs__process=htd-list\ htd-tasks\ ctx-base\ context
#htd_argsv__process=htd_argsv_list_session_start
htd_als__proc=process
htd_grp__process=proc

htd__process()
{
  htd_wf_ctx_sub process "$@"
}


htd_flags__update=q
htd__update()
{
  htd_wf_ctx_sub update "$@"
}


#htd_man_1__update_status='Update quick status'
#htd_als__update_stats=update-status
#htd_flags__update_status=f

#htd_als__update=update-checksums
#htd_als__update=update-status

#htd_flags__status_cwd=fSm

htd__volume_status()
{
  htd__metadirs
}

# TODO: htd project status
htd__project_status()
{
  htd__metadirs
}

htd__workdir_status()
{
  htd__metadirs
  finfo.py --metadir .meta
}


htd_flags__build=pq
htd__build()
{
  htd_wf_ctx_sub build "$@"
}


htd_man_1__clean='Look for things to clean-up in given directory

TODO: in sequence:
- check (clean/sync) SCM dir, keep bare repo in /srv/$scm-local
- existing archive: check unpacked and cleanup unmodified files
- finally (on archive itself, other files left),
  use `htd find` to find existing copies and de-dupe
'
htd_flags__clean=pq
htd__clean()
{
  htd_wf_ctx_sub clean "$@"
}


htd_flags__test=pq
htd__test()
{
  htd_wf_ctx_sub test "$@"
}


htd_man_1__metadirs='TODO find packages, .meta dirs, DB client/query local-bg

    volume-status
    project-status
    workdir-status
'
htd__metadirs()
{
  test -n "$1" || set -- "$PWD"
  while test $# -gt 0
  do
    test -e $1/.meta && echo $1/.meta
    test "$p" != "/" || break
    p=$1
    shift
    test "$p" = "$(cd "$p"; pwd -P)" && {
      set -- "$(dirname "$p")"
    } || {
      set -- "$(dirname "$(cd "$p";pwd -P)")" "$(dirname "$p")"
    }
  done
}


htd_man_1__projects='Local project checkouts
  list
    TODO

  project-status
    See htd context
'
htd__projects()
{
  test -n "$1" || set -- list
  case "$1" in

    list ) shift
        cd $PDIR && find -L . -type d -maxdepth 1 \
            -exec test -e {}/.git \; -and -print | cut -c3-
      ;;

  esac
}


htd_man_1__project='Deal with project at local dir, see also projects.

  exists - check that project is vendored
  create - TODO: create new project
  checkout - TODO: create new checkout for project
  new - TODO: create new project
  init - TODO: check that project is vendored

  sync - TODO: ensure project is entirely available at vendor
  update - TODO: update from vendor(s)
  scm - TODO: init/update repo links
  releases - List github releases

Vendoring consists of selecting a vendor and using it as remote repository for
the project.
'
htd_flags__project=p
htd__project()
{
  test -n "$1" || set -- info
  case "$1" in

    create ) shift ; htd_project_create "$@" ;;
    new ) shift ; htd_project_new "$@" ;;
    checkout ) shift ; htd_project_checkout "$@" ;;
    init ) shift ; htd_project_init "$@" ;;
    sync ) shift ; htd_project_sync "$@" ;;
    update ) shift ; htd_project_update "$@" ;;
    exists ) shift ; htd_project_exists "$@" ;;

    scm ) # Find local SCM references, add as remote for current/given project
        shift ; test -n "$1" || set -- "$PWD"
        test -d "$1" || error "Project directory missing '$1'" 1
        local name="$(basename "$1")"
        (
          cd "$1"
          vc_getscm || return 1
          # TODO: add remotes, either
          # bare personal project /srv/<scm>-*/<project>.<scm>
          # annex checkout /srv/annex-*/<project>
          # checkout at /src/<site>/<user>/<project> and /srv/project-local
          echo "/srv/$scm-"*"/$name.$scm" | tr ' ' '\n' | while read p ; do
            test -e "$p" || continue
            echo TODO: check for remote $p
          done
        )
      ;;

    check ) shift ; test -n "$1" || set -- "$PWD"
        test -d "$1" || error "Directory expected '$1'" 1
        htd__srv check-volume "$1" || return 1
        htd__project exists "$1" || return 1
        htd__project scm "$1" || return 1
      ;;

    releases ) shift ; test -z "$*" || error "Unexpected arguments"
        htd_project_releases
      ;;

    * ) error "? 'project $*'" 1 ;;
  esac
}
htd_load__project=htd-project\ htd-src


htd__go()
{
  test -n "$APP_ID" || error "App-Id required" 1
  test -n "$1" || set -- compile
  case "$1" in

    c | compile ) shift
        docker run --rm \
          -e CGO_ENABLED=true \
          -e COMPRESS_BINARY=true \
          -v "$(pwd -P):/src" \
          centurylink/golang-builder
        du -hs $APP_ID*

        htd__go exec "$@"
      ;;

    x | x-compile ) shift
        test -n "$os" || os="$(uname -s | tr 'A-Z' 'a-z')"
        test -n "$BUILD_GOOS" || BUILD_GOOS="$os"
        test -n "$BUILD_GOARCH" || {
            case "$mach" in

                x86_64 ) BUILD_GOARCH="amd64" ;;
                * ) BUILD_GOARCH="$arch" ;;
            esac
        }
        docker run --rm \
          -e CGO_ENABLED=true \
          -e COMPRESS_BINARY=true \
          -e BUILD_GOARCH="$BUILD_GOARCH" \
          -e BUILD_GOOS="$BUILD_GOOS" \
          -v "$(pwd -P):/src" \
          centurylink/golang-builder-cross
        du -hs $APP_ID*

        test -x "$APP_ID-$os-$BUILD_GOARCH" ||
            error "Golang x-compile failed to $os/$BUILD_GOARCH" 1

        test ! -e "./$APP_ID" || rm "./$APP_ID"
        ln -s "$APP_ID-$os-$BUILD_GOARCH" "$APP_ID"

        htd__go exec "$@"
      ;;

    exec ) shift
        ./$APP_ID "$@"
      ;;

    dockerize ) shift
        test -z "$1" || img_tag=$1
        test -n "$img_tag" || img_tag=dotmpe/$APP_ID
    test -e Dockerfile || { { cat <<EOM
FROM scratch
COPY $APP_ID /
ENTRYPOINT ["/$APP_ID"]
EOM
    } > Dockerfile; note "Placed default dockerfile"; }
        docker run --rm \
          -e CGO_ENABLED=true \
          -e COMPRESS_BINARY=true \
          -v "$(pwd -P):/src" \
          -v /var/run/docker.sock:/var/run/docker.sock \
          centurylink/golang-builder \
          $img_tag || return $?
        du -hs $APP_ID*
        note "Done $img_tag with $APP_ID"
      ;;

    * ) error "? 'go $*'" 1
      ;;
  esac
}


htd_man_1__validate='Validate JSON/YAML against JSON-Schema '
htd_spc__validate='validate DOC [SCHEMA]'
htd__validate()
{
  htd_schema_validate "$@"
}
htd_grp__validate=schema


htd_man_1__validate='Validate local package metadata aginst JSON-Schema '
htd_flags__validate_package=p
htd__validate_package()
{
  set -- $scriptpath/schema/package.yml $scriptpath/schema/package.json
  test $2 -nt $1 || jsotk yaml2json --pretty "$@"
  htd_schema_validate .package.json "$2"
}

htd_man_1__validate_pdoc='Validate given projectdoc schema. '
htd__validate_pdoc()
{
  htd_schema_validate "$1" $scriptpath/schema/projectdir.yml
}


htd_flags__tools=fl
htd_spc__tools="tools (<action> [<args>...])"
htd__tools()
{
  test -n "${1-}" || set -- list
  subcmd_default=list subcmd_prefs=${base}_tools_ try_subcmd_prefixes "$@"
}
htd_grp__tools=tools

# FIXME: htd_als__install="tools install"
#htd_als__install=install-tool

htd_of__installed='yml'
htd_als__installed=tools\ installed

htd_als__outline=tools\ outline


# XXX: setup env before main?
htd_man_1__script='Get/list scripts in HTD_TOOLSFILE. Statusdata is a mapping
of scriptnames to script lines. See Htd run and run-names for package scripts. '
htd_spc__script="script"
htd_flags__script=pSmr
htd_S__script=\$package_id
htd__script()
{
  # Force regeneration for stale data
  test $status -ot $HTD_TOOLSFILE \
    && { rm $status || true; }

  # FIXME: statusdir tools script listing
  rm $status
  # Regenerate status data for this script if not available
  test -s $status || {
    scripts="$( jsotk.py keys -O lines $HTD_TOOLSFILE tools )"

    for toolid in $scripts
    do
      note "Scriptlines for '$toolid': "

      jsotk.py -q path --is-str $HTD_TOOLSFILE tools/$toolid && {
        scriptline="$(jsotk.py path -O py $HTD_TOOLSFILE "tools/$toolid")"
        note "Line: '$scriptline'"
        echo "tools/$toolid/scripts/${toolid}[]=$scriptline" 1>&5
        echo "scripts[]="$toolid 1>&5
        continue
      }

      # If object, our tool can either be a required package a named script
      # using oner And/or incidentally be the same name for an executable.
      (
        jsotk.py -q path --is-obj $HTD_TOOLSFILE tools/$toolid ||
        jsotk.py -q path --is-new $HTD_TOOLSFILE tools/$toolid
      ) && {

        jsotk.py objectpath -O lines $HTD_TOOLSFILE '$..*[@.scripts."'$toolid'"]' \
          | while read -r scriptline
          do
            note "Line: '$scriptline'"
            echo "tools/$toolid/scripts/${toolid}[]=$scriptline" 1>&5
          done

        #echo "scripts[]="$toolid 1>&5
        continue
      }

      jsotk.py -q path --is-list $HTD_TOOLSFILE tools/$toolid && {
        jsotk.py items -O py $HTD_TOOLSFILE "tools/$toolid" \
          | while read -r scriptline
          do
            note "Line: '$scriptline'"
            echo "tools/$toolid/scripts/${toolid}[]=$scriptline" 1>&5
          done
        echo "scripts[]="$toolid 1>&5
        continue
      }
    done
  }

  # TODO: generate script to run. This keeps a JSON blob associated with
  # htd-script and the script-mpe package ($HTD_TOOLSFILE). Gonna want a JSON
  # for shell scripts/aliases/etc. Also validation.

  #    while test $# -gt 0
  #    do
  #      jsotk.py objectpath -O py $HTD_TOOLSFILE '$..*[@.scripts."'$1'"]'
  #      shift
  #    done
  report=$status
}


htd__man_5__htdignore_merged='Exclude rules used by `htd find|edit|count`, compiled from other sources using ``htd init-ignores``. '

htd_man_1__init_ignores='Write all exclude rules to .htdignores.merged

TODO: see ignores, list and vs.
'
htd__init_ignores()
{
  htd_init_ignores
}


htd_man_1__relative_path="Test for relative path"
htd__relative_path()
{
  # TODO: maybe build relative path from 1 arg and cwd, or two args
  # see also mkrlink. Also clean up.
  #x_re "${1:0:2}" '[\.\/]*' && echo ok || echo nok
  htd_relative_path $1
  r=$?
  echo relpath=$relpath
  exit $r
}
htd_man_1__relpath="Alias for 'relative-path'"
htd_als__relpath='relative-path'


# XXX: add config files
htd__man_5_table_names=""

htd__test_find_path_locals()
{
  htd_find_path_locals table.names $1
  echo path_locals=$path_locals

  htd_find_path_locals table.names $1 $PWD
  echo path_locals=$path_locals
}


htd_grp__ns_names=prefix
htd_grp__list_local_ns=prefix


# Run a sys-* target in the main htdocs dir.
htd__make_sys()
{
  req_dir_env HTDIR
  cd $HTDIR
  for x in $*
  do
    make system-$x
  done
}

# show/get/add htd shell aliases
htd__alias ()
{
  htd_alias "$@"
}
htd_als__get_alias=alias
htd_als__set_alias=alias
htd_als__show_alias=alias
htd_grp__alias=htd-u-s\ shell-alias


htd_als__vt=journal\ edit-today
htd_als__edit_entry=journal\ edit-entry
htd_als__edit_week=journal\ edit-week

htd_grp__today=cabinet

htd_grp__week_nr=journal
htd_als__week=week-nr
htd_als__wknr=week-nr

htd_grp__this_week=cabinet

htd_grp__journal=journal
htd_als__jrnl=journal

htd_grp__journal_json=journal
htd_als__jrnl_json=journal-json
htd_als__jrnl_j=journal-json

htd_grp__journal_times=journal
htd_als__jrnl_times=journal-times
htd_als__jrnl_t=journal-times
htd_grp__archive_path=cabinet


# TODO: use with edit-local
htd__edit_note()
{
  htd_edit_note "$@"
}
htd_als__n=edit-note
htd_grp__edit_note=cabinet

htd__edit_note_nl()
{
  htd__edit_note "$1" "$2 nl" || return $?
}
htd_als__nnl=edit-note-nl
htd_grp__edit_note_nl=cabinet

htd__edit_note_en()
{
  htd__edit_note "$1" "$2 en" || return $?
}
htd_als__nen=edit-note-en
htd_grp__edit_note_en=cabinet


htd_man_1__main_doc_paths='Print candidates for main document
'
htd__main_doc_paths()
{
  local candidates="$(doc_main_files)"
  test -n "$1" && {
    fnmatch "* $1$DOC_EXT *" " $candidates " &&
      set -- $1$DOC_EXT ||
        error "Not a main-doc $1"

  } || set -- "$candidates"
  for x ; do
    test -e "$x" || continue
    set -- "$x"; break; done
  echo "$(basename "$1" $DOC_EXT) $1"
}
htd_load__main_doc_paths=doc
htd_grp__main_doc_paths=cabinet


# Edit first candidates or set to main$DOC_EXT
htd__main_doc_edit()
{
  # Find first standard main document
  test -n "$1" || set -- "$(htd__main_doc_paths "$1"|{ read tag path;echo $path; })"
  # Or set default
  test -n "$1" || set -- main$DOC_EXT

  # Open edit session, discard unchanged generated file
  local cksum=
  title="$(str_title "$(basename "$(pwd -P)")")"
  htd_rst_doc_create_update $1 "$title" created default-rst
  htd_edit_and_update $1
}
htd_flags__main_doc_edit=p
htd_als__md=main-doc-edit
htd_als___E=main-doc-edit
htd_grp__main_doc_edit=cabinet



### VirtualBox

vbox_names=~/.conf/etc/vbox/vms.sh
htd__vbox()
{
  name=$1
  [ -z "$name" ] && {
    htd__vbox_list
  } || {
    declare $(echo $(cat $vbox_names))
    uuid=$(eval echo \$$name)
    test -n "$uuid" || error "No such vbox VM '$name'" 1
  }
}
htd_grp__vbox=vm

htd__vbox_start()
{
  test -n "$1" || error "VM name required" 1
  htd__vbox $1
  VBoxManage startvm ${uuid} --type headless \
      || error "Headless-start of VM $name" 1 \
      && log "Headless-start of VM $name completed successfully"
}
htd_grp__vbox_start=vm

htd__vbox_start_console()
{
  test -n "$1" || error "VM name required" 1
  htd__vbox $1
  VBoxManage startvm ${uuid} \
      || error "Console-start of VM $name" 1 \
      && log "Console-start of VM $name completed successfully"
}
htd_grp__vbox_start_console=vm

htd__vbox_reset()
{
  test -n "$1" || error "VM name required" 1
  htd__vbox $1
  VBoxManage controlvm ${uuid} reset \
      || error "Reset of VM $name" 1 \
      && log "Reset of VM $name completed successfully"
}
htd_grp__vbox_start_reset=vm

htd__vbox_stop()
{
  test -n "$1" || error "VM name required" 1
  htd__vbox $1
  VBoxManage controlvm ${uuid} poweroff \
      || error "Power-off of VM $name" 1 \
      && log "Power-off of VM $name completed successfully"
}
htd_grp__vbox_stop=vm

htd__vbox_suspend()
{
  test -n "$1" || error "VM name required" 1
  htd__vbox $1
  VBoxManage controlvm ${uuid} savestate \
      || error "Save-state of VM $name" 1 \
      && log "Save-state of VM $name completed successfully"
}
htd_grp__vbox_suspend=vm

htd__vbox_list()
{
  VBoxManage list vms | \
    sed 's/^"\(.*\)"\ {\(.*\)}$/\2 \1/' | while read uuid name
  do
    grep $uuid $vbox_names >> /dev/null || echo unknown $name =$uuid
  done
  cat $vbox_names | \
    grep -Ev '^\s*(#.*|\s*)$'
}
htd_grp__vbox_list=vm

htd__vbox_running()
{
  VBoxManage list runningvms
}
htd_grp__vbox_running=vm

htd__vbox_info()
{
  test -n "$1" && {
    htd__vbox $1
    #2: --details --machinereadable
    VBoxManage showvminfo ${uuid} $2
  } || {
      for sub in intnets bridgedifs hostonlyifs natnets dhcpservers
      do log "Showing $sub"; VBoxManage list $sub; done
  }
}
htd_grp__vbox_info=vm

htd__vbox_gp()
{
  htd__vbox "$1"
  VBoxManage guestproperty enumerate ${uuid}
  #VBoxManage guestproperty get ${uuid} "/VirtualBox/GuestInfo/Net/0/V4/IP"
}
htd_grp__vbox_gp=vm


# Wake a remote host using its ethernet address
wol_hwaddr=~/.conf/etc/wol/hosts-hwaddr.sh
htd__wol_list_hosts()
{
  grep '^[a-zA-Z_][a-zA-Z0-9_]*=' $wol_hwaddr |
      cut -d'=' -f 1 | column
}
htd_grp__wol_list_hosts=box

htd__wake()
{
  [ -z "${1-}" ] && {
    htd__wol_list_hosts
    error "Expected hostname argument" 2
  } || {
    local host=$1
    local $(echo $(read_nix_style_file $wol_hwaddr|sed 's/ # .*$//g'))
    hwaddr=$(eval echo \$$host)
    [ -n "$hwaddr" ] || exit 4
    wakeonlan $hwaddr
    echo ":WOL Host: \`$host <$hwaddr>\`_"
  }
}
htd_grp__wake=box


htd_spc__shutdown='shutdown [ HOST [ USER ]]'
htd__shutdown()
{
  test -n "$1" || error host 1
  test -n "$2" || {
    test -e $UCONF/disk/$hostname-$1.user && {
      set -- "$1" "$(head -n 1 $UCONF/disk/$hostname-$1.user )"
    }
  }
  # Unmount remote disks from local mounts
  test -e $UCONF/disk/$hostname-$1.list && {
    note "Unmounting from local.."
    mounts="$(read_nix_style_file $UCONF/disk/$hostname-$1.list | lines_to_words)"
    sudo umount "$mounts"
  }
  ssh_req $1 $2 &&
  run_cmd "$1" 'sudo shutdown -h +1' &&
  note "Remote shutdown triggered: $1"
}
htd_grp__shutdown=box


htd__ssh_vagrant()
{
  test -d $UCONF/vagrant/$1 || error "No vagrant '$1'" 1
  cd $UCONF/vagrant/$1
  vagrant up || {
    vagrant up --provision || {
      warn "Provision error $?. See htd edit to review Vagrantfile. "
      sys_confirm "Continue with SSH connection?" ||
          note abort 1
    }
  }
  vagrant ssh
}


htd_flags__ssh=f
htd__ssh()
{
  test -d $UCONF/vagrant/$1 && {

    htd__ssh_vagrant "$@"
    return $?
  }

  case "$1" in
    # NEW
    sandbox-jenkins-mpe | sandbox-new )
        id=sandbox-trusty64-jenkins-mpe
        shift
        set -- $id "$@"
        htd__ssh_vagrant "$1"
      ;;

    # TODO: move to vagrants
    sandbox | sandbox-mpe | vdckr | vdckr-mpe )
        cd $UCONF/dckr/ubuntu-trusty64-docker-mpe/
        vagrant up
        vagrant ssh
      ;;

    # OLD vagrants
    treebox | treebox-precise | treebox-mpe )
        cd $UCONF/vagrant/treebox-hashicorp-precise-mpe
        vagrant up
        vagrant ssh
      ;;
    trusty )
        cd $UCONF/vagrant/ubuntu-trusty64
        vagrant up
        vagrant ssh
      ;;

    # TODO: harbour aliases in private space shomehow
    dandy-home )     htd ssh dandy "export CS=$CS; cd ~/ && bash -i " ;;
    dandy-conf )     htd ssh dandy "export CS=$CS; cd ~/.conf && bash -i " ;;
    dandy-bin )      htd ssh dandy "export CS=$CS; cd ~/bin && bash -i " ;;
    dandy-htd )      htd ssh dandy "export CS=$CS; cd ~/htdocs && bash -i " ;;

    # @Home
    * )
        # Try for minimally a minute to wake/contact remote
        test -n "$retries" || retries=6
        ret=0
        htd__detect_ping $1 || {
          while true
          do
            test $retries -gt 0 ||
              stderr warn "Unable to contact '$1' in allotted retries" 1
            stderr note "Trying to wake up $1.."
            htd wake $1 || stderr error "wol error $?" 1
            retries=$(( $retries - 1 ))
            sleep 16
            stderr info "Testing ping to '$1'..."
            htd__detect_ping $1 && break
          done
        }
        test -n "$2" &&
          note "Host '$1' is online, trying command '$2'.." ||
          note "Host '$1' is online, trying ssh connect.."

        ssh -t $1 "export CS=$CS; $2" || ret=$?
        test -n "$2" && {
          test -z "$ret" -o "$ret" = "0" &&
            note "Command $1: '$2' completed OK" ||
            error "Command $1: '$2' failed exiting $ret" 2
        } || {
          test -z "$ret" -o "$ret" = "0" &&
            note "SSH connection to '$1' completed and closed" ||
            error "SSH connection to '$1' exited $ret" 1
        }
      ;;

    * )
        error "No remote $1"
      ;;
  esac
}
htd_grp__ssh=box


htd_man_1__up='Test all given hosts are online and answering'
htd__up()
{
  test -n "$1" || set -- ping
  case "$1" in

    ping ) shift ; htd__detect_ping "$@" || return $? ;;

    aping|ansping ) shift ;
        test -z "$*" || stderr error "No arguments expected" 1
        ansible all -m ping || return $?
      ;;

    * ) error "'$1'? (htd up $*)" 1 ;;
  esac
}
htd_flags__up=f
htd_als__detect=up
htd_grp__up=box


htd_man_1__detect_ping='Test all given hosts are online, answering to PING'
htd__detect_ping() # Hosts...
{
  test -n "$failed" || error "detect-ping expects failed env" 1
  while test $# -gt 0
  do
    ping -qt 1 -c 1 $1 >/dev/null &&
      stderr ok "$1" || echo "htd:$subcmd:detect-ping:$1" >$failed
    shift
  done
  test ! -s "$failed"
}
htd_flags__detect_ping=f
htd_grp__detect_ping=box


# Simply list ARP-table, may want something better like arp-scan or an nmap
# script
htd__mac()
{
  arp -a
}
htd_grp__mac=box


htd_man_1__random_str="Print a web/url-save case-sensitive Id of length. It is
 base64 encoded, so multiples of 3 make sense as length, or they will be padded
 to length. "
htd_spc__random_str='(rndstr|random-str) [12]'
htd_als__rndstr=random-str
htd__random_str()
{
  test -n "$1" || set -- 12 # Set default htd:random-str length
  python2 -c "import os, base64;print base64.urlsafe_b64encode(os.urandom($1))"
}
htd_grp__random_str=box


htd_man_1__txt='todo.txt/list.txt util
'
htd__txt()
{
  test $# -gt 0 || set -- ""
  case "$1" in

    todotxt-list ) shift
        txt.py todolist todo.txt
      ;;

    to-json ) shift
        txt.py meta-to-json "$1"
      ;;

    number | enumerate ) shift
        offset=0
        for list
        do
          enum_nix_style_file "$list" | while read num line
          do
            echo "$(( $offset + $num )) $line"
          done
          offset=$(( $offset + $(line_count "$list" ) ))
        done
      ;;

    * ) error "'$1'? 'htd txt $*'" 1 ;;
  esac
}


htd_grp__tasks=tasks
htd_grp__tasks_edit=tasks
htd_grp__tasks_hub=tasks
htd_grp__tasks_process=tasks
htd_grp__tasks_buffers=tasks
htd_grp__tasks_scan=tasks
htd_grp__tasks_tags=tasks
htd_grp__tasks_add_dates=tasks

# Todo.txt stuff
htd_grp__todo=todo
htd_grp__todotxt=todo
htd_grp__todo_gtasks=todo
htd_grp__build_todo_list=todo

# Google tasks
htd_grp__gtasks_lists=gtasks
htd_grp__gtasks=gtasks
htd_grp__new_task=gtasks
htd_grp__gtask_note=gtasks
htd_grp__gtask_title=gtasks
htd_grp__done=gtasks


htd_grp__urlstat=htd-urls\ statusdir\ urlstat\ stattab\ match-htd\ date-htd
htd_grp__urls=htd-urls
htd_grp__save_url=urls


htd_grp__find=htd-code
htd_als___f=find

htd_grp__github=htd-code

htd_grp__src=htd-code

htd_grp__git=htd-code
htd_grp__gitremote=htd-code
htd_grp__git_init_local=htd-code
htd_grp__git_init_remote=htd-code
htd_grp__git_drop_remote=htd-code
htd_grp__git_init_version=htd-code
htd_grp__git_missing=htd-code
htd_grp__git_init_src=htd-code
htd_grp__git_list=htd-code
htd_grp__git_files=htd-code
htd_grp__git_grep=htd-code
htd_grp__gitrepo=htd-code
htd_grp__git_import=htd-code
htd_grp__github=htd-code


htd_man_1__file='TODO: Look for name and content at path; then store and cleanup.

    newer-than
    older-than
    newest
    mtype
    mtime
    mtime-relative
    size PATH
      Bytesize
    info PATH
      Use magic tests to describe file format
    mime PATH
      Try to give MIME content-type by using magic tests
    drop PATHS...
      Remove contents/path, wether untracked or GIT / Annexed tracked.
    find-by-sha2list
    find-by-sha256e

Given path, find matching from storage using name, or content. On match, compare
and remove path if in sync.
'
htd_flags__file=fl
htd__file()
{
  test -n "$1" || set -- info
  subcmd_prefs=${base}_file_\ file_ try_subcmd_prefixes "$@"
}
htd_als__test_name=file\ test-name
htd_als__file_info=file\ format
htd_als__file_modified=file\ mtime
htd_als__file_born=file\ btime
htd_als__file_mediatype=file\ mtype
htd_als__file_guessmime=file\ mtype
htd_als__drop=file\ drop
htd_als__filesize_hist=file\ size-histogram
htd_als__filenamext=file\ extensions
htd_als__filestripext=file\ stripext

htd_als__wherefrom=wherefrom



htd__content()
{
  note "TODO: go over some ordered CONTENTPATH to look for local names.."
}


htd_man_1__date='
    relative TIMESTAMP
    fmt-dawin TAGS STRF
    fmt DATESTR STRF
    microtime
    iso
    autores DATESTR
    parse DATESTR [FMT]
    tstat
    pstat TSTAT
    touchdt [FILE | TIMESTAMP]
    touch [FILE | TIMESTAMP FILE]
    week [help|iso|iso-w.y|iso-w.Y]
'
htd_flags__date=fl
htd_libs__date=date\ htd-date
htd__date()
{
  test -n "${1:-}" || set -- relative
  subcmd_prefs=date_\ htd_date_\ fmtdate_ try_subcmd_prefixes "$@"
}


htd_grp__vcflow=vcflow

htd_als__gitflow_check_doc=vcflow\ check-doc
htd_als__gitflow_check=vcflow\ check
htd_als__gitflow=vcflow\ status
htd_als__feature_branches=vcflow\ list-features


htd_grp__source=src
htd_grp__function=src
htd_grp__diff_function=src
htd_grp__sync_function=src
htd_grp__diff_functions=src
htd_grp__sync_functions=src
htd_grp__diff_sh_lib=src

htd_als__diff_func=diff-function




htd__find_empty()
{
  test -n "$1" || set -- .
  test -d "$1" || error "Dir expected '$?'" 1
  stderr info "Compiling ignores..."
  local find_ignores="$(ignores_find $IGNORE_GLOBFILE)"
  test -n "$find_ignores" || fail "Cannot compile find-ignores"
  eval find $1 -false $find_ignores -o -empty -a -print
}

htd__find_empty_dirs()
{
  test -n "$1" || set -- .
  test -d "$1" || error "Dir expected '$?'" 1
  stderr info "Compiling ignores..."
  local find_ignores="$(ignores_find $IGNORE_GLOBFILE)"
  test -n "$find_ignores" || fail "Cannot compile find-ignores"
  eval find $1 -false $find_ignores -o -empty -a -type d -a -print
}

htd_als__largest_files=find-largest
htd__find_largest() # Min-Size
{
  test -n "$1" || {
    set -- 15
    note "Set min-size to $1MB"
  }
  # FIXME: find-ignores
  test -n "$find_ignores" || {
    test -n "$2" && find_ignores="$2" || find_ignores="-not -iname .git "
  }
  eval find . \\\( $find_ignores \\\) -a -size +${MIN_SIZE}c -a -print | head -n $1
}

htd_als__filesize=file\ size


# XXX: a function to clean directories
# TODO: hark back to statusdir?
# TODO: notice deprecation marks
htd_flags__check_files=
htd__check_files()
{
  log "Looking for unknown files.."

  pwd=$PWD
  cruft=$sys_tmp/htd-$(echo $pwd|tr '/' '-')-cruft.list
  test ! -e "$cruft" || rm $cruft
  eval find . $find_ignores -o -print \
    | while read p
    do

      htd__test_name "$p" >> /dev/null || {
        warn "Unhandled characters: $p"
        continue
      }

      [ -L "$p" ] && {
        BE="$(dirname "$p")/$(readlink "$p")"
        [ -e "$BE" ] || {
          warn "Skip dead symlink"
          continue
        }
        SZ="$(filesize "$BE")"
      } || {
        SZ="$(filesize "$p")"
      }

      if test -d "$p" -a -n "$(htd__expand $p.{zip,tar{.gz,.bz2}})"
      then
        stderr info "Skipping unpacked dir $p"
        for ck in ck sha1 md5
        do
          htd__ck_table_subtree $ck "$p" | while read p2
          do
            htd__ck_table $ck "$p2" > /dev/null && {
              #htd__ck_drop $ck "$p"
              warn "FIXME: Dropped $ck key for $p"
            }
          done
        done
        continue
      fi

      test "$SZ" -ge "$MIN_SIZE" || {
        warn "File too small: $p"
        echo $p >>$cruft
        continue
      }

    done

  test -s "$cruft" && {
    note "Cruft in $pwd: $(line_count $cruft) files"
  } || true

}


# TODO: rename helper, group in lib. Or drop for renameutils?

htd_git_rename()
{
  $PREFIX/bin/matchbox.py rename "$1" "$2" |
  grep -Ev '^\s*(#.*|\s*)$' |
  while read file_old file_new
  do
    $cmd_pref git mv "$file_old" "$file_new"
  done
}

htd__rename_test()
{
  cmd_pref="echo"
  htd__rename "$@"
}

htd__rename()
{
  from_pattern="$1"
  to_pattern="$2"
  #$(echo $2 | sed 's/@\([A-Z0-9_]*\)/${\1}/g')
  shift 2
  test -z "$1" && {
    htd_git_rename "$from_pattern" "$to_pattern"
  } || {
    { for p ; do echo $p; done ; echo -e "\l"; } |
    htd_git_rename "$from_pattern" "$to_pattern"
  }
}


htd__ignore_names()
{
  test -n "$IGNORE_GLOBFILE" || error "IGNORE_GLOBFILE" 1
  lst list "$@"
}

htd_load__check_names="ignores"
htd__check_names()
{
  test -n "$IGNORE_GLOBFILE" || error "IGNORE_GLOBFILE" 1
  local find_ignores="$(ignores_find $IGNORE_GLOBFILE.names | lines_to_words)"
  test -z "$find_ignores" || find_ignores="-false $find_ignores -o"

  test -z "$1" && d="." || { d="$1"; shift 1; }
  test -z "$1" && valid_tags="" || valid_tags="$1"
  test "${d: -1:1}" = "/" && d="${d:0: -1}"

  test -z "$valid_tags" &&
    log "Looking for unmatched paths in $d" ||
    log "Validating $d, using valid patterns $valid_tags"

  {
    eval find $d " $find_ignores \( -type l -o -type f \) -a -print "
    echo "\l"
  } | matchbox.py check-names $valid_tags
}


htd__fix_names()
{
  local path_regex names_tables names_table
  req_cdir_arg "$1"
  match_grep_pattern_test "$path" || return 1
  path_regex="$p_"
  match_name_tables "$path"
  #
  htd_find_path_locals table.names $PWD
  names_tables=$path_locals
  for names_table in $names_tables
  do
    cat $names_table | grep -Ev '^(#.*|\s*)$' | while read match pattern tag
    do
      echo "$match" | grep '^'$path_regex > /dev/null || continue
      match_name_pattern "$pattern"
      for p in $match
      do
        echo "$p" | grep '^'"$grep_pattern"'$' >> /dev/null && {
          test -n "$tag" && {
            echo matched $tag $p
          } || {
            echo ok $p
          }
        } || test -n "$tag" || {
          echo mismatch $p
        }
      done
    done
  done
}
htd_load__fix_names=match


# XXX: cleanup
htd_host_arg()
{
  test -z "$1" && host=$1 || host=${hostname}
}

# TODO: pre-process file/metadata
htd__resolve()
{
  set --
}

htd_man_1__update_checkout='Checkout/update GIT version for this $scriptpath

Without argument, pulls the currently checked out branch. With env `push` turned
on, it completes syncing with the remote by returning the branch with a push.

If "all" is given as remote, it expands to all remote names.
'
htd_env__update_checkout='push'
htd_spc__update_checkout='update [<commit-ish> [<remote>...]]'
htd__update_checkout()
{
  test -n "$1" ||
      set -- "$(cd $scriptpath && git rev-parse --abbrev-ref HEAD)" "$@"
  test -n "$2" || set -- "$1" "$vc_rt_def"
  test "$2" = "all" &&
    set -- "$1" "$(cd $scriptpath && git remote | tr '\n' ' ')"

  # Perform checkout, pull and optional push
  test -n "$push" || push=0
  (
    cd $scriptpath
    local branch=$1 ; shift ; for remote
    do
      # Check argument is a valid existing branch on remote
      git checkout "$branch" &&
      git show-ref | grep '\/remotes\/' | grep -qF $remote'/'$branch && {
        git pull "$remote" "$branch"
        trueish $push && git push "$remote" "$branch" || true
      } || {
        warn "Reference $remote/$branch not found, skipped" 1
      }
    done
  )
}


htd__push()
{
  test -n "$1" || error "domain ID expected"
  local id=$(domain id) current_branch=$( git name-rev --name-only HEAD )
  domain id $1
  {
    git push $(git config branch.${current_branch}.remote) $current_branch
  } || error "Unable to push"
  domain id $id
}


htd__recommit()
{
  test -z "$1" || {
    id=$(domain id)
    domain id $1
  }
  current_branch=$( git name-rev --name-only HEAD )
  {
    git add -u &&
      git ci --amend --reset-author &&
        git push $(git config branch.${current_branch}.remote) $current_branch
  }
  test -z "$1" || domain id $id
}


htd_man_1__push_commit="Commit modified files and push to default remote. "
htd_spc__push_commit='(pci|push-commit)
    [ [ --id ID ] [ --amend ] [ --all | --no-update ] ]
    [ --no-push | [ --any ] [ --every ] ]                 MSG [REMOTES]
'
htd__push_commit()
{
  # Argument handling
  # FIXME: could do away with half of subcmd code with better dependent env defaults
  {
    trueish "$verbose" || trueish "$DEBUG"
  } &&
    note "id=$id update=$update amend=$amend all=$all push=$push any=$any every=$every"
  # FIXME: losing quotation marks!!
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  test -n "$1" && { not_trueish "$amend" || {
      error "Commit message given and --amend '$*'" 1
    }; } || { not_falseish"$amend" || {
      error "Commit message expected" 1
    }; }

  sh_isset update && {
    falseish "$update" && {
      trueish "$update" || error "unexpected value for update '$update'" 1
    } || {
      sh_isset all && {
        falseish "$all" || error "--update and add --all are exclusive" 1
      }
    }
  } || {
    trueish "$all" && update=0 || update=1
  }
  sh_isset push || push=true

  ## push-commit subcommand routine
  # Add modified files, or add all untracked files
  trueish "$update" && {
    git add -u || error "Failed adding modified files??" 1
  } || {
    trueish "$all" && {
      git add -a . || error "Unable to add all untracked" 1
    }
  }

  # Commit to local repository
  test -z "$id" || {
    # Switch ID if needed
    current_id="$(domain id)"
    test -n "$current_id" || error "Cannot get current domain ID" 1
    test "$current_id" = "$id" || {
      domain id $id || error "Domain ID switch from '$current_id' to '$id' failed" 1
    }
  }
  trueish "$amend" && {
    test -n "$id" && git_ci_f="--reset-author --amend" || git_ci_f="--amend"
  }
  test -z "$1" || git_ci_f="$git_ci_f -m \"$1\""
  eval git commit $git_ci_f &&
    note "Committted ('$git_ci_f')" ||
    error "Commit '$git_ci_f' failed" 1
  test -z "$id" || {
    domain id $current_id
  }
  shift

  # Distribute commit(s)
  current_branch=$( git name-rev --name-only HEAD )
  # More argument handling first
  test -n "$1" && {
    trueish "$every" ||
      warn "Remotes given and --every, remotes are not overriden"
  } || {
    trueish "$every" && {
      set -- $(git remote)
    } || {
      trueish "$push" && {
        # Set remote for current tracked branch
        set -- $(git config branch.${current_branch}.remote ||
          error "Unable to determine tracking remote of $current_branch branch" 1)
      }
    }
  }
  # Perform push
  trueish "$push" && {
    for remote
    do
      trueish "$any" && {
        git push --all $remote || failed "$base:$subcmd:push-any:$remote"
      } || {
        git push $remote $current_branch || failed "$base:$subcmd:push:$remote"
      }
    done
  } || {
    test -n "$1" || {
      warn "Remotes given but --no-push is on [$*]"
    }
  }
}
htd_flags__push_commit=iIAO
htd_als__pci=push-commit


htd_man_1__push_commit_all="Commit tracked files and push to everywhere. Add --any to push all branches too."
htd_spc__push_commit_all="(pcia|push-commit-all) [ --id ID ] [ --any ] MSG"
htd__push_commit_all()
{
  update=true every=true \
  htd__push_commit "$@"
}
htd_flags__push_commit_all=iIAO
htd_als__pcia=push-commit-all


htd_grp__cabinet=cabinet


# Move paths into new dir
htd__mkdir() # Dir Paths...
{
  test ! -e "$1" || error new-path 1
  local destd=$1 ; shift
  mkdir -p "$destd"
  while test $# -gt 0
  do
    mv $1 $destd/$1
    shift
  done
}


htd_man_1__record="Retrieve, update or initalize record(s). "
htd_spc__record="record [PATH]"
htd__record()
{
  # TODO: Look at all services with .git or .meta/table
  # Else record locally
  test -e table.sha1 \
    && htd__ck_table sha1 "$1" \
    || {
      touch table.sha1
      htd__ck_update sha1 "$1"
    }
}


## Annex:

htd_spc__save='save [ ( [PREFIX/]ID ) | PATHNAME [DESTPATH] ]'
# Save refs (download locators if not present) to prefix,
# building a full path for each ref from the prefix+ids+filetags.
# $ save "[<prefix>/]<id>" <refs>...
# TODO: define global <prefix> and <id> to correspond with (sets of) path instances
# ie. lookup given prefix and id first, see if it exists.
# XXX: may have lookup lookup. Use -g to override.
# <prefix>
htd__save()
{
  # TODO: fix the old save URL setup
  case "$1" in
    http*|magnet*|mailto* )
        htd__save_tags "$1"
        htd__save_url "$@"
      ;;
    * )
        req_file_arg "$1"
        test -n "$2" -o -d "$2" || error "expected directory argument '$2'" 1
        test -- "$1" "$bp/$bn"
        note "TODO: set target to journal, or cabinet"
        exit 1
        local bp="$(dirname "$1")" bn="$(basename "$1")"
        echo cp $1 $2/$bp/$bn
        echo "# See-Also: $new_ctxid $bp/$bn" >>$1
        htd_rewrite_comment Id From $2/$bp/$bn
        echo "# See-Also: $ctxid $bp/$bn" >>$2/$bp/$bn
        local new_ctxid=""
      ;;
  esac
}
htd_grp__save='urls annex'


htd_man_1__tags='
  bookmarks

XXX: see also
  task-hub
        List tags for which local task buffers or backend/proc scripts exists.
'
htd__tags()
{
  test -n "$1" || set -- bookmarks
  case "$1" in

    bookmarks ) shift
        width=$(tput cols)
        cols=$(( $width / 16 ))
        bookmarks.py tags "$@" | pr -t -$cols -w $width
      ;;

    nodes )
  test -n "$DBFILE" || DBFILE=~/.bookmarks.sqlite
echo
  sqlite3 $DBFILE <<SQL
    SELECT n2.\`name\`, n1.\`id\` FROM names n2, nodes n1
    JOIN names ON n2.id = n1.id ;
SQL
echo $?
echo
  exit $?
  sqlite3 $DBFILE <<SQL
    SELECT * FROM names_tag ;
SQL
  sqlite3 $DBFILE <<SQL
    SELECT nodes.\`id\`, names.\`name\`
    FROM
      names_tag,
      names,
      nodes
    JOIN names_tag ON names.id = names_tag.id
    JOIN names ON nodes.id = names.id ;
SQL
#  ORDER BY p.time DESC;
      ;;

    * ) error "tags '$*'?" ;;
  esac
}


htd__save_ref()
{
  test -n "$1" || error "tags expected" 1
  tags="$1"

  shift 1
  for ref
  do
    echo TODO: save $ref
  done
}
htd_grp__save_ref=annex


htd_grp__package=package
htd_man_1__ls="List local package names"
htd_als__ls=package\ list-ids

htd_man_1__openurl="Open local package URL"
htd_als__openurl=package\ open-url



htd_man_1__topics='List topics'
htd__topics()
{
  test -n "$1" || set -- list
  subcmd_prefs=${base}_topics_\ topics_ try_subcmd_prefixes "$@"
}
htd_flags__topics=liAOpx
htd_libs__topics=list\ ignores\ package

htd_man_1__list_topics='List topics'
htd_als__list_topics="topics list"



htd_man_1__scripts='Action on local package "scripts".

  scripts names [GLOB]
    List local package script names, optionally filter by glob.
  scripts list [GLOB]
    List local package script lines for names
  scripts run NAME
    Run scripts from package

'
htd_flags__scripts=lpf
htd_libs__scripts='package htd-scripts'
htd__scripts()
{
  test -n "${1-}" || set -- names
  subcmd_prefs=${base}_scripts_ try_subcmd_prefixes "$@"
}

htd_flags__script_opts=iAOpfl
htd_libs__script_opts='package htd-scripts'
htd__script_opts()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  htd__scripts "$@"
}


htd_man_1__run='Run script from local package.y*ml. See scripts (run).'
htd_spc__run='run [SCRIPT-ID [ARGS...]]'
htd_flags__run=iAOpl
htd_libs__run='htd-scripts'
htd__run()
{
  # List scriptnames when no args given
  test -z "${1-}" && {
    note "Listing local script IDs:"
    htd__scripts names
    return 1
  }
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  htd_scripts_run "$@"
}


htd_man_1__list_run="list lines for package script. See scripts (list)."
htd__list_run()
{
  verbose_no_exec=1 htd_scripts_list "$@"
}
htd_flags__list_run=iAOql
htd_libs__list_run='package htd-scripts'


htd_grp__rules=htd-rules
htd_grp__edit_rules=htd-rules
#htd_als__edit_rules='rules edit'
#htd_als__id_rules='rules id'
#htd_als__env_rules='rules id'
htd_grp__period_status_files=htd-rules
htd_grp__run_rules=htd-rules
htd_grp__show_rules=htd-rules
htd_grp__rule_target=htd-rules


htd_man_1__storage=''
htd_spc__storage='storage TAG ACTION'
htd__storage()
{
  test -n "${2-}" || set -- "$1" process
  eval $(package_sh id lists_default)
  test -n "$*" || { set -- $lists_default; note "Setting default tag args '$*'"; }
  while test $# -gt 0
  do
    local scr= cb= be=
    htd__get_backend "$1" store/ $2 || {
      stderr debug "Skipping non-storage '$1'"; shift 2; continue; }
    note "Processing for '$1':"; $cb ; shift 2
  done
}
htd_flags__storage=plA
htd_libs__storage=htd-tasks
htd_argsv__storage=htd_argsv_tasks_session_start
htd_grp__storage=htd-rules


htd__get_backend()
{
  test -n "${2-}" || set -- "${1-}" "store/" "${3-}"
  test -n "${3-}" || set -- "$1" "$2" "stat"
  case "$1" in
    @* ) ctx=$(echo "$1" | cut -c2- ) ; be=at-$ctx
      ;;
    +* ) ctx=$(echo "$1" | cut -c2- ) ; be=in-$ctx
      ;;
    * ) error "get-backend '$1'?" 1 ;;
  esac
  sid=$(str_sid $be)
  scr=$( htd__extensions $2$sid )
  test -n "$scr" || return 1
  cb=$(str_word ${be}__${3}) ; . $scr ; func_exists "$cb"
}
htd_grp__get_backend=htd-rules


htd__extensions()
{
  lookup_test="test -x" lookup_path HTD_EXT $1.sh
}
htd_grp__extensions=htd-rules


htd__tab2csv()
{
  out_fmt=csv htd__table_reformat "$1"
}

htd__tab2json()
{
  out_fmt=json htd__table_reformat "$1"
}

htd__tab2yaml()
{
  out_fmt=yml htd__table_reformat "$1"
}

htd_als__tab_out=table-reformat
htd_of__table_reformat="csv yaml json"
htd__table_reformat()
{
  test -n "$1" || set -- -
  test -n "$fields" || {
    test "$1" != "-" || error "file needed to determine header fields" 1
    local fields="$(fixed_table_hd_ids "$1")"
  }
  test -n "$cutf" || fixed_table_cuthd "$1" "$fields"
  upper=false default_env out-fmt json
  test "$out_fmt" = "csv" && { echo "#"$fields | tr ' ' ',' ; }
  fixed_table "$1" $cutf | while read vars
  do
    set -- $fields ; eval $vars ; case "$out_fmt" in
      yml|yaml|json )
          printf -- "- "
          while test $# -gt 1
          do
            eval printf -- \"$1: \'\$$1\'\\n\ \ \"
            shift
          done
          eval printf -- \"$1: \'\$$1\'\\n\"
          shift
        ;;

      csv )
          while test $# -gt 1
          do
            eval printf -- \"\$$1',"'
            shift
          done
          eval printf -- \"\$$1'\\n"'
          shift
        ;;

      * ) error "Unknown format '$out_fmt'" 1 ;;
    esac
  done | {
    test "$out_fmt" = "json" && jsotk -Iyaml -Ojson - || cat -
  }
}


htd__table()
{
  test -n "$1" || set -- list
  #subcmd_prefs=try_subcmd_prefixes "$@"
  case "$1" in
    fixed-hd ) shift ;     grep_list_head "$@" ;;
    fixed-hd-ids ) shift ; fixed_table_hd_ids "$@" ;;
    fixed-cuthd ) shift ;  fixed_table_cuthd "$@" ;;
    fixed ) shift ; f      ixed_table "$@" ;;
    reformat ) shift;   htd__table_reformat "$@" || return ;;
    * ) error "'$1'? 'table $*'"
      ;;
  esac
}


htd_grp__name_tags_test=meta
htd_grp__name_tags=meta
htd_grp__name_tags_all=meta
htd_grp__update_checksums=meta
htd_grp__ck=meta
htd_grp__ck_add=meta
htd_grp__ck_init=meta
htd_grp__ck_table=meta
htd_grp__ck_table_subtree=meta
htd_grp__ck_update=meta
htd_grp__ck_drop=meta
htd_grp__ck_validate=meta
htd_grp__cksum=meta
htd_grp__ck_prune=meta
htd_grp__ck_consolidate=meta
htd_grp__ck_clean=meta
htd_grp__ck_metafile=meta


htd_grp__exif=media
htd_grp__ck_torrent=media
htd_grp__read_torrents=media\ bittorrent
htd_grp__read_torrent=media\ bittorrent
htd_grp__mp3_validate=media


htd_grp__mux=tmux
htd_grp__tmux=tmux
htd_grp__tmux_resurrect=tmux

htd_als__tmux_list=tmux\ list-sessions
htd_als__tmux_sessions=tmux\ list-sessions
htd_als__tmux_windows=tmux\ session-list-windows
htd_als__tmux_session_windows=tmux\ session-list-windows


htd_man_1__test='Alias for run test TODO: or pd test'
htd_als__test="run test"
#htd_man_1__test="Run PDir tests in HTDIR"
#htd__test()
#{
#  req_dir_env HTDIR
#  cd $HTDIR && projectdir.sh test
#}
htd_als___t=test
#htd_grp__test=projects


htd_man_1__edit_test="Edit all BATS spec-files (test/*-spec.bats)"
htd__edit_test()
{
  $EDITOR ./test/*-spec.bats
}
htd_als___T=edit-test
htd_grp__edit_test=cabinet


htd_man_1__inventory="Edit all inventories"
htd__inventory()
{
  req_dir_env HTDIR
  test -e "$HTDIR/personal/inventory/$1.rst" && {
    set -- "personal/inventory/$1.rst" "$@"
  } || {
    set -- "personal/inventory/main.rst" "$@"
  }
  htd_rst_doc_create_update $1 "Inventory: $1"
  htd_edit_and_update "$@"
}
htd_als__inv=inventory
htd_grp__inventory=cabinet


htd_man_1__inventory_elecronics="Electr(on)ics inventory"
htd__inventory_electronics()
{
  set -- "personal/inventory/components.rst" \
      "personal/inventory/modules.rst" \
      "personal/inventory/hardware.rst" "$@"
  htd_rst_doc_create_update $1
  htd_edit_and_update "$@"
}
htd_als__inv_elec=inventory-electronics
htd_grp__inventory_electronics=cabinet


htd__uptime()
{
  nowts="$($gdate +"%s")"
  s=$(${os}_uptime)
  note "Last reboot: $( fmtdate_relative "$nowts" "$s" )"

  ts_rel_multi "$s" hours minutes seconds
  note "Uptime: $dt_rel"
}

htd_als__runtime=disk\ runtime
htd_als__bootnumber=disk\ bootnumber

htd_grp__disk=disk
htd_grp__disks=disk
htd_grp__disktab=disk
htd_grp__disk_doc=disk
htd_grp__create_ram_disk=disk
htd_grp__check_disks=disk


htd__normalize_relative()
{
  normalize_relative "$1"
}


# Get document part using xpath. See getxl about getting document's XML
htd__getx() # Document XPath-Expr Document-XML
{
  test -n "$1" || error "Document expected" 1
  test -e "$1" || error "No such document <$1>" 1
  test -n "$2" || error "XPath expr expected" 1

  test -n "$3" || set "$1" "$2" "$(du_getxml "$1")"

  xmllint --xpath "$2" "$3"
  rm "$3"
}

htd_grp__doc=doc
htd_grp__count=doc
htd_grp__find_doc=doc
htd_grp__find_docs=doc
htd_als__docs=doc\ list

htd_grp__tpaths=doc
htd_grp__tpath_raw=doc


htd_man_1__xproc='Process XML using xsltproc - XSLT 1.0'
htd__xproc() { htd_xproc "$@" ; }


htd_man_1__xproc2='Process XML using Saxon - XSLT 2.0'
htd__xproc2() { htd_xproc2 "$@" ; }


# TODO: Append definition term to doc
htd__dl_init()
{
  test -n "$1" || error "Document expected" 1
  test -e "$1" || error "Document expected: <$1>" 1
  test -n "$2" || error "Term expected" 1
  htd getx '//*/term[text()="'$2'"]' "$1"
}

# TODO: Add list item beneath definition term
htd__dl_append()
{
  echo
}



# Setup X tcp socket for VS1 containers
htd__xtcp()
{
  socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\"
}


gcal_tab=~/htdocs/personal/google-.tab
htd__man_5_cals_tab="List of Google calendar IDs"

gcal_tab_ids()
{
  if test -n "$1"
  then
    cat $gcal_tab
  else
    grep '\<'$1 $gcal_tab
  fi
}

# List current and upcoming events
htd__events()
{
  test -n "$2" || set -- "$1" "days=3"
  gcal.py --version || return
  read_nix_style_file $UCONF/google/cals.tab | while read calId summary
  do
    note "Upcoming events for '$summary'"
    gcal.py list-upcoming 7 $calId "$2" 2>/dev/null
  done
}

# List upcoming events at any date
htd__upcoming_events()
{
  gcal_tab_ids "$1" | while read calId summary
  do
    note "Upcoming events for '$summary'"
    gcal.py list-upcoming 7 $calId 2>/dev/null
  done
}

# List events of +/- 1day
htd__current_events()
{
  test -n "$2" || set -- "$1" "days=1" "$3" "$4"
  test -n "$3" || set -- "$1" "$2" "days=1" "$4"
  test -n "$4" || set -- "$1" "$2" "$3" "7"

  gcal_tab_ids "$1" | while read calId summary
    do
      note "Current events ($2/$3) for '$summary' ($calId)"
      gcal.py happening-now $7 $calId "$1" "$2" 2>/dev/null
    done
}


htd_man_1__port='List command, pid, user, etc. for open port'
htd__port()
{
  case "${OS_UNAME:?}" in
    Darwin ) ${sudo}lsof -i :$1 || return ;;
    Linux ) ${sudo}netstat -an $1 || return ;;
  esac
}


htd__active='
  files
    TODO: cache set of user-files
'
htd__active()
{
  test -n "$tdata_fmt" && {
    note "Listing files active in '$*'"
  } || {
    tdata_fmt=$TODAY
    note "Listing files active today in '$*'"
  }
  tdate=$(date "$1")

  test -n "$2" || set -- "$1" "$(pwd -P)"
  shift
  test -n "$tdate" || error "formatting date" 1
  touch -t $tdate $(statusdir.sh file recent-paths)
  htd__recent_paths "$@"
}


htd_man_1__ps='Using ps, print properties for the given or current process.
'
htd_spc__ps='ps PID'
htd__ps()
{
  local upper=false
  default_env out-fmt yaml
  default_env pretty 1
  test -n "$1" || set -- $$
  # Cannot parse the headers for fixed-table, other than try sort them out into
  # left and right aligned columns and try to go from there, ie. hardcoding at
  # least half of the set and sniffing the first data row. But even then it
  # still makes it ambigious to parse columns containing whitespace, which
  # ps by default seems to delegate to the last column.
  # So instead, ignore whitespace and make a special case of CMD too, and
  # simply add other values using one subshell each.
  ps -o \
  'sess,sig,sigmask,pri,uid,gid,pid,ppid,cpu,%mem,time,etime,nice,state,tty,command'\
    "$1" | tail -n +2 |
  while read sess sig sigmask pri uid gid pid ppid cpu mempc time etime nice state tty cmd
  do { test "$tty" = "??" && tty= ; cat <<EOM
{"SID": "$sess", "UID": $uid, "GID": $gid, "PID": $pid, "PPID": $ppid, "tty": "$tty", "CPU": $cpu, "MEM": $mempc, "lstart": "$(ps -olstart "$1" | tail -n +2)", "nice": "$nice", "cputime": "$time", "state": "$state", "ELAPSED": "$etime", "CMD": "$cmd", "CWD":"$( lsof -p "$1" | grep cwd | awk '{print $9}')", "priority": $pri, "pending": "$sig", "blocking": "$sigmask"}
EOM
    }
  done | {
    test "$out_fmt" = "yaml" && jsotk json2yaml --pretty - || {
      trueish "$PRETTY" && jsotk dump --pretty - || cat -
    }
  }
}
htd_of__ps='yaml json'


# TODO: open routine ...
htd__open()
{
  test -n "$1" && {
    stderr warn TODO 1
  } || {
    htd__current_paths || return
  }
}

htd_als__c=current-paths
htd_als__of=open-paths
htd_als__lsof=open-paths
htd_als__open_files=open-paths


htd_man_1__current_paths='List open paths for user (belonging to specific processes)'
htd__current_paths() #
{
  htd__shell_cwds | tail -n +2 | awk '{print $9}' | sort -u
}
htd_of__current_paths='list'
htd_als__open_paths=current-paths


htd_man_1__lsof='List CWD for user process'
htd__lsof_cwd() # [User] Cmd-Grep [Cmd-Len]
{
  test -n "${1-}" || set -- $USER "${2-}" "${3-}"
  test -n "${3-}" || set -- $1 "${2-}" "15"
  lsof +c $3 -c $2 -u "$1" -a -d cwd
}

htd__editor_cwds() # User Cmd-Grep Cmd-Len
{
  htd__lsof_cwd "${1-}" '/^('"$EDITOR"')$/x'
}

htd__shell_cwds() # User Cmd-Grep Cmd-Len
{
  htd__lsof_cwd "${1-}" '/^(bash|sh|ssh|dash|zsh)$/x'
}


htd_man_1__open_paths='Lists names of currently claimed by a process.

    dirs
        Print directories only
    files
        Print directories only
    paths
        Print just the directory and fila paths.
    pid-paths
        Print process ID, parent process ID, inode and name.
    info
        Print process ID, parent process ID, command, offset, inode and name.
    details
        Print process ID, parent process ID, command, offset, access mode,
        lock status, device node, descriptor, inode and name.

Open paths (from lsof), even filtered by user, returns 10k paths on my OSX box.
It even lists network file connections. For it to get usable, need to limit
it to known bases.

Also unfortenately, my editor (vim) does not keep the files open, but
instead the swap file. Making identification just a bit more complicated.
And finally, query lsof takes quite a long time, making it completely
unsuited for interactive use.

Because of this, using find -newer is a more efficient way to find paths to
user files. As for open directories, htd prefixes records those based on
current-cwd. Somehow, current-cwd is also significantly faster getting live
data than open-paths lsof invocations.
'
htd__open_paths()
{
  test -n "$1" -a -n "$2" || set -- "paths" "$1"
  test -n "$1" || set -- "paths" "$2"
  test -n "$2" || set -- "paths" "."
  os_isdir "$2" || return $?
  note "Listing open paths for '$2'"
  set -- "$1" "$(cd "$2" && pwd -P)"

  case "$1" in

    paths ) shift ; lsof -F n +D "$1" | grep -v '^p' | cut -c2- | sort -u ;;

    dirs ) shift ; htd__open_paths paths "$1" | filter_dirs - ;;
    files ) shift ; htd__open_paths paths "$1" | filter_files - ;;

    pid-paths ) shift ; lsof -F pRin0 +D "$1" | tr '\0' ' ' ;;

    info ) shift ; lsof -F pRcoin0 +D "$1" | tr '\0' ' ' ;;

    details ) shift ; lsof -F pRcoaldfin0 +D "$1" | tr '\0' ' ' ;;
  esac
}


htd_man_1__open_paths_diff='Create list of open files, and show differences on
  subsequent calls. '
htd_spc__open_paths_diff="open-paths-diff"
htd__open_paths_diff()
{
  export lsof=$(statusdir.sh assert-dir htd/open-paths.lsof)
  export lsof_paths=$lsof.paths
  export lsof_paths_ck=$lsof_paths.sha1

  # Get open paths for user, include only CWD, and with 15 COMMAND chars
  # But keep only non-root, and sh or bash lines, throttle update of cached file
  # by 10s period.
  {
    test -e "$lsof" && newer_than $lsof 10
  } || {
    htd__current_paths >$lsof

    debug "Updated $lsof"
    stderr info "Commands: $(echo $(
        sed 's/\ .*$//' $lsof | sort -u
      ))"

    sed 's/^.*\ //' $lsof | sort -u > $lsof_paths.tmp
  }

  test -e $lsof_paths_ck && {
    sha1sum -c $lsof_paths_ck >/dev/null
  } || {
    sha1sum "$lsof.paths.tmp" > $lsof_paths_ck
    test ! -e $lsof_paths && {
      note "Initialized $(
        sed 's/^\([^\ ]*\).*/\1/g' $lsof_paths_ck | cut -c-11
      )"
    } || {
      note "Updated $(
        sed 's/^\([^\ ]*\).*/\1/g' $lsof_paths_ck | cut -c-11
      )"
      git diff --color $lsof_paths $lsof_paths.tmp | tail -n +6 \
        1>&2
      # XXX: clean-me
      #diff $lsof_paths $lsof_paths.tmp | vim -R -
      #cdiff $lsof_paths $lsof_paths.tmp
    }
    cp $lsof.paths.tmp $lsof.paths
  }

  note "Paths:"
  cat $lsof_paths
}

# List paths newer than recent-paths setting
htd__recent_paths()
{
  test -n "$1" || set -- "$(pwd -P)"
  note "Listing active paths under $1"
  dateref=$(statusdir.sh file recent-paths)
  find $1 -newer $dateref
}


htd_grp__prefixes=prefix
htd_als__prefix=prefixes
htd_als__prefixes_list=prefixes\ list
htd_als__list_prefixes=prefixes\ list
htd_als__prefixes_update=prefixes\ update
htd_als__update_prefixes=prefixes\ update


## Services

htd_man_1__service_list='
List servtab entries, optionally updating
'
htd_of__service_list='text txt list plain'
htd__service_list()
{
  test -n "$service_cmd" || service_cmd=status
  htd_service_env_req
  fixed_table $HTD_SERVTAB UNID TYPE EXP CTX | while read vars
  do
    eval local "$vars"
    DIR=$(echo "$CTX" | awk '{print $1}')
    HTD_SERV_ENV="${CTX:${#DIR}}"
    DIR=$(eval echo "$DIR")
    cd $DIR || {
      error "service $UNID dir missing: '$DIR'"
      continue
    }
    # XXX: interpret recorded
    trueish "$update" || {
      # XXX: nicely formatted stdout $UNID $TYPE $DIR ...
      test -z "$HTD_SERV_ENV" || eval $HTD_SERV_ENV
      # NOTE: Get a bit nicer name.
      # FIXME: would want package metadata. req. new code getting type specific
      # metadata. Not sure yet where to group it.. services, environment.
      #package_get_key "$DIR" $package_id label name id
      : "$(upper=true str_word "$TYPE")_NAME"
      NAME=${!_}
      echo "$UNID: $NAME @$TYPE $(htd_service_status_info "$TYPE" "$EXP") <$DIR>"
      continue
    }
    # XXX: interpret current results
    test "$service_cmd" = status || {
      htd__service $service_cmd "$UNID" "$TYPE" "$DIR" ||
        warn "'$service_cmd' returned $?" 1
      continue
    }
    # XXX: update
    htd__service $service_cmd "$UNID" "$TYPE" "$DIR" && {
      test -z "$EXP" -o "$EXP" = "0" &&
        stderr OK "OK $TYPE $htd_serv_stat_msg [$DIR] ($UNID) "  ||
        warn "Unexpected state 0 for $TYPE [$DIR] ($UNID)"
    } || { E=$?
      test "$E" = "$EXP" && {
        stderr note "Ingored non-zero state $EXP for $TYPE [$DIR] ($UNID)"
      } ||
        stderr fail "Failed $TYPE err $E $htd_serv_stat_msg [$DIR] ($UNID) "
    }
  done
}
htd_als__list_services=service-list


htd__service() # Cmd [ Sid [ Type [ Dir ]]]
{
  test -n "$1" || set -- list
  test -n "$htd_serv_update" || export htd_serv_update=1
  case "$1" in
    info | record )
        test -z "$3" -a -z "$4"
        test -n "$2" && {
          htd_service_record "$2"
        } || {
          echo
        }
      ;;
    reload ) ;;
    status | install | init | start | stop | restart | deinit | uninstall )
        shift
        CTX=$(htd_service_attr "$1" CTX )
        DIR=$(echo "$CTX" | awk '{print $1}')
        HTD_SERV_ENV="${CTX:${#DIR}}"
        DIR=$(eval echo $DIR)
        test -n "$2" -a -n "$3" || {
          set -- $1 $( htd_service_attr "$1" TYPE ) "$DIR"
        }
        htd_service_exists "$@" || {
          trueish "$htd_serv_update" && {
            htd_service_update_record "$@"
          } ||
            return 1
        }
        htd_service_status "$@" || return
        htd_service_update "$@"
      ;;
    list ) test -z "$2" -a -z "$3" -a -z "$4" ;
        echo "#$(grep_list_head "$HTD_SERVTAB")"
        update=0 service_cmd=info htd__service_list
      ;;
    list-info ) test -z "$2" -a -z "$3" -a -z "$4" ;
        update=1 service_cmd=status htd__service_list
      ;;
  esac
}

htd_man_1__audit='Check code heuristics, format. See also bashisms, and doctor.'
htd__audit()
{
  git grep 'while test -n\s*['"'"'"]\$[{]\?[0-9]"' && { # Consider rewriting to $# -gt 0
      stderr error "1."
  } || stderr ok "1. OK"

  git grep 'test -z\s*['"'"'"]\$[{]\?[0-9][^-]"' && { # consider rewriting to test $# -eq 0
      stderr error "2."
  } || stderr ok "2. OK"
}

htd_man_1__bashisms='Scan for bashims in given file or current dir'
htd_spc__bashisms="bashism [DIR]"
htd__bashisms()
{
  test -n "$1" || set -- "."
  f=-srI

  # Scan for bash redirect
  grep $f '\&>' "$@" && {
    note "Bash extension found: '&>...' is a shortcut for '>... 2>&1'"
  }

  # Scan for bash, ksh etc. keyword
  grep $f '\<source\|declare\|typeset\>' "$@" && {
    note "Bash extension found"
  }
}


htd_clean_scm()
{
  vc_getscm "$1" && {
    note "Found SCM in $1"
    ( cd "$1" &&
    vc_clean )
  }
}


htd__clean_empty_dirs()
{
  htd__find_empty_dirs "$1" | while read p
  do
    rmdir -p "$p" 2>/dev/null
  done
}


htd_grp__archive=archive

htd_als__archive_list=archive\ list
htd_als__test_unpacked=archive\ test-unpacked
htd_als__clean_unpacked=archive\ clean-unpacked
htd_grp__note_unpacked=htd-archive


htd__export_docker_env()
{
  launchctl setenv DOCKER_HOST $DOCKER_HOST
  launchctl setenv DOCKER_MACHINE_NAME $DOCKER_MACHINE_NAME
  launchctl setenv DOCKER_TLS_VERIFY $DOCKER_TLS_VERIFY
  launchctl setenv DOCKER_CERT_PATH $DOCKER_CERT_PATH
  note "OK"
}

htd__import_docker_env()
{
  echo DOCKER_HOST=$(launchctl getenv DOCKER_HOST)
  echo DOCKER_MACHINE_NAME=$(launchctl getenv DOCKER_MACHINE_NAME)
  echo DOCKER_TLS_VERIFY=$(launchctl getenv DOCKER_TLS_VERIFY)
  echo DOCKER_CERT_PATH=$(launchctl getenv DOCKER_CERT_PATH)
}


# XXX: to-html of vim-syntax highlited files. But what about ANSI in and out?
# Also, this does not seem to take colorscheme values?
# There is also ANSI HTML Adapter https://github.com/theZiz/aha
# Below is not ideal, maybe AHA is better.
#
# FIXME: pstree-color is perhaps not returning valid escapes, as 2html.vim chokes
htd__colorize()
{
  test -n "$1" || set -- "-"

  case "$1" in

    - )
        set -- $sys_tmp/htd-vim-colorize.out
        #{ cat - > $1 ; }
        #exec 0<&-
        #  -R -E -s  \
        vim \
          -c "syntax on" \
          -c "AnsiEsc" \
          -c "w! $1" \
          -c "let g:html_no_progress=1" \
          -c "let g:html_number_lines = 0" \
          -c "let g:html_use_css = 1" \
          -c "let g:use_xhtml = 1" \
          -c "let g:html_use_encoding = 'utf-8'" \
          -c "TOhtml" \
          -c "wqa!" \
          -

        open $1.xhtml
        rm $sys_tmp/htd-vim-colorize* $sys_tmp/.htd-vim-colorize*
      ;;

    * )
        test -e "$1" || error "no file '$1'" 1
        local output="$B/$(prefix_resolve "$1").xhtml"
        {
          trueish "$keep_build" && test -e "$output" -a "$output" -nt "$1"
        } && note "Existing build is up-to-date <$output>" || {
          vim_swap "$1" || error "swap file exists '$1'" 2
          mkdir -p "$(dirname "$output")"
          #  -E -s \
          # -R -E -s  \
          # FIXME: use colorize for converting ANSI dumps to HTML
          # -c "AnsiEsc" \
          vim \
            -c "syntax on" \
            -c "colorscheme mustang" \
            -c "let g:html_no_progress=1" \
            -c "let g:html_number_lines = 0" \
            -c "let g:html_use_css = 1" \
            -c "let g:use_xhtml = 1" \
            -c "let g:html_use_encoding = 'utf-8'" \
            -c "TOhtml" \
            -c "wqa!" \
            "$1"
          mv "$1.xhtml" "$output"
          note "Written to <$output>"
        }
        trueish "$open" && open "$output" || echo " $output"
        trueish "$keep_build" || rm "$output"
      ;;

  esac
}


# Control 'say' command (BSD/Darwin)
htd__say()
{
  lang=$1
  shift
  test -n "$s" || s=f
  case "$lang" in
    uk ) case "$s" in m ) say -v Daniel "$@" ;; f ) say -v Kate "$@" ;; esac;;
    us ) case "$s" in m ) say -v Alex "$@" ;; f ) say -v Samantha "$@" ;; esac;;
    dutch | nl ) case "$s" in m ) say -v Xander "$@" ;; f ) say -v Claire "$@" ;; esac;;
    japanese | jp ) case "$s" in m ) say -v Otoya "$@" ;; f ) say -v Kyoko "$@" ;; esac;;
    chinese | cn | sc ) say -v Ting-Ting "$@" ;; hong-kong | sar | tc ) say -v Sin-ji "$@" ;;
  esac
}


htd_man_1__src='TODO: this is for the src service/directory

  linespan Start-Line[/- ]Lines File [Checks]
    Retrieve content. Provided checksums to validate files before.

  (content | linerange) Start-Line[- ]End-Line File [Checks]
    Convert range to to span and defer execution to linespan.

  validate File Checks..
    Require one/each/all checksums to be valid. Checksums can be abbreviated
    (abbrev=7). See ck-<CK> for more details.

  grep-to-first Grep File From-Line
    ..

See source for src.lib.sh wrapped as subcommands.
'
htd__src()
{
  test -n "$1" || set -- list
  case "$1" in

    linespan ) shift ;
        note "'$*'"
        { fnmatch "*-*" "$1" || fnmatch "*/*" "$1"
        } && { r="$1" ; shift ; set -- $(echo "$r" | tr '/-' ' ') "$@" ; }
        sl=$1 l=$2 file=$3 ; shift 3
        test -z "$1" || { htd__src validate "$file" "$@" || return ; }
        tail -n +$sl $file | head -n $l
      ;;

    content | linerange ) shift ;
        fnmatch "*-*" "$1" &&
            { r="$1" ; shift ; set -- $(echo $r | tr '-' ' ') "$@" ;}
        sl=$1 el=$2 file=$3 ; shift 3
        htd__src linespan $sl $(( $el - $sl + 1 )) "$file" "$@"
      ;;

    grep-to-first ) shift ; grep_to_first "$@" ; echo $first_line ;;
    grep-to-previous ) shift ; grep_to_last "$@" ; echo $prev_line ;;

    validate ) shift ;
        file=$1 ; shift
        while test $# -gt 0
        do
          echo "$1  $file"
          shift
        done | any=1 ck_validate
      ;;

    * ) error "'$1'?" 1 ;;
  esac
}
htd_flags__src=f


htd__domain()
{
  note "Domain User ID: "$(cat $(statusdir.sh file domain-identity))
  note "Domain Net ID: "$(cat $(statusdir.sh file domain-network))
}


# exit succesfully after receiving 4 replies
htd__ping()
{
  case "${OS_UNAME:?}" in

    Darwin )
        ping -ot 4 $1 || return $?
      ;;

    Linux )
        ping -c 4 $1
      ;;

  esac
}


# Count depth (excluding root)
htd__path_depth()
{
  test -n "$1" || error arg-1-path-expected 1

  while test $# -gt 0
  do
    path="$(htd__normalize_relative "$1")"
    #note "Depth for path $path"
    # Count dashes (except the trailing one)
    depth=$(echo $path | tr '/' ' ' | count_words)
    # Remove root.
    echo $(( $depth - 1 ))
    shift
  done
}
htd_als__depth=path-depth


htd_grp__srv=htd-srv
htd_grp__srv_list=htd-srv

# Check if any of 'lower-case' SId or 'Title-Case' path of NAME in DIR exists
htd__name_exists() # DIR NAME
{
  name="$2"
  test -e "$1/$2" && return
  sid=$(lower=true str_sid "$2")
  name="$sid"
  test -e "$1/$sid" && return
  sid=$(str_sid "$(str_title "$2")")
  name="$sid"
  test -e "$1/$sid" && return
  return 1
}

# services list
SRVS="archive archive-old scm-git src annex www-data cabinet htdocs shared \
  docker"
# TODO: use service names from disk catalog


#htd_grp__munin=munin
htd_grp__munin_ls=munin
htd_grp__munin_ls_hosts=munin
htd_grp__munin_archive=munin
htd_grp__munin_merge=munin
htd_grp__munin_volumes=munin
htd_grp__munin_check=munin
htd_grp__munin_export=munin


htd_man_1__find_broken_symlinks='Find broken symlinks'
htd__find_broken_symlinks()
{
  lib_require os-htd || return
  find_broken_symlinks "$@"
}


htd_man_1__find_skip_broken_symlinks='Find except broken symlinks'
htd__find_skip_broken_symlinks()
{
  lib_require os-htd || return
  find_filter_broken_symlinks "$@"
}


htd_man_1__uuid="Print a UUID line to stdout"
htd_spc__uuid="uuid"
htd__uuid()
{
  get_uuid
}


htd_man_1__finfo='Touch document metadata for htdocs:$HTDIR' # XXX: setup env before main?
htd_spc__finfo="finfo DIR"
htd__finfo()
{
  req_dir_env HTDIR
  for dir
  do
    finfo.py --recurse --documents --env htdocs=HTDIR $dir \
      || return $?
  done
}


htd__reader_update()
{
  cd /Volumes/READER

  for remote in $(git remote)
  do
    name="$(basename "$remote")"
    newer_than "$remote" _1HOUR && {
      stderr info "Remote $name is up-to-date"
    } || {
      note "Remote $name is too old, syncing"
      git annex sync $name && continue || error "sync failed"
    }
  done

  note "Removing dead symlinks (annex content elsewhere), for PRS software"
  find ./ -type l | while read l
  do
    test -e "$l" || rm "$l"
  done
}


htd_man_1__annex='Extra commands for GIT Annex.

  remote-export REMOTE [RSync-Options]
    Use given remote name as plain export, like annex v6.2 should (but using
    older annex). See import for rsync-options.

  remote-import REMOTE [RSync-Options]
    Use given remote name to get rsync info, sync data from remote dir to
    TMPDIR and call git annex import TMPDIR. Local dir should be the target
    repo. See import.

These commands use a specialremote, provided by GIT Annex. However the remote
should not be used for regular sync. See `configuring a special remote for tree
export`__.

.. __: https://git-annex.branchable.com/design/exporting_trees_to_special_remotes/#index1h2

  import RSync-Info Checkout-Dir [RSync-Options]
    Import from any rsync-spec, rsync first if not a local directory.
    Then call git annex import ... This passes extra arguments as options to
    rsync, e.g. to use include/exclude patterns. Also before git-annex-import
    all normal tracked files are copied from source.

  list
    List annex paths
  metadata
    Formfeed delineated k/v
'
htd__annex()
{
  test -n "$1" || error command 1
  test -n "$dry_run" || dry_run=true

  local srcinfo= rsync_flags=avzui act=$1 ; shift 1
  falseish "$dry_run" || rsync_flags=${rsync_flags}n

  get_srcinfo() # Get URL for remote name
  {
    srcinfo=$(git config --local --get remote.${remote}.annex-rsyncurl)
    test -n "$srcinfo" || {
        package_lib_set_local "."
        srcinfo=$(package_get_keys urls.${remote})
    }
    test -n "$srcinfo" || error "annex remote-export srcinfo ($remote)" 1
  }

  case "$act" in

    remote-export ) local remote=$1 ; shift
        test -d "./.git/annex" || error annex 1
        test -n "$remote" || error remote 1
        get_srcinfo
        rsync -${rsync_flags}L "./" "$srcinfo" "$@" || return $?
      ;;

    remote-import ) local remote=$1 ; shift
        test -d "./.git/annex" || error annex 1
        test -n "$remote" || error remote 1
        get_srcinfo
        htd__annex import $srcinfo/ . "$@" || return $?
      ;;

    import )
        # Add remote-dir import to git-annex-import, and do not turn
        # tracked files into annexed files
        test -n "$1" || error src 1
        test -n "$2" || error dest 1
        test -d "$2/.git/annex" || error annex-import 1

        local tmpd=$(base=htd-annex setup_tmpd) srcinfo=$1 dest=$2 ; shift 2
        # See if remote-spec is local path, or else sync. Extra arguments
        # are used as rsync options (to pass on include/exclude patterns)
        test -e "$srcinfo" && tmpd=$srcinfo ||
          rsync -${rsync_flags} "$srcinfo" "$tmpd" "$@"

        {
            cd "$dest" ;

            # Copy normal tracked files so annex doesn't import them
            htd__git_import "$tmpd" ||
                warn "git-import $tmpd returned $?" 1

            trueish "$dry_run" && {
              echo git annex import --deduplicate $tmpd/*

            } || {

              # Force is needed to take updates during import
              git annex import --force --deduplicate $tmpd/* ||
                  warn "annex-import $srcinfo returned $? ($tmpd)"

              git status || true
            }
        }
        # Remove tmpdir if not a local srcdir
        test -e "$srcinfo" && note "Leaving localdir $srcinfo" || rm -r $tmpd
      ;;

    metadata ) lib_require annex
        htd_annex_files "$@" | annex_metadata ;;

    git-deleted )
        git ls-files -d | while read -r fn;
        do echo "$(basename $(git show HEAD^:"$fn")) $fn" ; done
      ;;

    drop-git-deleted )
        git ls-files -d | while read -r fn;
        do echo "$(basename $(git show HEAD^:"$fn")) $fn" ; done |
          annex_dropkeys
      ;;

    * ) subcmd_prefs=${base}_annex_ try_subcmd_prefixes "$@" || return ;;

  esac
}

htd_flags__annex_fsck=i
htd__annex_fsck()
{
  local rules=.sync-rules.list
  test -e "$rules" || {
    note "No local rules, executing global rules"
    rules=~/.conf/sync-rules.list
  }
  read_nix_style_file $rules | while read dir branch remotespec which
  do
    dir="$(htd prefixes expand "$dir")"

    { cd $dir ; test "$which" = "1" -o "$which" = "2" && {

        git annex fsck -q && {
            echo "$dir" >$passed
        } || {
            error "[$dir] fsck failure ($?)"
            echo "$dir" >$failed
        }
    } ; }
  done
  test -s "$passed" &&
      note "$(count_lines "$passed") repositories OK" || warn "Nothing to do"
}


htd_man_1__sync='Go over local or global repo paths for syncing'
htd__sync()
{
  local rules=.sync-rules.list
  test -e "$rules" || {
    test -e .git/annex && {
      git annex sync
      return $?
    }
    sys_confirm "No local rules, execute all global rules?" || return $?
    rules=~/.conf/sync-rules.list
  }
  read_nix_style_file $rules | while read dir branch remotespec which
  do
    dir="$(htd prefixes expand "$dir")"

    cd $dir || error "cd '$dir'" 1
    test "$remotespec" != "*" || remotespec="$(git remote | lines_to_words)"
    test -z "$(git status --porcelain -uno)" || {
      warn "Ignoring dirty index at '$dir'"
      continue
    }

    test "$branch" = "$(git rev-parse --abbrev-ref HEAD)" && {

        note "[$dir] updating '$branch' from '$remotespec'.."
    } || {
        note "[$dir] Checking out '$branch' for '$remotespec'.."
        git checkout -q $branch ||
            error "[$dir] git checkout '$branch' ($?)" 1
    }

    test -z "$which" -o "$which" = "0" -o "$which" = "2" && { # GIT

        for remote in $remotespec
        do
            test "$remote" = "$hostname" && continue
            git pull -q $remote $branch ||
                error "[$dir] git pull '$remote $branch' ($?)" 1
        done
        for remote in $remotespec
        do
            test "$remote" = "$hostname" && continue
            git push -q $remote $branch ||
                error "[$dir] git push '$remote $branch' ($?)" 1
            note "[$dir] $branch in sync with $remote/$branch"
        done

    }
    test "$which" = "1" -o "$which" = "2" && { # GIT-Annex

        note "[$dir] Backing up tracked local files.."
        git annex sync -q $remotespec ||
            error "[$dir] git annex sync '$remotespec' ($?)" 1

        for remote in $remotespec
        do
            test "$remote" = "$hostname" && continue
            trueish "$(git config --get remote.$remote.annex-ignore)" && continue
            git annex copy -q --to $remote ||
                error "[$dir] git annex copy --to '$remote' ($?)" 1
            note "[$dir] backup done at $remote"
        done
    }
    continue
  done
}


htd_man_1__annices='
'
htd__annices()
{
  case "$1" in

      #findbysha2list ) shift ;;
      #lookup-by-key ) shift ;;
      #lookup-by-sha2 ) shift ;;
      #scan-by-sha2 ) shift ;;

      * ) error "'$1'?" 1
        ;;
  esac
}


htd_man_1__init_backup_repo='Initialize local backup annex and symlinks'
htd__init_backup_repo()
{
  test ! -e "/srv/backup-local" \
    || error "Local backup annex exists (/srv/backup-local)" 1

  test -n "$1" && {
    test -d "$1" || error "Dir expected" 1
  } || {
    test -d /srv/annex-local/ && set -- "/srv/annex-local"
    stderr info "Using local annex folder for annex-backup checkout"
  }

  git clone $(htd git-remote annex-backup) $1/backup &&
      stderr info "Cloned annex-backup into $1/backup" || return $?
  ln -s $1/backup /srv/backup-local &&
      stderr info "Initialized backup-local symlink ($1/backup)" || return $?

  note "Initialized local backup annex ($1/backup)"
}


# Copy/move all given file args to backup repo
htd_flags__backup=iAOP
htd__backup()
{
  local act= bu_act_lbl= bu_act=

  test -n "$choice_keep" || choice_keep=1 # TODO

  trueish "$dry_run" && {
    note "Doing dry-run of $# files.."
    act="echo '*** DRY-RUN ***'"
  } || act=''

  trueish "$choice_keep" && {
    note "Copying $# files to backup.."; bu_act=cp; bu_act_lbl=Copy
  } || {
    note "Moving $# files to backup.."; bu_act=mv; bu_act_lbl=Move
  }

  local srcpaths="$(for arg
    do
      test -f "$arg" || warn "Missing or not a file for backup: '$arg'" 1
      realpath "$arg"
    done )"

  test -d "/srv/backup-local" || error "Unknown error" $?
  (
    cd /srv/backup-local
    git diff --quiet --exit-code \
      || error "Changed in local backup repo" 1
  )

  # Created dest path from given path but replace path elements
  local destpath= prefix=
  while test $# -gt 0
  do
    trueish "$no_cabinet" || {
      prefix=$(date_flags="-r $(filemtime $1)" date_fmt "" %Y/%m/%d-)
    }
    destpath="$prefix$(echo "$1" | tr '/' '-')"
    dirname=$(dirname $destpath)
    test -z "$dirname" || {
      test -d /srv/backup-local/$dirname || mkdir -vp /srv/backup-local/$dirname
    }
    test ! -e /srv/backup-local/$destpath \
      || error "File $destpath already exist" 1
    eval $act $bu_act $1 /srv/backup-local/$destpath \
      && note "$bu_act_lbl '$1' to backup" \
      || warn "$bu_act_lbl '$1' failed" 1
    shift
    test ! -d /srv/backup-local/.git || {
      ( cd /srv/backup-local
        eval $act git annex add $destpath || error "Failed adding files to annex" $?
      )
    }
  done

  cd /srv/backup-local

  test ! -d .git || {
    {
      test -n "$msg" || msg="Backed up files at '$hostname':\n\n$srcpaths"
      trueish "$dry_run" && {
        eval $act git ci -m \\\"\"$msg\"\\\"
      } || {
        echo "$msg" | git ci -F -
      }
    } \
      || error "Failed making backup commit" $?

    test ! -d "/srv/backup-local/.git/annex" || {
      eval $act git annex sync \
        || error "Annex sync failed" $?
      eval $act git annex copy --to 21-2
    }
    note "Backed up to /srv/backup-local"
  }
}
htd_pre__backup=htd_backup_prereq
htd_argsv__backup=htd_backup_argsv
htd_optsv__backup=htd_backup_optsv


htd_man_1__pack_create="Create archive for dir and add ck manifest"
htd_man_1__pack_verify="Verify archive with manifest, see that all files in dir are there"
htd_man_1__pack_check="Check file (w. checksum) TODO: dir with archive manifest"
htd_flags__pack=i
htd__pack()
{
  test -n "$2" || set -- "$1" . "$3"

  test -n "$3" || set -- "$1" "$2" "$(basename "$(realpath "$2")")"
  fnmatch "*.tar.*" "$3" || set -- "$1" "$2" "$3.tar.lzma"

  case "$1" in

    create )
        test -d "$2" || error "No such dir '$2'" 3
        test ! -e "$3" || error "archive already exists '$3'" 3
        test -n "$CK" || CK=sha1
        test "$CK" != "ck" || error "TODO ck sums" 1
        local tab=manifest.$CK
        test ! -e $tab || error "Manifest exists: $tab" 1
        htd__ck $tab "$2"
        find $2 -iname '*.tar*' >>$skipped
        stderr info "Creating archive from '$2'"
        tar --exclude '*.tar*' --lzma -cvf "$3" $tab "$2" \
          2>&1 | grep '^a\ ' | sed 's/^a\ /htd:'"$subcmd"':create:added/g' \
          >> $passed
        rm $tab
        note "Created archive '$3' from '$2'"
      ;;

    verify ) # verify files are present and cataloged. No checksumming.
        tar -tf "$3" >/dev/null \
          && htd_passed "Archive checked '$3'" \
          || error "Error in archive '$3'" 1
        tar -xf "$3" manifest.* || error "No manifest(s) in archive '$3'" 1
        local ck_tab=manifest
        test -e $ck_tab.sha1 || error $ck_tab.sha1-expected 1
        # FIXME: iterate files instead
        while read checksum path
        do
          htd__ck_table sha1 "$path" \
            || echo "htd:$subcmd:verify:$check" >>$failed
        done < $ck_tab.sha1
        rm $ck_tab.*
      ;;

    #validate )
    #    test "$CK" = "ck" && {
    #      htd__cksum table.$CK
    #    } || {
    #      ${CK}sum -c table.$CK
    #    }
    #  ;;

    check ) # lookup and compare checksum from manifest
  test -f "$2" || error "No such file '$2'" 3
        tar -xf "$3" manifest.* || error "No manifest(s) in archive '$3'" 1
        local ck_tab=manifest
        # find...
        sha1sum="$(sha1sum "$2" | awk '{print $1}')"
        test "$sha1sum" = "$(htd__ck_table sha1 "$2" | cut -f 1 -d ' ')" \
          && echo "htd:$subcmd:$2" >>$passed \
          || echo "htd:$subcmd:$2" >>$failed
      ;;

    add )
        echo TODO
      ;;

  esac

  test ! -s "$skipped" || {
    note "Skipped files: $(cat $skipped)"
    return 1
  }
}

htd_backup_prereq()
{
  test -e /srv/backup-local || {
    trueish "$choice_interactive" && {
      test -n "$choice_confirm" || confirm "Create local backup annex repo?"
      trueish "$choice_confirm" && {
        htd init-backup-repo || return $?
      }
    } || {
      error "Expected backup dir" 1
    }
  }
}

htd_backup_argsv()
{
  test -n "$*" || error "Nothing to backup?" 1
  opt_args "$@"
}

htd_backup_optsv()
{
  while test $# -gt 0
  do
    case "$1" in
      --archive* )
        ;;
      --tags-append* )
        ;;
      --node-base )
        ;;
      --add-base )
        ;;
      --no-cabinet )
        ;;
      * )
          main_options_v "$1"
        ;;
    esac
    shift
  done
}



# List GNU PG keys
htd__gpg()
{
  gpg -K --keyid-format long --with-colons --with-fingerprint
}

# Export GNU-PG keys in ASCII format
htd__gpg_export()
{
  gpg --export --armor $1
}


htd__bdd_args()
{
  for x in *.py *.sh test/*.feature test/bootstrap/*.php
  do
    printf -- "-w $x "
  done
}

htd__bdd()
{
  test -n "$1" && {
    set -- test/$1.feature
    nodemon -x "./vendor/bin/behat $1" \
      --format=progress \
      -C $(htd__bdd_args)
  } || {
    set -- test/
    nodemon -x "./vendor/bin/behat $1" \
      --format=progress \
      $(htd__bdd_args)
  }
}


htd__clean_osx()
{
  sys_confirm "Continue to remove Caches? [yes/no]" || return 1
  (
    sudo rm -rf ~/Library/Caches/*/*
    #/Library/Caches/*/*
  ) && stderr ok "Deleted contents of {~,}/Library/Caches" ||
    error "Failure removing contents of {~,}/Library/Caches"
}


htd__basenames()
{
  test -n "$*" && basenames "$@" || {
    basenames .rst $( lines_to_words )
  }
}


htd_spc__pathnames="exts=DOC-EXTS pathname PATH.."
htd__pathnames()
{
  test -n "$exts" || exts="$DOC_EXTS"
  {
    pathnames "$@" || return $?
  } | sort -u
}



# Shell script source


htd_man_1__src_info=
htd_grp__src_info=box-src
htd_load__src_info=src\ functions
htd__src_info()
{
  test -n "$1" || set -- $0
  local functions=0 lines=0
  for src
  do
    src_id=$(prefix_resolve $src)
    $htd_log file_warn $src_id "Listing info.." >&2
    $htd_log header "Box Source" >&2
    functions_=$(functions_list "$src" | count_lines)
    functions=$(( $functions + $functions_ ))
    $htd_log header2 "Functions" $functions_ >&2
    count=$(count_lines "$src")
    lines=$(( $lines + $count ))
    $htd_log header3 "Lines" $count >&2
    $htd_log file_ok $srC_id >&2
  done
  $htd_log header2 "Total Functions" $functions >&2
  $htd_log header3 "Total Lines" $lines >&2
  $htd_log done $subcmd >&2
}


htd_grp__functions=htd-functions
htd_als__list_functions=functions\ list
htd_als__list_funcs=functions\ list
htd_als__ls_functions=functions\ list
htd_als__ls_funcs=functions\ list

htd_als__find_functions=functions\ find
htd_als__find_funcs=functions\ find

htd_als__funcs=functions

htd_grp__filter_functions=src
htd_grp__list_functions_added=src
htd_grp__list_functions_removed=src
htd_grp__diff_function_names=csrc
htd_grp__find_function=src

htd_als__new_functions=list-functions-added
htd_als__deleted_functions=list-functions-removed


htd__vcard2n3()
{
  swap_dir=/home/berend/project/w3c-swap/swap.mpe/
  PYTHONPATH=$swap_dir:$PYTHONPATH $swap_dir/pim/vcard2n3.py $*
}


# this acts as a remote diff program, accepting two files and displaying
# a diff for them.  Zero, one, or both files can be remote.  File paths
# must be in a format `scp` understands: [[user@]host:]file
htd__rsdiff()
{
  f1=/tmp/rdiff.1
  f2=/tmp/rdiff.2
  scp $1 $f1
  scp $2 $f2
  if [ -f $f1 -a -f $f2 ]; then
    vimdiff -b $f1 $f2
  fi
  rm -f $f1 $f2
}


htd__crypto_volumes()
{
  for x in /srv/volume-[0-9]*
  do
    test -d $x/crypto || continue
    echo $x/crypto
  done
}


htd__crypto_volume_find()
{
  test -n "$*" || return
  while test $# -gt 0
  do
    htd__crypto_volumes | while read volume
    do
      echo "$volume/$1"
      test -e "$volume/$1" || continue
      echo "$volume/$1"
    done
    shift
  done
}


htd_grp__crypto=crypto
htd_grp__crypto_mount_all=crypto
htd_grp__crypto_mount=crypto
htd_grp__crypto_unmount=crypto
htd_grp__crypto_vc_init=crypto


htd_man_1__vfs='
    mount NAME PATH CLASS
      Mount VFS
    umount NAME
      Unmount VFS
    mounted NAME
      Check for VFS name in mount list
    running NAME
      Check for VFS process ID
    check NAME
      Run mounted and running check.
'
htd_flags__vfs=l
htd_libs__vfs=vfs
htd__vfs()
{
  # FIXME default vfs status test -n "$1" || set -- status
  verify=1 subcmd_prefs=${base}_vfs_ try_subcmd_prefixes "$@"
}


htd_flags__hoststat=fl
htd_libs__hoststat=hoststat
htd__hoststat()
{
  test -n "$1" || set -- status
  subcmd_prefs=${base}_hoststat_ try_subcmd_prefixes "$@"
}


htd_flags__volumestat=l
htd_libs__volumestat=volumestat
htd__volumestat()
{
  test -n "$1" || set -- status
  subcmd_prefs=${base}_volumestat_ try_subcmd_prefixes "$@"
}


htd__darwin()
{
  test -n "$1" || set -- list
  subcmd_prefs=${base}_darwin_\ darwin_ try_subcmd_prefixes "$@"
}
htd_flags__darwin=f


# Advanced init-symlinks script with multiple modes and attributes
htd_spc__checkout='checkout ID-or-TABLE'
htd_env__checkout='
  symlinks_id=${symlinks_id-script-mpe-symlinks}
  symlinks_attrs= symlinks_file=
'
htd__checkout()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  test -e "$1" && fn="$1" || fn="$symlinks_file"
  test -x "$fn" && table_f=- || table_f="$fn"

  stderr info "2.2. Env: $(var2tags id symlinks_fn table_f )"
  test "$table_f" = "-" && {
    # TODO: either generate table
    #alternatively generate table dynamically?
    exit 44 #. $fn
  } || {
    test -e "$table_f" || error "No such table '$table_f'" 1
    fixed_table $table_f $symlinks_attrs | while read vars
    do
      eval "$vars"
      test -e "$DEST" && {
        test "$(readlink $SRC)" = "$DEST" && {
          stderr ok "OK: $DEST"
          continue
        }
        test -h "$DEST" && rm $DEST
      }
      test -e "$DEST" && {
        error "Path exists '$DEST'"
        continue
      }
      ln -s $SRC $DEST
    done
  }
}
htd_flags__checkout=ieOAp
htd_argsv__checkout()
{
  (
    package_id=$symlinks_id
    package_file && package_update
  )
  package_id=$symlinks_id package_lib__load
  eval $(map=package_:symlinks_ package_sh id file attrs)
  test -n "$symlinks_attrs" || symlinks_attrs="SRC DEST"
  stderr info "2.1. Env: $(var2tags package_id symlinks_id symlinks_attrs)"
}


htd_man_1__date_shift='Adjust mtime forward or back by number of hours, or other
unit if specified'
htd__date_shift()
{
  test -e "$1" || stderr error "date-shift $1"
  case "${OS_UNAME:?}" in
    Linux )
        test -n "$2" || set -- "$1" '-1 day'
        touch -r "$1" -d $2 "$1"
      ;;
    Darwin )
        test -n "$2" || set -- "$1" '-1day'
        # '013007' 1hr30m07sec fwd
        #touch --time=mtime -r "$1" -A $2 "$1"
        touch -r "$1" -A $2 "$1"
      ;;
  esac
}
htd_als__rshift=date-shift


htd_grp__couchdb=couchdb
htd_grp__couchdb_htd_scripts=couchdb
htd_grp__couchdb_htd_tiddlers=couchdb


htd__lfs_files()
{
  test -e .gitattributes || return
  x=$HOME/project/docker-git-lfs-test-server/lfs-test-server-darwin-amd64/lfs-content
  grep filter=lfs .gitattributes |
  while read glob f d m s
  do
    for p in $glob
    do
      h=$(shasum -a 256 $p | awk '{print $1}')
      r="$( echo $h | cut -c1-2 )/$( echo $h | cut -c3-4 )/$( echo $h | cut -c5- )"

      echo $p $r
    done
  done
}


htd_grp__env=env


# Show prefix of VIM install
htd__vim_get_runtime()
{
  vim -e -T dumb --cmd 'exe "set t_cm=\<C-M>"|echo $VIMRUNTIME|quit' | tr -d '\015'
}


htd_grp__ips=net


htd__photos()
{
  PHOTOS_FOLDER=/Volumes/Zephyr/photos
  OSX_PHOTOS="/Volumes/Zephyr/Photos Library.photoslibrary"

  find "$OSX_PHOTOS/Thumbnails" -type f |
  while read thumb
  do
      $grealpath --relative-to="$OSX_PHOTOS" "$thumb"
  done

  find "$OSX_PHOTOS/Masters" -type f |
  while read master
  do
      $grealpath --relative-to="$OSX_PHOTOS" "$master"
  done
}


htd_man_1__ispyvenv='Check wether shell env has Python virtualenv, get prefix

Return 1 if false, or prints the virtualenv prefix. On env choice-interactive
prints a warning or notice to stderr as well.
'
htd__ispyvenv()
{
  python -c 'import sys
if not hasattr(sys, "real_prefix"): sys.exit(1)' && {
        trueish "$choice_interactive" && note "Running with Python virutalenv:"
        python -c 'import sys
print sys.prefix'
        return 0
    } || {
        trueish "$choice_interactive" && warn "No Python virtualenv set"
        return 1
    }
}
htd_als__pyvenv=ispyvenv
htd_als__venv=ispyvenv



htd_grp__catalog=htd-catalog
htd_grp__catalogs=htd-catalogs


htd__annexdir()
{
  test -n "$1" || set -- status
  subcmd_prefs=annexdir_ try_subcmd_prefixes "$@"
}
htd_flags__annexdir=f


htd_grp__foreach=main
htd_grp__filter=main
htd_grp__filter_out=main


htd_als__cal=calendar
htd__calendar()
{
  ncal -w
}


htd_grp__whoami=env


htd_man_1__watch='Alias to local script feature-watch [ARG]'
htd_als__watch='run feature-watch'


htd_man_1__resolve_modified='Helper to move files to GIT stage.

Each basename must test OK, then it is staged.
TODO: rewrite to infinite loop, that doesnt break until lst watch returns.
'
htd__resolve_modified()
{
  vc_modified | while read name
    do
      basename=$(filestripext "$name");
      mkid "$basename" "" "-_";
      note "$name: $basename: $id";
      echo "$id $name"
  done | join_lines - ' ' | while read component files
  do
    htd run test $component && git add $files
  done
}


htd_man_1__components='List component names, followed by associated paths

Default is run package-paths or read paths from stdin, and process basename
to Ids. Ie. components are based on pathnames, and are groups around a basename.
No sub-file components either.
'
htd__components()
{
  test -n "$package_components" && { eval $package_env || return $? ; }
  $package_components
}
htd_flags__components=lpq
htd_libs__components=package


htd_man_1__test_all='TODO: see htd run test-all for script.mpe, work towards
dynamic req/test spec?'
htd__test_all()
{
  htd__components | while read component files
  do
    htd run test $component
  done
}


htd__dangling_blobs()
{
  git fsck | grep 'dangling blob' | cut -f 3 -d ' ' | while read sha1
  do
    echo $sha1
    #vc.sh list-objects $sha1
    #git show $sha1
  done
}


htd__pm2()
{
  test -n "$1" || set -- list
  subcmd_prefs=${base}_pm2_ try_subcmd_prefixes "$@"
}
htd_flags__pm2=f


htd_man_1__make='
    files
    targets
'
htd__make()
{
  test -n "$1" || set -- status
  subcmd_prefs=${base}_make_ try_subcmd_prefixes "$@"
}
htd_flags__make=f


htd_grp__composure=main


# XXX: setup env before main?
htd_man_1__meta='

$meta_api_man_1

See also embyapi'
htd__meta()
{
  subcmd_prefs=meta_ try_subcmd_prefixes "$@"
}


htd_grp__emby=media


htd_man_1__src=''
htd_libs__src=htd-src
htd_flags__src=fl
htd__src()
{
  test -n "$1" || set -- default
  subcmd_prefs=${base}_src_ try_subcmd_prefixes "$@"
}


htd_grp__docstat=statusdir\ docstat


htd_grp__context=context
htd_als__ctx=context


htd_flags__lists=q
htd__lists()
{
  htd__gtasks_lists
}


htd_grp__scrtab=scrtab
htd_grp__cmdtab=cmdtab


htd_man_1__redo='
    redo deps - List

'
htd__redo()
{
  subcmd_default=list subcmd_prefs=redo_ try_subcmd_prefixes "$@"
}
htd_flags__redo=l


htd_man_1__stattab='Build stattab index

  new [NAME] [STAT]
    Create a new STAT-Id
  list [Glob]
    List entries
  check
    Add missing
  entry-exists STAT-Id
'
htd__sttab()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  subcmd_default=list subcmd_prefs=stattab_\ htd_stattab_ \
  try_subcmd_prefixes "$@"
}
htd_flags__sttab=qliAO
htd_libs__sttab=stattab


htd_man_1__project_stats=''
htd_spc__project_stats='project-stats [CMD ARGS..]'
htd__project_stats()
{
  project_stats_req || return
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  subcmd_default=stat
  subcmd_prefs=${base}_project_stats_\ project_stats_ try_subcmd_prefixes "$@"
}
htd_flags__project_stats=qilAO
htd_libs__project_stats=statusdir\ date\ project-stats\ build-htd\ htd-project-stats
htd_argsv__project_stats=opt_args


htd_man_1__str=''
htd_spc__str='str [CMD ARGS..]'
htd__str()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  subcmd_prefs=${base}_str_\ str_ try_subcmd_prefixes "$@"
}
htd_flags__str=ilAO
htd_libs__str=str\ htd-str
htd_argsv__str=opt_args

htd_als__count_words=str\ wordcount
htd_als__count_lines=str\ linecount
htd_als__count_columns=str\ colcount
htd_als__count_chars=str\ charcount


htd_flags__user=ilAO
htd_libs__user=user-scripts
htd__user()
{
  eval set -- $(lines_to_args "$arguments") # Remove options from args
  subcmd_prefs=${base}_user_ try_subcmd_prefixes "$@"
}


htd_grp__docker_hub=docker-hub


htd_grp__draft=draft
htd_grp__drafts=draft


htd_grp__eval=htd-eval


htd__conf ()
{
  test -n "${HTD_CONF:-}" || {
    : "${XDG_CONFIG_HOME:="$HOME/.config"}"
    test ! -d "$XDG_CONFIG_HOME/htd" || HTD_CONF="$XDG_CONFIG_HOME/htd"
  }
  test -n "${HTD_CONF:-}" -a -e "${HTD_CONF:-}" ||
      $LOG error "" "Cannot find config dir or does not exist" \
        "${HTD_CONF:-"\$XDG_CONFIG_HOME/htd"}" 1
}


htd__tosort () # ~ [ 'local' | 'global' ]
{
  local dir
  for dir in $(case "${1:-"local"}" in
          ( local ) find ./ \( -iname 'tosort' \
              -o -iname '*tosort' -o -iname '*tosort' \
              -o -iname '*tosort*' \) -a -exec test -d {}/ ';' -print ;;
          ( global ) locate -e -b '*tosort*' | filter_dirs ;;
          ( * ) return 1 ;;
      esac)
  do
    echo "$dir: $(find $dir -type f -o -type l | count_lines)"
  done | sumcolumn 2
}

htd__reader () # ~ <Files...>
{
  for fn in "${@:?}"
  do
    htd_modeline "$fn" || return
    echo "File mode: $filemode" >&2
  done
}

htd_libs__dev=$htd__wf__libs
htd_flags__dev=l
htd_grp__dev=htd-dev

#htd_grp__prefix=htd-prefix


# -- htd box insert sentinel --



# Script main functions

htd_main ()
{
  local scriptname=htd base=$(basename "$0" .sh) \
    scriptpath="$(cd "$(dirname "$0")"; pwd -P)" \
    upper= r= \
    package_id= package_cwd= package_env= \
    subcmd=${1-} subcmd_alias= subcmd_args_pre= flags= \
    dry_run= \
    arguments= subcmd_prefs= options= \
    passed= skipped= error= failed=

  #test -n "$U_S" || U_S=/srv/project-local/user-scripts
  #test -n "$htd_log" || htd_log=$U_S/tool/sh/log.sh
  test -n "${script_util-}" || script_util=$scriptpath/tool/sh
  test -n "${htd_log-}" || htd_log=$script_util/log.sh
  test -n "${verbosity-}" || verbosity=4
  htd_init || $htd_log error htd-main "During htd-init: $?" "$0" $? || return

  case "$base" in

    $scriptname )
        test -n "${subcmd-}" || {
          test -t 0 && set -- main-doc-edit || set -- status
        }
        main_subcmd_run "$@" || return $?
        test "$dry_run" = 0 \
          && std_info "'$base-$subcmd' completed normally" 0 \
          || std_info "'$base-$subcmd' dry-run completed" 0
      ;;

    * )
        $htd_log error htd-main "not a frontend for $base ($scriptname)" "" 1
        return 1
      ;;

  esac
}

# The default optionparser for htd, see htd-subcmd-optsv
htd_optsv()
{
  set -- $(lines_to_words $options)
  for opt
  do
    case "$opt" in
      -S* ) search="$(echo "$opt" | cut -c3-)" ;;
      * ) define_all=1 main_options_v "$opt" ;;
    esac
  done
}

# Initial step to prepare for subcommand
htd_init()
{
  local scriptname_old=$scriptname; export scriptname=htd-init
  test -n "$script_util" || return 103 # NOTE: sanity

  ! "${DEBUG:-false}" ||
    ! "${DIAG:-false}" || {
      add_path "${C_INC:?}"/tool/sh/part &&
      uc_script_load sh-core sh-type user-script &&
      script_debug_env CWD EWD PWP SWD
    }

  set -euETo pipefail
  init_sh_libs=os\ sys\ str\ log
  true "${SWD:="$scriptpath"}"
  true "${SUITE:="Main"}"
  true "${PACK_MAIN_ENV:="$scriptpath/.meta/package/envs/main.sh"}"
  test ! -e $PACK_MAIN_ENV || {
    source $PACK_MAIN_ENV ||
      $htd_log error htd-init "E$? main env" "$PACK_MAIN_ENV" $? || return
  }
  test -n "${HTD_CONF:-}" || { htd__conf ||
      $htd_log error htd-init "E$? htd:conf" "" $? || return
  }

  LOG=$htd_log

  # FIXME: instead going with hardcoded sequence for env-d like for lib.
  INIT_ENV="init-log 0 dev ucache scriptpath std box" \
  INIT_LIB="os sys std log str match src main args stdio vc std-ht shell"\
" bash-uc ansi-uc"\
" date str-htd logger-theme sys-htd vc-htd statusdir os-htd htd ctx-std" \
. ${SWD:="$scriptpath"}/tool/main/init.sh ||  {
    $htd_log error htd-init "E$?" "tool/main/init" $? || return
  }

  trap bash_uc_errexit ERR

  # -- htd box init sentinel --
  export scriptname=$scriptname_old
}

# Use hyphen to ignore source exec in login shell
case "$0" in "" ) ;; "-"* ) ;; * )

  set -euETo pipefail
  shopt -s extdebug

  # Ignore 'load-ext' sub-command
  test "${1-}" = load-ext ||
  test -n "${lib_loading-}" || {
    htd_main "$@"
  }
;; esac

# Id: script-mpe/0.0.4-dev htd.sh
