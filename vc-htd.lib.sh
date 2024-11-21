#!/bin/sh

# Htd ctx cleanup for vc wip


vc_htd_lib__load ()
{
  lib_require sys-htd || return
  # XXX: std.lib
  test -n "${vc_rt_def-}" || vc_rt_def=origin
  test -n "${vc_br_def-}" || vc_br_def=master
}

vc_htd_lib__init ()
{
  test -z "${vc_htd_lib_init:-}" || return $_  # Run once
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized vc-htd.lib" "$(sys_debug_tag)"
}


# Macro to generate another macro. Generates a function to wrap getting/setting
# values.
#sh_gen_descr prefix [name=<prefix>_]

# Macro where key is either part of function name or variable. Either must
# exist.
vc_ () # ~ <Key> [<New-value> [<...>]]
{
  test 0 -lt $# || return ${_E_GAE:?}
  local update
  test 1 -lt $# && update=true || update=false
  : "vc_${1:?}"
  sh_fun "$_" && {
    "$_" "${@:2}"
    return
  }
  "$update" "$_" && {
    # XXX: could use $#>2 as varaible array els, but need more actions as well
    declare -g "$_=$2" &&
      test 2 -eq $#
    return
  } || {
    test -n "${!_}" && echo "$_" || {
      : "vc_${1}_def"
      echo "${!_}"
    }
  }
}


# See if path is in GIT checkout
vc_isgit()
{
  test -e "$1" || error "vc-isgit expected path argument: '$1'" 1
  test -z "$2" || error "vc-isgit surplus arguments: '$2'" 1
  test -d "$1" || {
    set -- "$(dirname "$1")"
  }
  ( cd "$1" && go_to_dir_with .git || return 1 )
}

# Echo absolute location of (root) .git repo, be silent otherwise
# Note this is the repo for the root checkout, not for submodules.
vc_gitdir()
{
  test $# -eq 0 || { local oldpwd="$PWD"; cd "$1"; }

  repo=$(git rev-parse --git-dir 2>/dev/null)
  while fnmatch "*/.git/modules*" "$repo"
  do repo="$(dirname "$repo")" ; done
  test -n "$repo" || return 1
  echo "$repo"
  #repo="$(git rev-parse --show-toplevel)"
  #echo $repo/.git

  test $# -eq 0 || cd "$oldpwd"
}

# Echo the repository dir for current checkout. Gives .git/modules sub-dir
# for GIT submodules.
vc_gitrepo()
{
  test $# -eq 0 || { local oldpwd="$PWD"; cd "$1"; }

  git rev-parse --git-dir || return
  test $# -eq 0 || cd "$oldpwd"
}

vc_hgdir()
{
  test -d "$1" || error "vc-hgdir expected dir argument: '$1'" 1
  ( cd "$1" && go_to_dir_with .hg && echo "$PWD"/.hg || return 1 )
}

vc_issvn()
{
  test -d "$1" || error "vc-issvn expected dir argument: '$1'" 1
  test -e "$1"/.svn
}

vc_svndir()
{
  test -d "$1" || error "vc-svndir expected dir argument: '$1'" 1
  ( test -e "$1/.svn" && echo $PWD/.svn || return 1 )
}

vc_bzrdir()
{
  test -d "$1" || error "vc-bzrdir expected dir argument: '$1'" 1
  (
    cd "$1"
    root=$(bzr info 2> /dev/null | grep 'branch root')
    if [ -n "$root" ]; then
      echo "$root"/.bzr | sed 's/^\ *branch\ root:\ //'
    fi
  )
  return 1
}

# Auto-detect SCM system at directory, in order: GIT, BazaarNG, Subversion,
# Mercurial. To start specific SCM directly call 'vc_<scmid>dir "$@"'.
vc_dir()
{
  test -n "${1-}" || set -- $PWD
  test -d "$1" || error "vc-dir expected dir argument: '$1'" 1
  test -z "${2-}" || error "vc-dir surplus arguments: '$2'" 1
  vc_gitdir "$1" && return
  vc_bzrdir "$1" && return
  vc_svndir "$1" && return
  vc_hgdir "$1" && return
  return 1
}

