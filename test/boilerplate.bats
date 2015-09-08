#!/usr/bin/env bats

load helper
base=boilerplate

init_lib
init_bin


@test "${bin} -vv -n help" {
  skip "envs: envs=$envs FIXME is hardcoded in test/helper.bash current_test_env"
  check_skipped_envs || \
    skip "TODO envs $envs: implement bin (test) for env"
  run $BATS_TEST_DESCRIPTION
  test ${status} -eq 0
  test -z "${lines[*]}" # empty output
  test "${#lines[@]}" = "0" # lines of output (stderr+stderr)
}

@test "${lib}/main function should ..." {
  check_skipped_envs || \
    skip "TODO envs $envs: implement lib (test) for env"
}

# vim:et:ft=sh:
