#!/bin/sh

# Main-Defs: standard definitions for init, lib, load and unload handlers
#   for use with main.lib.
# Created: 2020-06-30


main_main() # Base Default-Subcmd Script-Aliases
{
  test $# -gt 0 -a $# -le 3 || return
  test -n "${main_id-}" || str_vword main_id "$1" || return

  test -n "${main_script-}" || main_script="\$0"
  test -n "${main_base-}" || main_base="\$(basename \$0 .sh)"
  test -n "${main_scriptpath-}" ||
      main_scriptpath="\$(cd \"\$(dirname \"\$0\")\"; pwd -P)"
  test -n "${make_pref-}" || local make_pref=eval
  # test -n "${3-}" || set -- "$1" "$2" "\${aliases-}"
  $make_pref "$(cat <<EOM

${main_id}_main()
{
  local \
      script="$main_script" \
      scriptname=$1 \
      scriptpath="$main_scriptpath" \
      base="$main_base" ${3:-"aliases"} ${3:+"aliases=\"$3\""} \
      ${main_bases:+"baseids=$(echo $(for b in $main_bases;do printf -- \
        "%s\n" "$b" | tr -sc '[:alnum:]\.\\\/:_\n' '_';done|sed ':a;N;$!ba;s/\n/\\ /g'|tr 'A-Z' 'a-z'))"} \
      subcmd=\${1-} subcmd_alias ${2:+"subcmd_default=$2"} \
      subcmd_func flags c ${main_local-}

  ${main_id}_main_init "\$@" || exit \$?
  test \${c:-0} -gt 0 && shift \$c ; c=0

  case "\$base" in

    $(echo $1 $3 | sed 's/ / | /g' ) )
EOM
  test -z "$3" || cat <<EOM
        fnmatch "* \$base *" " \$aliases " &&
            base=\$scriptname
EOM
  test -z "${main_lib-}" || cat <<EOM
        ${main_id}_main_lib || exit \$?
EOM
  cat <<EOM
        test -n "\${subcmd-}" || subcmd=\$subcmd_default
        main_subcmd_run "\$@" || exit \$?
      ;;

    * )
        error "not a frontend for \$base (\$scriptname)" 1
      ;;

  esac
}
EOM
  )"
}

main_define() # 1:Base 2:Local-Vars 3:Init 4:Lib 5:Load 6:Load-Flags 7:Unload 8:Unload-Flags
{
  local main_local="$2" main_init="$3" main_lib="$4" main_load="$5" main_load_flags="$6" main_unload="$7" main_unload_flags="$8"
  main_make "$1"
}

# Assemble and evaluate CLI script with main entry point and
# loader/unloaders for subcommand.
main_make () # Script-Name
{
  test -n "${make_pref-}" || make_pref=eval
  test -n "${main_id-}" || {
    str_vword main_id "$1"
  }

  # Declare an entry point for base unless main-bases is given
  { type_exists ${main_id}_main
  } || {
    main_main "$1" "${main_default:-'usage'}" "${main_aliases-}"
  }

  type_exists ${main_id}_init ||
      $make_pref "$(cat <<EOM

${main_id}_main_init()
{
  local scriptname_old=\$scriptname; export scriptname=$1-main-init

${main_init-}
  ${main_init_env-} . \${CWD:="\$scriptpath"}/tool/main/init.sh || return
  # -- $1 box init sentinel --
  export scriptname=\$scriptname_old
}
EOM
      )"

  { type_exists ${main_id}_main_lib || test -z "${main_lib-}"
  } ||
      $make_pref "$(cat <<EOM

${main_id}_main_lib()
{
  local scriptname_old=\$scriptname; export scriptname=$1-main-lib

$main_lib
  # -- $1 box lib sentinel --
  export scriptname=\$scriptname_old
}
EOM
      )"

  { type_exists ${main_id}_subcmd_load
   } || {
      test -n "${main_load_flags_def-}" ||
          local main_load_flags_def="    * ) error \"No load flag '\$x' for \$base:\$subcmd\" 3 ;;"
      $make_pref "$(cat <<EOM

# Pre-exec: post subcmd-boostrap init
${main_id}_subcmd_load()
{
  local scriptname_old=\$scriptname; export scriptname=$1-subcmd-load

${main_preload-}
  test -n "\${subcmd_func-}" || {
    main_subcmd_func "\$subcmd" || true; # Ignore, check for func later
    c=1
  }

  main_var flags "\$baseids" flags "\${flags_default-}" "\$subcmd"

${main_load-}
  # -- $1 box load sentinel --

  for x in \$(echo \$flags | sed 's/./&\ /g')
  do case "\$x" in
${main_load_flags-$main_load_flags_def}
  esac; done
  export scriptname=\$scriptname_old
}
EOM
      )"
  }

  { type_exists ${main_id}_subcmd_unload ||
      test -z "${main_unload-}" -a -z "${main_unload_flags-}"
  } || {
      test -n "${main_unload_flags_def-}" ||
          local main_unload_flags_def="    * ) error \"No unload flag '\$x' for \$base:\$subcmd\" 3 ;;"
      $make_pref "$(cat <<EOM

# Post-exec: subcmd and script deinit
${main_id}_subcmd_unload()
{
  local scriptname_old=\$scriptname; export scriptname=$1-subcmd-unload
  local unload_ret=0

${main_unload-}
  # -- $1 box unload sentinel --

  for x in \$(echo \$flags | sed 's/./&\ /g')
  do case "\$x" in
${main_unload_flags-"$main_unload_flags_def"}
  esac; done
  export scriptname=\$scriptname_old
  return \$unload_ret
}
EOM
      )"
  }
}

main_entry()
{
  test -n "${make_pref-}" || local make_pref=eval
  local main_call="${main_id}_main \"\$@\""
$make_pref "$(cat <<EOM

# Main entry - bootstrap script if requested
# Use hyphen to ignore source exec in login shell
case "\$0" in "" ) ;; "-"* ) ;; * )

  # Ignore 'load-ext' sub-command
  test "load-ext" != "\${1-}" || __load=ext
  case "\${__load-}" in
    ext ) ;;
    * ) ${main_call} ;;

  esac ;;
esac

${main_epilogue-}
EOM
  )"
}

# Id: script-mpe/0.0.4-dev main-defs.lib.sh
