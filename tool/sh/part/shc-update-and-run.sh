# Refresh compiled scripts behind alias automatically
_shc_update_and_run ()
{
  test -s "$b.sh" ||
    $LOG error :-shc-update-and-run "No such b" "E$?:b=$b" 64 || return
  test $b.shc -nt $b.sh || {
    make_echo=1 $b.sh >| $b.shc.tmp
    test -s $b.shc &&
    diff -bqr $b.shc{,.tmp} >/dev/null || {
      cat $b.shc.tmp >| $b.shc || return
      $LOG "note" "" "Updated box script, regenerated" "$b.shc"
    }
    rm $b.shc.tmp
    test -x $b.shc || chmod +x $b.shc
  }
  "$b".shc "$@"
}