vc_isscmdir()
{
  test -n "${1-}" || set -- "."
  test -d "$1" || error "vc-isscmdir expected dir argument: '$1'" 1
  vc_isgit "$1" && return
  vc_isbzr "$1" && return
  vc_issvn "$1" && return
  vc_ishg "$1" && return
  return 1
}

vc_scmdir()
{
  vc_dir "$@" || error "can't find SCM-dir" 1
}

# Lookup vc-dir
vc_getscm() # [PWD]
{
  scmdir="$(vc_dir "$@")"
  test -n "$scmdir" || return 1
  scm="$(basename "$scmdir" | cut -c2-)"
}


vc_fsck_git()
{
  # XXX: has no exit-code, only diagnostic output
  #git --strict fsck
  git fsck
}

vc_fsck()
{
  test -n "${scm-}" || vc_getscm
  vc_fsck_${scm}
}


vc_remotes_git()
{
  test -n "${1-}" && {
    git config --get remote.$1.url
    return $?
  } || {
    git remote
  }
}

vc_remotes_hg()
{
  hg paths "$@"
}

vc_remotes() # DIR [NAME]
{
  test -z "$3" || error "vc-remote surplus arguments" 1
  local pwd=$PWD r=
  test -z "$1" || {
    cd "$1"
    vc_getscm
  }
  test -z "$2" && {
      vc_remotes_$scm || r=$?
    } || {
      vc_remotes_$scm "$2" || r=$?
    }
  test -z "$1" || {
    cd "$pwd"
  }
  return $?
}


vc_ls_remote_git()
{
  test -n "$1" || error "remote expected" 1
  git ls-remote "$1"
}

vc__ls_remote()
{
  test -n "${scm-}" || vc_getscm
  vc_ls_remote_${scm} "$@"
}



# Return table for all repos on stdin
vc_dirtab()
{
  while read -r dirpath
  do
    remotepath="$(dirname "$dirpath")"
    vendor="$(dirname "$remotepath")"
    account_handle="$(basename "$remotepath")"
    project_name="$(basename "$dirpath")"

    vc_remotes "$dirpath" | while read -r remote_name
    do
      remote_url="$(vc_remotes "$dirpath" "$remote_name")"
      echo "$remote_name $remote_url $project_name $account_handle $vendor"
    done
  done
}

vc_remote_dirs() # [FMT] [DIR] []
{
  test -n "$2" || set -- "$1" "." "$3"

  vc_remotes "$2" "$3" | while read -r remote
  do
    case "$1" in
      '')
        echo $remote $(git config remote.$remote.url);;
      sh|var)
        echo $remote=$(git config remote.$remote.url);;
      *)
        error "illegal $1" 1;;
    esac
  done
}

vc_remote_git()
{
  git config --get remote.$1.url
}

vc_remote_hg()
{
  hg paths "$1"
}

vc_remote()
{
  test -n "$1" || set -- "." "origin"
  test -d "$1" || error "vc-remote expected dir argument" 1
  test -n "$2" || error "vc-remote expected remote name" 1
  test -z "$3" || error "vc-remote surplus arguments" 1

  local pwd=$PWD
  cd "$1"
  vc_remote_$scm "$2"
  cd "$pwd"
}

# Given COPY src and trgt file from user-conf repo,
# see if target path is of a known version for src-path in repo,
# and that its the currently checked out version.
vc_gitdiff()
{
  test -n "${1-}" || error "vc-gitdiff expected src" 98
  test -n "${2-}" || error "vc-gitdiff expected trgt" 98
  test -z "${3-}" || error "vc-gitdiff surplus arguments: '$3'" 98
  test -n "$GITDIR" || error "vc-gitdiff expected GITDIR env" 1
  test -d "$GITDIR" || error "vc-gitdiff GITDIR env is not a dir" 1

  target_sha1="$(git hash-object "$2")"
  co_path="$(cd $GITDIR;git rev-list --objects --all | grep "^$target_sha1" | cut -d ' ' -f 2)"
  test -n "$co_path" -a "$1" = "$GITDIR/$co_path" && {
    # known state, file can be safely replaced
    test "$target_sha1" = "$(git hash-object "$1")" \
      && return 0 \
      || {
        return 1
      }
  } || {
    return 2
  }
}


vc_unversioned_git()
{
  git ls-files --others --exclude-standard --dir "$@"
}

