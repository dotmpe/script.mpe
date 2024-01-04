# See meta.lib
# Extension on statusdir to track local indices with potential to update
# from/to global files (in user/system statusdir)

metadir_lib__load ()
{
  lib_require os-htd stattab-uc || return

  : "${metadirs_default:="\{,.}meta"}"
  : "${METADIRS_TAB:=${STATUSDIR_ROOT:?}index/metadirs.tab}"
}

metadir_lib__init ()
{
  test -z "${metadir_lib_init:-}" || return $_

  local found=false
  test -n "${metadir_default:-}" || {
    for metadir_default in $(eval echo ${metadirs_default:?})
    do
      test -e "$metadir_default" && { found=true; break; }
    done
  }
  $found || test -e "$metadir_default" || return
  #create metadirs StatTab $METADIRS_TAB
  #$LOG info :metadir.lib:init "Loaded" "E$?" $?
}


metadir_basedirs () # ~ <Paths...>
{
  foreach "${@:?}" | foreach_line_do fs_basedir_with ${metadir_default:?}
}


# XXX: find dir with marker leaf. See os.lib:go_to_dir_with.
fs_basedir_with () # ~ <Sub> <Path>
{
  local path=${2:?}
  while test "$path" != "/"
  do
    test -e "$path/${1:?}" && {
      echo "$path"
      return
    }
    path=$(dirname "$path")
  done
  return 1
}

#
