redo-always
scriptpath=$REDO_BASE . $REDO_BASE/util.sh &&
  lib_load &&
  scriptname="do:$REDO_PWD:$1" &&
  cd "$REDO_BASE" &&
  lib_load build-test &&
  build_test_init &&
  for dep in $package_specs_required
  do
      set -- "$1" "$2" "$3" "$cllct_test_base/$dep.tap"
      grep -qv '^not ok ' "$4" 2>/dev/null && {
        redo-ifchange "$4" || error "$4" 1
      } || {
        redo "$4" || error "$4" 1
      }
  done
  for dep in $package_specs_required
  do
      set -- "$1" "$2" "$3" "$cllct_test_base/$dep.tap"
      test -s "$4" || {
        warn "Empty suite '$dep' ($4)"
        continue
      }
      grep -q '^not ok ' "$4" && {
        error "Failed tests '$dep'" 1
      } || true
  done
