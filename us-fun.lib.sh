
# FIXME: move to +user-scripts:tool/us/part

us_fun_lib__load ()
{
  : "${us_fun_funset:=$(echo \
    at_ \
    us_{basedir,stbtab,class,stdenv,userconf,userdir,xctx}_init \
    us_xctx_switch)}"
}

us_fun_lib__init ()
{
  lib_require sys lib-uc class-uc || return
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized us-fun.lib" "$(sys_debug_tag)"
}


at_ () # ~ <ctx> [<ctx|args..>]
{
  while test 0 -lt $#
  do
    : "${1:?at_ argument 1 expected}"

    ctxv=${1//[^A-Za-z0-9_]/_}ctx
    test -n "${!ctxv:-}" &&
    std_quiet declare -F "$_" && {
      set -- $_ "${@:2}"
      break
    }

    uc_script_load "${1:?}" || return
    ! std_quiet declare -F at_${1//[^A-Za-z0-9_]/_} || {
      set -- $_ "${@:2}"
      break
    }
    shift
  done
  test 0 -eq $# && return
  "$@"
}

us_basedir_init ()
{
  ${xctx:?}@User/Conf :basedirtab &&
  ${xctx:?}@User/Dir :init-basedir "${basedirtab:?}"
}

us_stbtab_init ()
{
  class_init StatTab{,Entry} &&
  class_new stbtab StatTab "${STTAB:?}" ||
    $LOG error : "Failed to load stattab index" "E$?:$STTAB" $?
}

us_class_init ()
{
  user_script_initlibs std-uc uc-class class-uc
}

us_stdenv_init ()
{
  #lib_load stattab-class &&
  class_init StatTab
}

us_userconf_init ()
{
  [[ ${user_conf-} ]] || {
    class_init User/Conf &&
    class_new user_conf $_
  }
}

us_userdir_init ()
{
  local lk=${lk:-}:us-fun.lib:usrdir-init
  # XXX: add user-dir as field on context somehow? Or fix query menchanism on
  # XContext, ie. so it implements (constructs, etc) and remembers each
  # supported type.
  #@User/Dir :init
  #${xctx:?}@User/Dir :init
  class_init User/Dir &&
  class_new user_dir User/Dir "${1:-${PWD:?}}"
}

us_xctx_init ()
{
  local lk=${lk:-}:us-fun.lib:xctx-init
  class_init XContext &&
  class_new xctx XContext
}

us_xctx_switch () # ~ <Default-context> <User-provided...>
{
  declare defctx=${1:-@List} lk=${lk:-}:us-fun.lib:xctx-switch
  shift

  # Use tagref as user provided context
  test -n "${1-}" &&
  fnmatch "@*" "$_" && {
    uref=$1
    fnmatch "[A-Z]*" "${uref:1}" && {
      $LOG info "$lk" "User selected context class" "$_"
      ctxclass=$_
    # TODO: look to table for ctx=$_
    } || return 0
  } || {
    ctxclass=${defctx:1}
  }

  # Query to default or requested xcontext
  : "ctxref=${ctxref:-xctx} $xctx@$ctxclass"
  $LOG debug "$lk" "Switching context class" "$_"
  ${xctx:?}@${ctxclass:?}

  $LOG notice "$lk" "Context ready" "E$?:$xctx@$ctxclass" $?
}

#