vc_unversioned_bzr()
{
  bzr ls --unknown "$@"
}

vc_unversioned_svn()
{
  svn status | grep '^?' | sed 's/^?\ *//g'
}

vc_unversioned_hg()
{
  hg status --unknown "$@" | cut -c3-
}

# List untracked paths (excluding ignored files)
vc_unversioned()
{
  pwd_p && push_pwd || pwd_init # Start tracking PWD on PWP stack.

  test -n "${scm-}" || vc_getscm # Get scm-id/scm-dir

  # list paths not in git (including ignores)
  vc_unversioned_$scm "$@"

  test "$scm" = "git" && {

    vc_git_submodules | while read prefix
    do
      push_pwd $prefix

      vc_unversioned "$@" \
          | grep -Ev '^\s*(#.*|\s*)$' \
          | sed 's#^#'"$prefix"'/#'

      pop_pwd
    done
  }

  pop_pwd || true
}


vc_untracked_bzr()
{
  bzr ls --ignored --unknown "$@"
}

vc_untracked_git()
{
  git ls-files --others --dir "$@" || return $?
}

vc_untracked_svn()
{
  { svn status --no-ignore "$@" || return $?
  } | grep '^?' | sed 's/^?\ *//g'
}

vc_untracked_hg()
{
  hg status --ignored --unknown "$@" | cut -c3-
}

# List any untracked paths (including ignored files)
vc_untracked()
{
  pwd_p && push_pwd || pwd_init # Start tracking PWD on PWP stack.

  test -n "${scm-}" || vc_getscm # Get scm-id/scm-dir

  vc_untracked_$scm "$@"

  test "$scm" = "git" && {

    vc_git_submodules | while read prefix
    do
      push_pwd $prefix

      vc_untracked "$@" \
          | grep -Ev '^\s*(#.*|\s*)$' \
          | sed 's#^#'"$prefix"'/#'

      pop_pwd
    done
  }

  pop_pwd || true
}


vc_tracked_git() # [REV] -- [PATH]
{
  git ls-files "$@"
}

vc_tracked_bzr()
{
  bzr ls -R "$@"
}

vc_tracked_svn()
{
  { svn list --depth infinity "$@" || return $?
  } | grep '^?' | sed 's/^?\ *//g'
}

vc_tracked_hg()
{
  { hg status --clean --modified --added "$@" || return $?
  } | cut -c3-
}

# List file tracked in version
vc_tracked()
{
  pwd_p && push_pwd || pwd_init # Start tracking PWD on PWP stack.

  test -n "${scm-}" || vc_getscm # Get scm-id/scm-dir

  # list paths under version control
  vc_tracked_$scm "$@"

  # submodules too for GIT
  test "$scm" = "git" && {

    vc_git_submodules | while read prefix
    do
      push_pwd $prefix

      vc_tracked_git "$@" \
          | { grep -Ev '^\s*(#.*|\s*)$' || true; }\
          | sed 's#^#'"$prefix"'/#'

      pop_pwd
    done
  }

  pop_pwd || true
}


vc_staged_git()
{
  git diff --name-only --cached
}
vc_staged_hg() { false; }
vc_staged_svn() { false; }
vc_staged_bzr() { false; }

# List staged files
vc_staged()
{
  test -n "${scm-}" || vc_getscm
  vc_staged_${scm}
}


vc_modified_git()
{
  git ls-files --modified
}
vc_modified_hg() { false; }
vc_modified_svn() { false; }
vc_modified_bzr() { false; }

# List modified files
vc_modified()
{
  test -n "${scm-}" || vc_getscm
  vc_modified_${scm} "$@"
}


vc_git_annex_list()
{
  git annex list "$@" | grep '^[_X]*\ ' | sed 's/^[_X]*\ //g'
}


vc_branch_git()
{
  git rev-parse --abbrev-ref HEAD
}

vc_branch_hg()
{
  hg identify -b
}

vc_branch_svn()
{
  url=$(svn info | grep '^Relative URL:') && {

    echo "$url" | cut -c15-
  } || {
    url=$(svn info | grep '^URL:') && {

        echo "$url" | cut -c6-
    } || error "No URL found in 'svn info'" 1
  }
}

vc_branch_bzr() { false; }

