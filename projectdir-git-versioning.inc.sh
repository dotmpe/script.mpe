
pd_register git-versioning check init


pd_check__git_versioning_autoconfig()
{
  test -x "$(which git-versioning 2>/dev/null)" || return 1
  test -e .versioned-files.list && {
    echo :git-versioning
  } || return 0
}

pd_als__vchk=git-versioning

#pd__git_versioning_check()
#{
#  git-versioning check
#}


pd_load__git_versioning=i
pd__git_versioning()
{
  test -n "$1" || set -- check
  test -n "$io_id" || local io_id="-$base-$subcmd-$(uuidgen)"
  test -n "$vchk" || local vchk=$(setup_tmpf .vchk $io_id)
  local result=0 mismatches=
  git-versioning "$@" 2>&1 | tee $vchk
  mismatches="$(grep 'Version.mismatch' $vchk | count_lines )"
  states="matches=$(grep 'Version.match' $vchk | count_lines )"
  states="$states mismatches=$mismatches"
  test $mismatches -eq 0 || {
    result=1
    grep 'Version.mismatch' $vchk \
      | sed 's/Version.mismatch.in./pd:vchk:/' >$failed
    #1>&6
  }
  rm $vchk
  return $result
}


