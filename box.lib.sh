#!/bin/sh

# box - Shell framwork wip


box_lib__load()
{
  test -n "${hostname-}" || hostname="$(hostname -s | tr '[:upper:]' '[:lower:]')"
  test -n "${box_name-}" || box_name=$hostname
}

box_lib__init()
{
  test "${box_lib_init-}" = "0" && return

  box_posixly_correct || return
  lib_assert src || return

  test -z "${DEBUG-}" || {
    test "$PWD" = "$(pwd -P)" || warn "current dir seems to be aliased"
  }

  test -n "$BOX_DIR" || error "box-load: expected BOX-DIR env" 1
  test -d "$BOX_DIR" || mkdir -vp $BOX_DIR

  nid_cwd=$(str_word "$PWD")

  test ! -e "$BOX_DIR/bin/$box_name" ||
      box_file="$BOX_DIR/bin/$box_name"
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized box.lib" "$(sys_debug_tag)"
}


### Util functions

box_find_localscript()
{
  # XXX: or scan for function before determining script
  test -e "$local_script" && return || {
    warn "No local_script for $hostname:$PWD"
    return 1
  }
}

box_find_namedscript()
{
  test -n "${named_script-}" || named_script=$BOX_BIN_DIR/$script_name
  test -e "$named_script" && return || {
    warn "No named_script for $script_name"
    return 1
  }
}

box_req_files_localscript()
{
  local r=0

  box_find_localscript && {
    log "Inncluding local-script $local_script"
    . $local_script
    script_files="$script_files $local_script"
  } || r=1

  box_find_namedscript && {
    log "Including named-script $named_script"
    . $named_script
    script_files="${script_files:-}${script_files:+" "}$named_script"
  } || r=$(( $r + 1 ))

  test -e "$uconf_script" && {
    log "Including uconf-script $uconf_script"
    . $uconf_script
    script_files="$script_files $uconf_script"
  } || r=$(( $r + 1 ))

  test $r -lt 3 || return $r
}

box_init_local()
{
  subbox_name="${script_name}:${script_subcmd_name}"
  test -n "$local_script" || local_script=$BOX_DIR/${script_name}/${nid_cwd}.sh
  test -n "$uconf_script" || uconf_script=$BOX_DIR/$script_name-localscripts.sh
  test -e $uconf_script && warn "TODO clean $uconf_script"

  case "${1-}" in 1 )
        test -e "$named_script" || touch $named_script
        box_req_files_localscript
      ;;
    2 )
        box_req_files_localscript || return 1
      ;;
    * )
        box_req_files_localscript || true
      ;;
  esac
  locate_name
}

box_init_script()
{
  touch $1
  chmod +x $1
  echo "#!/bin/sh" > $1
  echo >> $1
}

# 1:func-name 2:file-name[:line-number] 3:script
box_add_function()
{
  test -n "$1" || err "function name arg required" 1
  test -n "$2" || err "file name arg required" 1
  test -n "$3" || err "function body arg required" 1

  fnmatch "*:[0-9]*" $2 && {

    std_info "Inserting funtion $1"
    add_function "$1" "$2" "$3"
  } || {

    std_info "Appending funtion $1 for $2"

    echo "$1()" >> $2
    echo "{" >> $2
    echo "$3" >> $2
    echo "}" >> $2
    echo >> $2
  }
}

box_add_idx()
{
  echo "$1()" >> $2
  echo "{" >> $2
  echo "  $func" >> $2
  echo "}" >> $2
  echo >> $2
}

box_grep()
{
  file_where_before "$@" || return $?
  test -n "$where_line" || return 1
}

# box-script-insert-point FILE SUBCMD PROPERTY BOX-PREFIX
# Return line-nr before function
box_script_insert_point() # File Sub-Cmd Property Box-Prefix
{
  test -e "$1" ||
      error "box-script-insert-point: file-arg required <$1>" 1
  local subcmd_func= grep_file=$1
  shift
  local subcmd_func=$(main_local "$3" "$2" "$1")
  local where_line= line_number= p='^'${subcmd_func}'()$'
  box_grep "$p" "$grep_file" || {
    error "box-script-insert-point: invalid $subcmd_func ($grep_file)" 1
  }
  echo $line_number
}

box_sentinel_indent()
{
  local where_line= line_number=
  box_grep $1 $2 || {
    error "box-sentinel-indent: invalid sentinel $1 ($2)" 1
  }
  echo "$where_line"
}

box_name_args()
{
  test -n "${1-}" && {
    name="$1" ; shift 1 ; c=$(( $c + 1 ))
  } || name="${hostname}"

  test -n "${1-}" \
    && { cmd="$1"; shift 1; c=$(( $c + 1 )); } \
    || note "using default cmd='run'"
}

box_run_cwd()
{
  test -n "${1-}" || error "box-run-cwd: req name" 1
  test -n "${2-}" || error "box-run-cwd: req cmd" 1
  local func=$(echo $func_pref$1__$2 | tr '/-' '__')
  local tcwd=$1
  test -d $tcwd || error "box-run-cwd: no dir $tcwd" 1
  shift 2
  cd $tcwd
  $func "$*"
}

box_init_args () # [Sub-Cmd | "run"] [Script-Name | hostname]
{
  # subcmd-name
  test -n "${1-}" && {
    script_subcmd_name="$1"
  }

  # script-name
  test -n "${2-}" && {
    script_name="$2"
  } || {
    script_name="${hostname}"
  }
}