# Print checked out branch
vc_branch()
{
  vc_branch_${scm} "$@"
}


vc_branches_git()
{
  test 0 -lt $# || set -- refs/heads
  test "$1" != "all" || set -- refs/heads "refs/remotes/$(vc_ rt)"
  git for-each-ref --format='%(refname:short)' "$@" |
      grep -v HEAD | sed 's/^'"$(vc_ rt)"'\///g' | sort -u
}
vc_branches_hg()
{
  test "$1" != "all" && {
    hg branches | cut -f1 -d' '
  } || {
    # NOTE: remote branches is not as straightforward
    # <https://stackoverflow.com/questions/4296636/list-remote-branches-in-mercurial/11900786>
    error "hg-remotes" 1
  }
}
vc_branches_svn() { false; }
vc_branches_bzr() { false; }

# Print branche refs for local or all branches. Only checks primary 'remote'
# repo, should inspect every remote to find possible non-distributed branches.
vc_branches()
{
  vc_branches_${scm} "$@"
}

vc_list_all_branches()
{
  vc_branches all
}


vc_git_submodules() #
{
  git submodule foreach | sed "s/.*'\(.*\)'.*/\1/" | while read prefix
  do
    test -e $PWD/.git || {
      warn "Not a submodule checkout '$prefix' ($CWD/$prefix)"
      continue
    }
    trueish "${quiet-}" || note "Submodule '$prefix' ($CWD/$prefix)"
    echo "$prefix"
  done
}


# Add new remote, or update existing with different URL. Strip .git suffix.
vc_git_update_remote() # Name URL
{
  local remote_url="$(git config --get remote.$1.url)"
  test -z "$remote_url" && {

    git remote add "$1" "$2" &&
        note "Remote '$1' added" || warn "Error adding '$1' remote" 1

  } || {

    test "$2" = "$remote_url" || {
      git remote set-url "$1" "$2" &&
        note "Remote '$1' updated" || warn "Error updating '$1' remote" 1
    }
  }
}


vc_roots_git()
{
  git rev-list --max-parents=0 HEAD
}

vc_roots_hg()
{
  vc_branches_hg | while read branch
  do
    set -- "$(printf -- "min(branch(%s))" "$branch")"
    hg log -r "$@"  --template '${node}'
  done
}

vc_roots()
{
  test -n "${scm-}" || vc_getscm
  vc_roots_${scm} "$@"
}


# Get commit date as seconds in Unix epoch
# vc_epoch_*

vc_epoch_git() # Commit
{
  set -- $( git rev-list --max-parents=0 HEAD )
  git show -s --format=%ct "$1"
}

vc_epoch_hg()
{
  hg log -r "min(branch(default))"  --template '{date(date|localdate, "%s")}\n'
}


vc_age_git()
{
  set -- $( vc_epoch_git )
  fmtdate_relative "$1" "" "\n"
}

vc_age_hg()
{
  set -- $( vc_epoch_hg )
  fmtdate_relative "$1" "" "\n"
}


vc_diskuse_git()
{
  test -d .git/annex && {
    du -hs . .git/objects .git/annex
  } || {
    du -hs . .git/objects .git
  }
}

vc_diskuse()
{
  test -n "${scm-}" || vc_getscm
  vc_diskuse_${scm} "$@"
}


vc_status_git()
{
  # Forced color output commands
  #git -c color.status=always status
  test -d .git/annex && {
    git annex unused
  }
  vc_git_submodules | while read prefix
  do
    # Enabled?
    test -d "$prefix" || continue
    echo "$prefix: $(cd "$prefix" && vc status)"
  done
  echo "$(vc_flags_${scm})"
}
vc_status_hg() { false; }
vc_status_svn() { false; }
vc_status_bzr() { false; }

# Report on various checkout/repo state
vc_status()
{
  vc_status_${scm} "$@"
}


# XXX: Cleanup the checkout, and report on the state
vc_clean()
{
  (
  trueish "$1" && {
      vc_unversioned
    } || {
      vc_untracked
    }
  )
}


