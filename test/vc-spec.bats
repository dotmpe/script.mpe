#!/usr/bin/env bats

load helper
load vc
base=vc.sh
init


@test "$bin no arguments no-op" {
  run $bin
  test $status -eq 0
}

@test "$bin help" "prints help" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin commands" "prints commands" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin version" "prints version" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin list-prefixes" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin uf" "prints unversioned files" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin ufx" "prints unversioned and excluded files" {
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
}

@test "$bin ps1" {

  cd $TMPDIR
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  test "$TMPDIR" = "${lines[*]}" || {
    diag "TMPDIR:'${TMPDIR}'"
    diag "BATS_TMPDIR:'${BATS_TMPDIR}'"
    fail "Lines: '${lines[*]}'"
  }
}

@test "$bin screen" {
  cd $TMPDIR
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  test "$TMPDIR" = "${lines[*]}"
}

@test "$bin bits" {

  export GIT_PS1_DESCRIBE_STYLE=(contains)
  export GIT_PS1_SHOWSTASHSTATE=1
  export GIT_PS1_SHOWDIRTYSTATE=1
  export GIT_PS1_SHOWUNTRACKEDFILES=1

  local owd=$(pwd)
  setup_clean_git
  local twd=$(pwd)

  run $BATS_TEST_DESCRIPTION
  test $status -eq 0

  #diag "SHELL: $SHELL"

  shopt -s extglob
  fnmatch $(cd $twd; pwd -P)' \[git:master +([0-9a-f])...\]' "${lines[*]}" \
    || fail "'${lines[*]}'"

  mkdir doc
  cd doc
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0

  fnmatch $twd' \[git:master +([0-9a-f])...\]/doc' "${lines[*]}" \
    || fail "Output: ${lines[*]} ($twd)"

  cd $twd
  echo ignore > .gitignore

  #diag "$(git status)"
  #diag "${lines[*]}"

  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\* +([0-9a-f])...\]' "${lines[*]}"

  cd doc
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\* +([0-9a-f])...\]/doc' "${lines[*]}"

  cd $twd
  touch README

  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\*~ +([0-9a-f])...\]' "${lines[*]}" \
    || fail "'${lines[*]}: $(git status)'"

  cd doc
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\* +([0-9a-f])...\]/doc' "${lines[*]}"

  cd $twd
  touch CHANGELOG
  git add README

  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\*\+~ +([0-9a-f])...\]' "${lines[*]}" \
    || fail "'${lines[*]}: $(git status)'"

  cd doc
  run $BATS_TEST_DESCRIPTION
  test $status -eq 0
  fnmatch $twd' \[git:master\*\+ +([0-9a-f])...\]/doc' "${lines[*]}" \
    || fail "'${lines[*]}: $(git status)'"

  shopt -u extglob
}


# vim:ft=sh:
