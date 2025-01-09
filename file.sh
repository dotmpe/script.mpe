#!/usr/bin/env bash

us-env -r us:boot.screnv &&

us-env -r user-script || ${us_stat:-exit} $?

! script_isrunning "file" .sh ||
  uc_script_load us-als-mpe || ${us_stat:-exit} $?


file_ ()
{
  local a1_def=summary; sa_switch_arg
  case "$switch" in

  ( ml|modeline )
      lib_require sys os str-uc || return
      declare file{version,id,mode}
      fml_lvar=true file_modeline "$1" &&
      {
        : "file:${1-}"
        : "$_${fileid:+:id=$fileid}"
        : "$_${fileversion:+:ver=$fileversion}"
        : "$_${filemode:+:mode=$filemode}"
        $LOG notice "" "Modeline" "$_"
      }
    ;;

    * ) sa_E_nss
  esac
  __sa_switch_arg
}

# XXX: temp while user-script node scan is being rebuild
set -euETo pipefail
lib_require ck

#declare -p VERBOSE QUIET
: "${file_sh_cachefp:=${STATUSDIR_ROOT:?}cache/file-sh.cache.bash}"

declare -gA __file_stat_cache
[[ -s "${file_sh_cachefp:?}" ]] && {
  file_sh_cache_startload=$(date +%s)
  . "$file_sh_cachefp" ||
    $LOG alert : "Loading cache" E$? 3
  file_sh_cache_load=$(( $(date +%s) - $file_sh_cache_startload ))
  ! "${VERBOSE:-false}" ||
  stderr echo Cache loading took $file_sh_cache_load seconds
}

file_scan () # ~ <Path>
{
  [[ $# -gt 0 ]] && {
    if_ok "$(realpath "${1:?}")" &&
    set -- "$_" || return
  } || {
    set -- $PWD
  }

  [[ -h $1 ]] && {
    # XXX:
    file_scan "$(realpath "${1:?}")" || return
  } || {
    # XXX:
    local _super
    [[ $1 = / ]] || os_filestat_read "$(dirname "$1")" inode-number:_super
    [[ -d $1 ]] && {
      file_scan_directory "${_super:-0}" "${1:?}"
    } || {
      local _{fk,mik,stat,{c,a,m}time,blocks{,ize},inode,mount,real,size,type,paths}
      file_scan_pathcache "${1:?}" && {
        file_scan__readcache "${1:?}" || return
      } || {
        file_scan__cachestat "${1:?}" || return
      }
    }
  }
}

file_scan_directory () # ~ <ROOTNODE> <PATH>
{
  local _super=${1:?} _dirpath=${2:?}

  local i _{fk,mik,stat,{c,a,m}time,blocks{,ize},inode,mount,real,size,type,paths}
  if_ok "$(find "${_dirpath:?}" -mindepth 1 -maxdepth 1 -not -name '.*')" &&
  test -n "$_" &&
  mapfile -t _paths <<< "$_" &&
  for ((i=0; i<${#_paths[*]}; i++))
  do
    file_scan_pathcache "${_paths[i]}" && {
      test 1 -eq $? || return $_

      file_scan__readcache "${_paths[i]}" || return
      continue
    } || {

      file_scan__cachestat "${_paths[i]}" || return
    }
  done &&

  arr_dump __file_stat_cache > "${file_sh_cachefp:?}"
}

file_scan_pathcache ()
{
  _fk=$(<<< "${1:?}" ck_sha1) || return 3
  test -n "${__file_stat_cache["file.sh:cache:$_fk.path.sha1"]-}"
}

file_scan__readcache () # (fs) ~
{
  _mik=${__file_stat_cache["file.sh:cache:$_fk.path.sha1"]} &&
  _stat=${__file_stat_cache["file.sh:cache:$_mik.stat"]} &&
  <<< "$_stat" read -r _{stat,type,alloc,size,{a,c,m}time} &&
  _inode=${_mik:41}
  #stderr declare -p _{inode,stat,type,alloc,size,{a,c,m}time}
}

file_scan__cachestat () # (fs) ~
{
  os_filestat_read "${1:?:?}" \
    inode-number:_inode \
    mount-point:_mount \
    quoted-symref:_real \
    file-type:_type \
    byte-size:_size \
    allocated-blocks:_blocks \
    block-size:_blocksize \
    ctime:_ctime atime:_atime mtime:_mtime

  #stderr declare -p _{inode,real,type,size,blocks{,ize}}

  case $_type in
  ( 'regular file' ) ;;
  ( 'directory' )
      file_scan_directory "${_super}" "${1:?}"
      return
    ;;
    * ) return
  esac

  _mik=$(<<< "${_mount}" ck_sha1):$_inode || return
  __file_stat_cache["file.sh:cache:$_fk.path.sha1"]=$_mik

  _alloc=$(( _blocks * _blocksize ))

  #[[ ${__file_stat_cache["file.sh:cache:$_mik.stat"]:+set} ]] ||
  _stat=file\ $_alloc\ $_size\ $_atime\ $_ctime\ $_mtime

  [[ $_alloc -ge $_size ]] && {
    _stat=0\ $_stat
    ! "${VERBOSE:-false}" ||
      echo "OK. ${_fk} -> ${_mik}"
    #echo "OK. ${1:?}"
  } || {
    # XXX: sparse?
    _stat=4\ $_stat
    ! "${VERBOSE:-false}" ||
      echo "Sparse? ${_fk} -> ${_mik}"

    # Should be same as stat bytes field
    #: "$(du -b "${1:?}")"
    #_du="${_%$'\t'*}"
    #echo "  :Size:  $_size"
    #echo "  :Alloc: $_alloc"
    #echo "  :Du:    ${_du}"
  }
  __file_stat_cache["file.sh:cache:$_mik.stat"]=$_stat
}


## User-script parts

file_name=File.sh
file_version=0.0.0-alpha
#file_shortdescr=""
#file_defcmd=short
#file_maincmds=""

#file_aliasargv ()
#{
#  test -n "${1:-}" || return ${_E_MA:?}
#  case "${1//_/-}" in
#    * ) set -- file_ "$@"
#  esac
#}

# Main entry (see user-script.sh for boilerplate)

! script_isrunning "file" .sh || {
  user_script_load || exit $?
  # Default value used if argv is empty
  user_script_defarg=defarg\ aliasargv
  # Resolve aliased commands or set default
  eval "set -- $(user_script_defarg "$@")"
  script_run "$@"
}