vc_check_git()
{
  test -n "${1-}" || set -- .git
  # There should be a head
  # other checks on .git/refs seem to fail after garbage collect
  git rev-parse HEAD >/dev/null ||
  test "$(echo $1/refs/heads/*)" != "$1/refs/heads/*" ||
  test "$(echo $1/refs/remotes/*/HEAD)" != "$1/refs/remotes/*/HEAD"
}

# __vc_git_flags accepts 0 or 1 arguments (i.e., format string)
# returns text to add to bash PS1 prompt (includes branch name)
vc_flags_git()
{
  test -n "$1" || set -- "$PWD"
  g="$(vc_gitdir "$1")"
  test -e "$g" || return

  vc_check_git "$g" || {
    echo "(!git:unborn)"
    return
  }

  cd "$1"
  std_quiet git status -s || {
    echo "(!git:E$?)"
    return
  }
  local r b

  if [ -f "$g/rebase-merge/interactive" ]; then
    r="|REBASE-i"
    b="$(cat "$g/rebase-merge/head-name")"
  elif [ -d "$g/rebase-merge" ]; then
    r="|REBASE-m"
    b="$(cat "$g/rebase-merge/head-name")"
  else
    if [ -d "$g/rebase-apply" ]; then
      if [ -f "$g/rebase-apply/rebasing" ]; then
        r="|REBASE"
      elif [ -f "$g/rebase-apply/applying" ]; then
        r="|AM"
      else
        r="|AM/REBASE"
      fi
    elif [ -f "$g/MERGE_HEAD" ]; then
      r="|MERGING"
    elif [ -f "$g/BISECT_LOG" ]; then
      r="|BISECTING"
    fi

    b="$(git symbolic-ref HEAD 2>/dev/null)" || {

      b="$(
      case "${GIT_PS1_DESCRIBE_STYLE-}" in
      (contains)
        git describe --contains HEAD ;;
      (branch)
        git describe --contains --all HEAD ;;
      (describe)
        git describe HEAD ;;
      (* | default)
        git describe --exact-match HEAD ;;
      esac 2>/dev/null)" ||

      b="$(cut -c1-11 "$g/HEAD" 2>/dev/null)" || b="unknown"
      # XXX b="($b)"
    }
  fi

  local w= i= s= u= c=

  if [ "true" = "$(git rev-parse --is-inside-git-dir 2>/dev/null)" ]; then
    if [ "true" = "$(git rev-parse --is-bare-repository 2>/dev/null)" ]; then
      c="BARE:"
    else
      b="DIR!"
    fi
  elif [ "true" = "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
    if [ -n "${GIT_PS1_SHOWDIRTYSTATE-}" ]; then

      if [ "$(git config --bool bash.showDirtyState)" != "false" ]; then

        git diff --no-ext-diff --ignore-submodules \
          --quiet --exit-code || w='*'

        if git rev-parse --quiet --verify HEAD >/dev/null; then

          git diff-index --cached --quiet \
            --ignore-submodules HEAD -- || i="+"
        else
          i="#"
        fi
      fi
    fi
    if [ -n "${GIT_PS1_SHOWSTASHSTATE-}" ]; then
      git rev-parse --verify refs/stash >/dev/null 2>&1 && s="$"
    fi

    if [ -n "${GIT_PS1_SHOWUNTRACKEDFILES-}" ]; then
      if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        u="~"
      fi
    fi
  fi

  repotype="$c"
  branch="${b##refs/heads/}"
  modified="$w"
  staged="$i"
  stashed="$s"
  untracked="$u"
  state="${r-}"

  x=
  rg=$g
  test -f "$g" && {
    g=$(dirname $g)/$(cat .git | cut -d ' ' -f 2)
  }

  # TODO: move to extended escription cmd
  #x="; $(git count-objects -H | sed 's/objects/obj/' )"

  if [ -d $g/annex ]; then
    #x="$x; annex: $(echo $(du -hs $g/annex/objects|cut -f1)))"
    x="$x annex"
  fi

  b="${b##refs/heads/}"

  test -n "${2-}" && fmt="$2" || fmt='(%s%s%s%s%s%s%s%s)'
  printf "$fmt" "$c" "$b${b+ }" "$w" "$i" "$s" "$u" "${r-}" "$x"
  #               |    |          |    |    |    |     |      extensions: annex
  #               |    |          |    |    |    |   current-op
  #               |    |          |    |    |  untracked
  #               |    |          |    |   stash
  #               |    |          |  stage
  #               |    |      modified
  #               |  branch-ref
  #             repo-type
}