# Extract source lines from {base}-load routine in frontend script
box_list_libs() # Script-File Box-Prefix
{
  test -n "${1-}" || error "Script-File required" 1
  test -n "${2-}" || error "Box-Prefix required" 1

  local \
    line_offset="$(box_script_insert_point $1 "" lib $2)" \
    sentinel_grep=".*#.--.${2}.box.lib.sentinel.--"
  test -n "$line_offset" ||
    error "box-list-libs: line_offset empty for '$1' lib '$2'" 1
  box_grep $sentinel_grep $1
  local line_diff=$(( $line_number - $line_offset - 2 ))

  test -n "$line_diff" || error "box-list-libs: line_diff empty" 1
  fnmatch "-*" "$line_diff" &&
    error "box-list-libs: negative line_diff: $line_diff" 1 || true

  test -z "${dry_run-}" || {
    debug "named_script='$1'"
    debug "scan after line $line_offset"
    debug "scan up to line $line_number"
    debug "scan total lines $line_diff"
    debug "nid_cwd='$nid_cwd'"
    debug "'$BOX_BIN_DIR/*'"
    std_info "** DRY RUN ends **" 0
  }

  test $line_diff -eq 0 || {
    tail -n +4 | tail -n +$line_offset | head -n $line_diff;
  } < $1
}


# XXX: goes here at box.lib? or into main.lib? Unused still

box_init()
{
  test -n "${UCONF-}" || error "box-init: UCONF" 1
  cd $UCONF
}


box_update()
{
  test -n "${UCONF-}" || error "box-update: UCONF" 1
  cd $UCONF

  test -n "${box_host-}" || box_host=$hostname
  test -n "${box_user-}" || box_user=$(whoami)

  #on_host "$box_host" || ssh_req $box_host $box_user
  #run_cmd "$box_host" "cd \$HOME/.conf && git fetch --all && git pull"
  #run_cmd "$box_host" "cd \$HOME/.conf && vc.sh update-local"

  # TODO: cleanup ansible
  #ansible-playbook -l $box_host ansible/playbook/user-conf.yml
  #ansible-playbook -l $box_host ansible/playbook/system-update.yml
  #ansible-playbook -l $box_host ansible/playbook/user-env-update.yml
}


# Load the {base}_lib functions content, and parse its lines into paths to
# included scripts.
box_lib()
{
  export box_lib="$(box_lib_src "$@" | lines_to_words )"
}

# return source paths, extract from lines found by box-list-libs
box_lib_src()
{
  dry_run= box_list_libs "$@" | while read dir arg args
    do case "$dir" in
      . | source ) eval echo $arg ;;
      dir_load ) test -n "$args" || args=.sh
          for scr in $(eval echo $arg/*$args) ; do
              echo $scr
          done ;;
      lib_load ) for lib in $arg $args ; do
            echo XXX: eval lookup_test=lib_path_exists lookup_path SCRIPTPATH $lib >&2
          done ;;
      * ) ;;
    esac; done
}

# Setup instance for script to use as background service
box_bg_setup()
{
  not_trueish "$no_background" && {

    test ! -e "$main_sock" || error "box: pd meta bg already running" 1
    $main_bg &
    PID=$!
    while test ! -e $main_sock
    do note "box: Waiting for server.." ; sleep 1 ; done
    std_info "box: Backgrounded $main_bg (PID $PID)"

  } || {
    note "box: Forcing foreground/cleaning up background"
    test ! -e "$main_sock" || $main_bg exit \
      || error "box: Exiting old" $?
  }
}

# Close backgrounded service script instance
box_bg_teardown()
{
  test ! -e "$main_sock" || {
    $main_bg exit
    while test -e $main_sock
    do note "box: Waiting for background shutdown.." ; sleep 1 ; done
    std_info "box: Closed background metadata server"
    test -z "$no_background" || warn "box: no-background on while pd-sock existed"
  }
}

box_lib_current_path()
{
  # test "$PWD" = "$(pwd -P)" || warn "current dir seems to be aliased"
  set -- $( ( while true ; do pwd && cd .. ; test "$PWD" != '/' || break; done ) |
      while read -r path
      do
        str_word "$path"
      done | while read -r vid
      do
        sh="$BOX_DIR/${hostname}/${vid}.sh"
        test -e "$sh" || continue
        echo "$sh"
      done | lines_to_words )

  box_lib="$box_lib $*"
  test -z "$*" || . "$@"
}

# List distinct values for "grp" attribute.
box_list_function_groups() # [ Src-Files... ]
{
  test -n "$1" || set -- "$0"
  for src in "$@"
  do
    grep '^[a-z][0-9a-z_]*_grp__[a-z][0-9a-z_]*=.*' $src | sed 's/^.*=//g'
  done | uniq
}

# List all box functions with their attribute key-names. By default set FILE to
# executing script (ie. htd).
box_list_functions_attrs() # [FILE]
{
  test -n "$1" || set -- $0
  for f in $@
  do
    grep '^[a-z][0-9a-z_]*__[0-9a-z_]*().*$' $f | sed 's/().*$//g' |
      grep -v 'optsv' | grep -v 'argsv' | sort -u |
      while read subcmd_func
    do
      base=$(echo $subcmd_func | sed 's/__.*$//g')
      function=$(echo $subcmd_func | sed 's/^.*__//g')
      printf -- "  $(echo $function | tr '_' '-')\n"
      eval grep "'^${base}_.*__${function}\\(\\(=.*\\)\\|()\\)$'" $f |
        sed -E 's/(=|\().*$//g' | while read attr_field
      do
        printf -- "   - $(echo $attr_field |
          cut -c1-$(( ${#attr_field} - ${#field} - 2 )) |
          cut -c$(( ${#base} + 2 ))- |
          tr '_' '-')\n"
      done
    done
  done
}