# Generate statistics for repository:
vc_stats() # [ Dir=. [ Initial-Indent="  " ] ]
{
  test -n "$1" || set -- "." "$2"
  test -n "$2" || set -- "$1" "  "

  {
    cd "$1"
    tracked_files=$( vc_tracked | count_lines )
    untracked_files=$( vc_unversioned | count_lines )
    untracked_cleanable=$( vc__unversioned_cleanable_files | count_lines )
    untracked_temporary=$( vc__unversioned_temporary_files | count_lines )
    untracked_uncleanable=$( vc__unversioned_uncleanable_files | count_lines )
    total_untracked_files=$( vc_untracked | count_lines )

    { cat <<EOM
$2lines:
$2  unique-lines: $(
$2    vc_tracked | while read f; do test -f "$f" && cat "$f" || continue ; done | LC_ALL=C sort -u | count_lines )
$2  (total): $(
$2    vc_tracked | while read f; do test -f "$f" && cat "$f" || continue ; done | count_lines )
$2files:
$2  tracked: $tracked_files
$2  untracked:
$2    unversioned: $untracked_files
$2    cleanable: $untracked_cleanable
$2    temporary: $untracked_temporary
$2    uncleanable: $untracked_uncleanable
$2    (total): $total_untracked_files
$2    (total): $(( $untracked_cleanable + $untracked_temporary + $untracked_uncleanable ))
$2  (total): $(( $tracked_files + $total_untracked_files ))
EOM
    }

    test -d "$1/.$scm/annex" && {
      printf "$2  annex:\n"
      printf "$2    files: $( vc_git_annex_list | count_lines )\n"
      printf "$2    here: $( vc_git_annex_list -i here | count_lines )\n"
      printf "$2    unused: $( git annex unused | count_lines )\n"
    }

    printf "$2(date): $( date_microtime )\n"
  }
}


vc_info()
{
  test -n "${1-}" || set -- "." "  "
  test -n "${PACK_SH-}" -a -s "${PACK_SH-}" && {

    note "Sourcing '$PACK_SH'..."
    . "$PACK_SH"
    cat <<EOM
$2spec: $package_id/$package_version
$2id: $package_id
$2version: $package_version
$2vendor: $package_vendor
$2pd-meta:
$2  tasks:
$2    document: $package_pd_meta_tasks_document
$2    done: $package_pd_meta_tasks_done
EOM

    test -e "$PACK_JSON" || error "Expected package main JSON" 1
    note "Checking '$PACK_JSON'..."
    jsotk.py -sq path --is-new $PACK_JSON 'urls' || {
      printf "$2urls:\n"
      htd_package_urls | grep -v '^\s*$' | sed 's/^\([^=]*\)=/'"$2"'  \1: /'
    }
  }

  cat <<EOM
$2status-flags: $(vc_flags_${scm} "$1" "%s%s%s%s%s%s%s%s"  )
$2type: $scm
$2age: '$(vc_age_$scm) ($(date_iso $(vc_epoch_$scm)))'
$2default: $package_default
EOM

  printf -- "$2roots:\n"
  { cd "$1" && vc_roots_${scm} ; } | while read name
  do
    printf -- "$2- $name\n"
  done

  printf -- "$2remotes:\n"
  { cd "$1" && vc_remotes_${scm} ; } | while read name
  do
    printf -- "$2  $name:\n"
    printf -- "$2    description: $package_description\n"
    printf -- "$2    sync: \n"
    printf -- "$2    url: $(vc_${scm}remote "$1" $name)\n"
  done

  # TODO: created, updated, first-commit dates

  printf "$2(date): $( date_microtime )\n"
}


vc_checkout_git()
{
  git checkout "$@"
}
vc_checkout_hg() { false; }
vc_checkout_svn() { false; }
vc_checkout_bzr() { false; }

# checkout
vc_checkout()
{
  test -n "${scm-}" || vc_getscm
  vc_checkout_${scm} "$@"
}


vc_fetch_git()
{
  git fetch "$@"
}
vc_fetch_hg() { false; }
vc_fetch_svn() { false; }
vc_fetch_bzr() { false; }

# fetch
vc_fetch()
{
  test -n "${scm-}" || vc_getscm
  vc_fetch_${scm} "$@"
}


git_ref_exists() # [Branch|Tag]
{
  git show-ref --verify -q "$1" || return $?
}
vc_ref_exists() # [Branch|Tag]
{
  ${scm}_ref_exists
}


git_remote_branch() # ( Branch-Name Remote | Remote/Branch )
{
  test -n "$1" || error "remote branch name missing" 1
  test -n "$2" || {
    fnmatch "*/*" "$1" && {
      set -- "$1" "$(echo "$1" | cut -d '/' -f 2-)"
      set -- "$(echo "$1" | cut -d '/' -f 1)" "$2"
    }
  }
  test -n "$2" || error "remote name missing '$*'" 1
  git_ref_exists "refs/remotes/$2/$1" || return $?
}

git_local_branch() # Branch-Name
{
  test -n "$1" || error "local branch name missing" 1
  git_ref_exists "refs/heads/$1" || return $?
}

git_branch_exists()
{
  test -n "$2" || set -- "$1" origin
  git_local_branch "$1" || git_remote_branch "$@"
}

git_tag_exists()
{
  test -n "$1" || error "tag name missing" 1
  test -z "$2" || error "TODO: check for tag at remote?" 1
  git_ref_exists "refs/tags/$1" || return $?
}

vc_exists() # Branch [Remote]
{
  ${scm}_branch_exists "$@" || ${scm}_tag_exists "$@"
}

vc_exists_local() # Branch
{
  ${scm}_local_branch "$@" || ${scm}_tag_exists "$@"
}


vc_revision_git()
{
  git show-ref --head HEAD -s
}
vc_revision_hg() { false; }
vc_revision_svn()
{
  svn info --show-item revision
}
vc_revision_bzr()
{
  bzr revno
}

# Return version for working tree, aka revision Id, commit Id, etc.
vc_revision()
{
  test -n "${scm-}" || vc_getscm
  vc_revision_${scm}
}


# List linenumber, SHA1 commit-ID, and linecount.
vc_blame_git() # List line-nr, sha1 and line-cnt ~ File [Start- End-Line]
{
  {
    test -n "$2" && {
      git blame --porcelain --incremental --root -L $2,$3 -- "$1"
    } || {
      git blame --porcelain --incremental --root -- "$1"
    }
  } |
      grep '^[0-9a-f]*\ [0-9\ ]*$' |
      while read -r sha1ref srcline finalline numlines
  do
      echo $finalline $sha1ref $numlines $(( $finalline + $numlines ))
  done |
      sort -n
}
vc_blame_hg() { false; }
vc_blame_svn() { false; }
vc_blame_bzr() { false; }

vc_blame()
{
  test -n "${scm-}" || vc_getscm
  vc_blame_${scm} "$@"
}


# XXX: really like blame but stashes blame-idx in local file, for
# cleanup into status dir or some htd/pd thing
vc_commit_for_line() # File Line-Nr
{
  test $# -gt 0 || return
  vc_getscm || return
  vc_blame "$1" >"$1".blameidx
  local srcf="$1" ; shift
  while read firstln commit lncnt lastln
  do
    test $1 -ge $firstln || continue
    test $1 -lt $lastln && {
        echo "$commit"
        shift
        test $# -gt 0 || break
    }
    continue
  done <"$srcf".blameidx
  test $# -eq -0
}

vc_commit_date() # Commit
{
  git show -s --format=%cI "$1"
}

vc_author_date() # Commit
{
  git show -s --format=%aI "$1"
}

# List 'commit-ref, ISO date and commit-oneline' for path(s), starting with most
# recent.
vc_commits () # Log-Args...
{
  git log --pretty='format:%C(auto)%h %ad %s' --date=short --follow "$@"
}

vc_list_paths_git () # [DIR]
{
  find ${1:-"."} -type d -iname .git -print -prune
}

# Boilerplate
#vc_status_git()
#{
#    .. get status
#}
#vc_status_hg() { false; }
#vc_status_svn() { false; }
#vc_status_bzr() { false; }
#
## status
#vc_status()
#{
#  test -n "${scm-}" || vc_getscm
#  vc_status_${scm}
#}

#
