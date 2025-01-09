#!/usr/bin/env bash
#!/bin/sh
# Created: 2015-12-14
set -e

version=0.0.4-dev # script-mpe


pd_man_1__version="Version info"
pd__version()
{
  echo "$(cat $scriptpath/.app-id)/$version"
}
#pd_als___V=version
pd_als____version=version


pd_man_1__edit="Edit script-files, append ARGS to EDITOR arguments. "
pd_spc__edit="edit [ARGS]"
pd__edit()
{
  $EDITOR $0 \
    $scriptpath/projectdir*sh \
    $scriptpath/pd_meta.py \
    $scriptpath/meta.lib.sh \
    "$@"
}
pd_als___e=edit


pd_man_1__new='FIXME: setup new project at prefix'
pd_flags__new=y
pd__new()
{
  test -e "$pdoc" || error pdoc 2
  note "Generating new project checkout at '$pd_prefix'.."
  package_file "$pd_realdir/$pd_prefix" &&
    error "Package exists: $(basename "$metaf"), use init or update" 1

  pd_new_package "$pd"
  (
    cd "$pd"
    git init
    npm init -y
  )
}


pd_flags__meta=y #B
pd_man_1__meta='Defer a command to the python script for YAML parsing

With no argument, create a new background process. If first command is a
sub-command name, try to pass invocation to background process if running.

The background process stays attached to the tty, so use a separate shell or job
control for the invocation (ie. append "&" to the line)
'
pd__meta()
{
  test -n "${1-}" || set -- --background
  test -f "$pdoc" || error "No file for pdoc" 2

  # Unless option is given, pass sub-cmd to backend (if pd-sock) exists
  fnmatch "$1" "-*" || {
    test -x "$(which socat)" -a -e "$pd_sock" && {

      main_sock=$pd_sock main_bg_writeread "$@"
      return $?
    }
  }

  # With no option, use existing pd-sock as requested address
  test -n "$pd_sock" && {
    test ! -e "$pd_sock" || $LOG "error" "" "PD socket exists" "$pd_sock" 1
    set -- --address $pd_sock "$@"
  }

  $scriptpath/projectdir-meta -f $pdoc "$@" || return $?
}

pd_man_1__meta_sq="double silent/quiet; TODO should be able to replace with -sq"
pd__meta_sq()
{
  pd__meta "$@" >/dev/null || return $?
}


pd_man_1__status="List prefixes and their state(s)"
pd_spc__status="st|stat|status $pd_registered_prefix_target_spec"
pd__status()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  std_info "Pd targets requested: $*"
  std_info "Pd prefixes requested: $(lines_to_words < $prefixes )"

  # Set default option
  test -s "$options" || format_yaml=1

  # XXX: fetching the state requires all branches to have status/result set.
  #pd__meta update-states
  # TODO: also export for monitoring
  while read pd_prefix
  do
    test -f "$checkout" -o -h "$checkout" && {
      echo "pd:status:$pd_prefix" >$failed
      note "Not a checkout path at $checkout"
      continue
    }
    note "pd-prefix=$pd_prefix ($CWD)"
    trueish "$format_yaml" && {

      {
        # Read from tree, note status != 0 as failures.
        pd_fetch_status "$pd_prefix" |
          jsotk.py -I yaml -O pkv - |
          tr '=' ' ' | while read var stat
        do
          test -n "$var" -a "$var" != "None" || continue
          test "$stat" = "None" && continue
          test "$stat" = "0" || {
            echo "$pd_prefix" >> $failed
            warn "$pd_prefix: $(echo $var | cut -c8-)"
          }
        done

      } || echo "pd:status:$pd_prefix" >>$failed

    }
    trueish "$format_stm_yaml" && {
      note "TODO"
    }

  done < $prefixes
  cd $pd_realdir
}
pd_flags__status=yiIaop
pd_defargs__status=pd_registered_prefix_target_args
pd_optsv__status=pd_options_v
pd_als__stat=status
pd_als__st=status


pd_flags__status_old=ybf
# Run over known prefixes and present status indicators
pd__status_old()
{
  pd__list_prefixes "$1" > $PD_TMPDIR/prefixes.list
  pd__meta list-disabled "$1" > $PD_TMPDIR/prefix-disabled.list
  pd__meta list-enabled "$1" > $PD_TMPDIR/prefix-enabled.list

  #local \
  #  registered="$(pd__list_prefixes "$1" || touch $failed)" \
  #  disabled="$(pd__meta list-disabled "$1" || touch $failed)" \
  #  enabled="$(pd__meta list-enabled "$1" || touch $failed)" \
  local \
    prefix_args= prefixes=

  test -n "$1" && prefix_args="$*" || prefix_args='*'
  #test -n "$1" || set -- "$prefix_args"

  # Gobble up arguments as prefixes
  test -z "$1" && {
    prefixes="$(cat $PD_TMPDIR/prefixes.list)"
  } || {
    while test $# -gt 0
    do
      grep -qF "$1" $PD_TMPDIR/prefixes.list && {
        prefixes="$prefixes $(echo $1)"
      } || {
        warn "Not a known prefix $1"
      }
      shift
      #registered="$registered $(pd__list_prefixes "$1" || touch $failed)"
      #disabled="$disabled $(pd__meta list-disabled "$1" || touch $failed)"
      #enabled="$enabled $(pd__meta list-enabled "$1" || touch $failed)"
    done
  }

  #note "Getting status for checkouts in '$prefix_args'"
  #std_info "Prefixes: $(echo "$prefixes" | unique_words)"
  #debug "Registered: $(echo "$registered" | unique_words)"
  #local union="$(echo "$prefixes $registered" | words_to_unique_lines )"
  for checkout in $prefixes
    # XXX union
  do

    test -f "$checkout" -o -h "$checkout" && {
      note "Not a checkout path at $checkout"
      continue
    }
    test -d "$checkout" || {
      grep -qF $checkout $PD_TMPDIR/prefixes.list || {
        touch $failed
        warn "Non-existant prefix? '$checkout'"
      }
      continue
    }
    test -e "$checkout/.git" || {
      note "Projectdir is not a checkout at $checkout"
      continue
    }
    #statusdir.sh assert-state 'project/'$checkout'/tags'='[]'

    # FIXME: merge with pd-check? Need fast access to lists..
    #pd_check $checkout || echo pd-check:$checkout >>$failed

    pd_meta_clean_mode=
    pd__clean $checkout || {
      echo pd-clean:$checkout >>$failed
      #statusdir.sh assert-state \
      #  'project/'$checkout'/clean'=false
      #statusdir.sh assert-state \
      #  'project/'$checkout'/tags[]'=to-clean
    }

    grep -qF $checkout $PD_TMPDIR/prefix-enabled.list && {
      test -e "$checkout" || {
        note "Checkout missing: $checkout"
        statusdir.sh assert-json \
          'project/'$checkout'/tags[]=to-enable'
      }
    } || {
      grep -qF $checkout $PD_TMPDIR/prefix-disabled.list && {
        test ! -e "$checkout" || {
          note "Checkout to be disabled: $checkout"
          statusdir.sh assert-json \
            'project/'$checkout'/tags[]=to-clean'
        }
      } || true
    }

  done
}


pd_flags__clean=y
pd__clean()
{
  local R=0

  test -n "$1" || error "Prefix expected" 1
  test -z "$2" || pd_meta_clean_mode="$2"
  test -n "$pd_meta_clean_mode" ||
      pd_meta_clean_mode="$( pd__meta clean-mode "$1" )"

  local scm= scmdir=
  vc_getscm "$1"

  std_info "Checkout at $1 ($scm), Clean Mode: $pd_meta_clean_mode"

  pd_auto_clean "$1" || {
    error "Auto-clean failure for checkout '$1'"
    return 1
  }

  pd_clean "$1" || R=$?;

  case "$R" in
    0|"" )
        std_info "OK $(vc_flags_${scm} "$1")"
      ;;
    1 )
        warn "Dirty: $(vc_flags_${scm} "$1")"
        return 1
      ;;
    2 )
        cruft_lines="$(echo $(echo "$cruft" | wc -l))"
        test $verbosity -gt 6 \
          && {
            warn "Crufty: $(vc_flags_${scm} "$1"):"
            printf "$cruft\n"
          } || {
            warn "Crufty: $(vc_flags_${scm} "$1"), $cruft_lines path(s)"
          }
        return 2
      ;;
    * )
        error "pd_clean error"
        return -1
      ;;
  esac
}


pd_man_1__disable_clean="drop clean checkouts and disable repository"
pd__disable_clean()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  pwd=$PWD
  pd__meta list-prefixes "$1" | while read prefix
  do
    test ! -d $prefix || {
      cd $pwd/$prefix
      local scm= scmdir=
      vc_getscm || continue
      git diff --quiet && {
        test -z "$(vc_untracked)" && {
          warn "TODO remove $prefix if synced"
          # XXX need to fetch remotes, compare local branches
          #pd__meta list-push-remotes $prefix | while read remote
          #do
          #  git push $remote --all
          #done
        }
      }
      cd $pwd
    }
  done
}


pd_man_1__regenerate="Regenerate local package metadata files and scripts"
pd_flags__regenerate=dfP
#pd_flags__regenerate=yfip
pd__regenerate()
{
  test -n "$pd_prefix" || error pd_prefix 1
  test -n "$1" || set -- .
  set -- "$(normalize_relative "$pd_prefix/$1")"
  note "Regenerating meta files in '$1' ($PWD)"
  exec 6>$failed
  pd_regenerate "$1"
  exec 6<&-
  test -s "$failed" || rm $failed
}


pd_man_1__update="Given existing checkout, update local scripts and then projdoc"
pd_flags__update=yfP
pd__update()
{
  test -n "$1" || set -- .
  set -- "$(normalize_relative "$pd_prefix/$1")"
  local cwd=$PWD

  note "Regenerating in $1"
  exec 3>$failed
  ( cd $1 && pd_regenerate "$1" )
  exec 3<&-
  test -s "$failed" || rm $failed

  cd $cwd

  # Update projectdocument with repo remotes etc
  pd__meta_sq get-repo $1 && {

    note "Updating prefix $1"
    pd__update_repo $1
  } || {

    note "Adding prefix $1"
    pd__add_new $1 $(cd "$cwd/$1"; vc.sh remotes sh)
  }
}

pd_man_1__update_all="Add/remove repos, update remotes at first level. git only."
pd_flags__update_all=yfb
pd__update_all()
{
  test -n "$1" \
    && set -- "$pd_prefix/$1" \
    || set -- "$pd_prefix/*"
  set -- "$(normalize_relative "$1")"

  backup_if_comments "$pdoc"
  while test ${#@} -gt 0
  do

    test -d "$1" -a -e "$1/.git" || {
      std_info "Skipped non-checkout path $1"
      shift
      continue
    }

    # Run over implicit enabled prefixes
    pd__meta list-enabled "$1" | while read prefix
    do
      # If exists save for next step, else disable if explicitly disabled
      test -d $prefix || {
        pd__meta -s enabled $prefix \
          && continue \
          || {

          pd__meta disable $prefix \
            && note "Disabled $prefix" \
            || touch $failed
        }
      }
    done

    # Run over all existing single-level prefixes, XXX: should want some depth..
    for git in $1/.git
    do
      prefix=$(dirname $git)
      match_grep_pattern_test "$prefix"

      # Assemble metadata properties
      pd__update $prefix

    done

    shift
  done
}

pd_flags__find=y
pd_spc_find='[<path>|<localname> [<project>]]'
pd__find()
{
  test -z "$3" || error "Surplus arguments: $3" 1
  test -n "$2" && {
    fnmatch "*/*" "$1" && {
      pd__meta list-prefixes "$1"
    } || {
      pd__meta list-local -g "$2" "*$1*"
    }
  } || {
    pd__meta list-prefixes -g "*$1*"
  }
}

pd_flags__list_prefixes=y
pd_man_1__list_prefixes="List enabled prefixes"
pd_spc__list_prefixes="list-prefixes [prefix-or-glob]"
pd__list_prefixes()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  pd__meta list-prefixes "$1" || return
}

pd__list()
{
  pd__meta list-prefixes | while read prefix
  do
    echo $prefix
    # TODO: echo table; id name main envs..
  done
}

pd__list_all()
{
  test -d "$UCONF/project/" || error list-all-UCONF 1
  local pdoc=
  {
    for pdoc in $UCONF/project/*/*.y*ml
    do
      pd__meta list-prefixes
    done
  } | sort -u
}

pd_flags__compile_ignores=y
pd__compile_ignores()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  pd__meta list-prefixes "$1" | while read prefix
  do
    match_grep_pattern_test "$prefix"
    grep -q "$p_" .gitignore || {
      echo $prefix >> .gitignore
    }
    echo $prefix
  done
}

# prepare Pd var, failedfn
pd_flags__sync=yf
pd_man_1__sync='Update remotes and check refs
'
pd__sync()
{
  test -n "$1" || error "prefix argument expected" 1
  remotes=/tmp/pd--sync-$(get_uuid)
  prefix=$1
  shift 1
  test -n "$1" || set -- $(vc.sh list-local-branches $prefix)

  pwd=$(pwd -P)
  cd $pwd/$prefix
  test -d .git || error "Not a standalone .git: $prefix" 1

  test ! -d .git/annex || {
    git annex version >/dev/null || {
      error "GIT Annex dir but no git-annex" 1
    }
    git annex sync || r=$?
    test -n "$r" || {
      echo "annex-sync:$prefix" >>$failed
      return $r
    }
  }

  cd $pwd

  # XXX: look into git config for this: git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads
  {
    pd_list_upstream || {
      warn "No sync setting, skipping $prefix"
      return 1
    }
  } | while read remote branch
  do

    fnmatch "*annex*" $branch && continue || true


    cd $pwd/$prefix

    ( test -e .git/FETCH_HEAD && newer_than .git/FETCH_HEAD $PD_SYNC_AGE ) || {
      git fetch --quiet $remote || {
        error "fetching $remote"
        echo "fetch:$remote" >>$failed
        continue
      }
    }


    local remoteref=$remote/$branch

    echo $remoteref >>$remotes

    git show-ref --quiet $remoteref || {
      test -n "$choice_sync_push" && {
        git push $remote +$branch
      } || {
        error "Missing remote branch in $prefix: $remoteref"
        echo "missing:$prefix:$remoteref" >>$failed
        continue
      }
    }

    local ahead=0 behind=0

    git diff --quiet ${remoteref}..${branch} \
      || ahead=$(git rev-list ${remoteref}..${branch} --count) \

    git diff --quiet ${branch}..${remoteref} \
      || behind=$(git rev-list ${branch}..${remoteref} --count)

    test $ahead -eq 0 -a $behind -eq 0 && {
      std_info "In sync: $prefix $remoteref"
      continue
    }

    test $ahead -eq 0 || {
      note "$prefix ahead of $remote#$branch by $ahead commits"
      trueish "$dry_run" \
        && echo "ahead:$prefix:$remoteref:$ahead" >>$failed \
        || {

          git push $remote $branch || {

            echo "sync-fail:$prefix:$remoteref:$?" >>$failed
            continue
          }
        }
    }

    test $behind -eq 0 || {
      # XXX: ignore upstream commits?
      test -n "$choice_sync_dismiss" \
        || {
          note "$prefix behind of $remote#$branch by $behind commits"
          test -n "$dry_run" || touch $failed;
        }
    }

  done

  test -s "$remotes" || {
    error "No remotes for $pwd/$prefix"; return 1;
  }
  remote_cnt=$(wc -l $remotes | awk '{print  $1}')
  test $remote_cnt -gt 0 || echo 'remotes:0' >>$failed

  test -s "$failed" \
    && { error "Not in sync: $prefix" ; return 1; }\
    || std_info "In sync with at least one remote: $prefix";
}

pd_flags__enable_all=ybf
pd__enable_all()
{
  test $# -gt 0 || return
  pwd=$PWD
  while test $# -gt 0
  do
    pd__enable "$1" || touch $failed
    cd $pwd
    shift
  done
}

# Assert checkout exists, or reinitialize from Pd document.
pd_flags__enable=y
pd__enable()
{
  test $# -gt 0 || {
    local prefixes="$(pd__meta list-enabled)"
    test -n "$prefixes" || {
        note "Nothing to check out"
        return
    }
    std_info "Checking out missing prefixes"
    pd__meta list-enabled | while read prefix
    do
      test -d "$prefix" || {
        note "Enabling $prefix..."
        pd__enable "$prefix" \
          && note "Enabed $prefix" \
          || error "pd-enable returned '$?'" 1
      }
    done
  } || {
    test -z "$2" || error "Surplus arguments: $2" 1
    set -- "$(strip_trail=1 normalize_relative "$1")"
    pd__meta_sq get-repo $1 || error "No repo for $1" 1
    pd__meta -sq enabled $1 || pd__meta -q enable $1 || return
    test -d $1 || {
      upstream="$(pd__meta list-upstream "$1" | sed 's/^\([^\ ]*\).*$/\1/g' | head -n 1)"
      test -n "$upstream" || upstream=origin
      uri="$(pd__meta get-uri "$1" $upstream)"
      test -n "$uri" || error "No uri for $1 $upstream" 1
      branch=$(jsotk.py path "$pdoc" repositories/"$1"/default -Opy 2>/dev/null || echo master)
      git clone $uri --origin $upstream --branch $branch $1 \
        || error "Cloning $uri ($upstream/$branch)" 1
    }
    pd__init $1 || return
  }
  note "Initialized '$1'"
}

pd_flags__init_all=ybf
pd__init_all()
{
  pwd=$PWD
  while test $# -gt 0
  do
    pd__init "$1" || touch $failed
    cd $pwd
    shift
  done
}

# Given existing prefix, update projectdocument and regen
#, update local .git with remotes, regen hooks.
pd_flags__init=yfP
pd__init()
{
  test -n "$1" || error "prefix argument expected" 1
  test -d "$1" || error "No checkout for $1" 1
  test -z "$2" || error "Surplus arguments: $2" 1
  pd__meta_sq get-repo $1 || error "No repo for $1" 1

  pd__set_remotes $1

  (
    cd $1
    git submodule update --init --recursive

    # Regenerate .git/info/exclude
    vc.sh regenerate || echo "init:vc-regenerate:$1" >>$failed

    test ! -e .versioned-files.list || {
      echo "git-versioning check" > .git/hooks/pre-commit
      chmod +x .git/hooks/pre-commit
    }
  )
}


pd_man_1__init_new="Run init_new targets (for single prefix)"
pd_flags__init_new=yiIap
pd_defargs__init_new=pd_prefix_target_args
pd__init_new()
{
  init -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  init -n "$1" || set -- $(pd__ls_targets init 2>/dev/null)
  std_info "Tests to run ($pd_prefixes): $*"
  pd_run_suite init "$@" || return $?
}


# Set the remotes from metadata
pd_flags__set_remotes=y
pd__set_remotes()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1

  note "Syncing local remotes with $pdoc repository"
  cwd=$PWD
  pd__meta list-remotes "$1" | while read remote
  do
    cd "$cwd"
    url=$(pd__meta get-uri "$1" $remote)
    cd "$cwd/$1"
    git config remote.$remote.url >/dev/null && {
      test "$(git config remote.$remote.url)" = "$url" || {
        no_act \
          && echo "git remote add $remote $url ( ** DRY RUN ** )" \
          || {
            git remote set-url $remote $url
            note "Updated remote $remote"
          }
      }
    } || {
      no_act \
        && echo "git remote add $remote $url ( ** DRY RUN ** )" \
        || {
          git remote add $remote $url
          note "Added remote $remote"
        }
    }
  done

  cd $cwd
}

no_act()
{
  test -n "$dry_run"
}

pd_flags__disable_all=ybf
pd__disable_all()
{
  pwd=$PWD
  while test $# -gt 0
  do
    pd__disable "$1" || touch $failed
    cd $pwd
    shift
  done
}

# Disable prefix. Remove checkout if clean.
pd_flags__disable=yf
pd__disable()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1


  pd__meta_sq disabled "$1" && {
    std_info "Already disabled: prefix '$1' in '$pdoc'"
  } || {
    pd__meta disable $1 && note "Disabled prefix '$1' in '$pdoc'"
  }

  test ! -d "$1" && {
    std_info "No dir '$1', nothing to do"
  } || {
    note "Found dir at '$1', running pd-clean..."
    pd__clean $1 || return $?

    choice_sync_dismiss=1 \
    $scriptpath/$scriptname.sh sync $1 || return $?

    trueish "$dry_run" \
      && {
        echo "dry-run:rm:$1" >>$failed
        note "** DRY_RUN **: checkout to be removed $1"
      } || {
        rm -rf $1 \
          && note "Removed checkout $1"
      }
  }
}


pd_man_1__add='Add or update SCMs of a repo.
Arguments checkout dir prefix, url and prefix, or remote name, url and prefix.
'
pd_flags__add=y
pd_spc__add="add ( PREFIX | REPO PREFIX | NAME REPO PREFIX )"
pd__add()
{
  # Shift args to right, padding with empty arguments
  while test ${#} -ne 3
  do
    set -- "" "$@"
  done

  # Check prefix or url arg
  set -- "$1" "$2" "$(normalize_relative "$pd_prefix/$3")"
  test -n "$2" -o -d $3/.git || error "No repo, and not a checkout: $3" 1

  # Set default args for single remote
  test -n "$1" || {
    test -z "$2" || set -- "origin" "$2" "$3"
  }

  # Check URL arg
  test -n "$2" && {
    # add/update a repo remote if arg given
    props="remote_$1=$2"
  } || {
    # Or fill out all remotes
    props="$(verbosity=0 ; cd $3 && vc.sh remotes sh)"
  }

  note "Prefix: $3"
  note "Repo: $2"
  note "Remote: $1"
  note "Properties: $props"

  pd__meta_sq get-repo "$3" 1>/dev/null || {
    pd__meta update-repo "$3" $props
  } || {
    pd__add_new "$3" $props
  }
  # TODO: after pd-add, perhaps enable+init+regenerate
  #trueish "$choice_interactive" && {
  #  pd__init
  #}
}

# Add a new item to the projectdoc, resolving some default values
# Fail if prefix already in use
pd_flags__add_new=f
pd__add_new()
{
  local prefix=$1; shift; local props="$@"

  # Concat props as k/v, and sort into unique mapping later; last value wins
  # FIXME: where ar the defaults: host and user defined, and project defined.
  props="clean=tracked sync=true $props"

  std_info "New repo $prefix, props='$(echo $props)'"

  pd__meta put-repo $prefix $props \
    && note "Added metadata for $prefix" \
    || {
      error "Unexpected error adding repo $?" $?
      echo "add-new:$prefix" >>$failed
    }

  # XXX: enabled?
}

# Given prefix and optional props, update metadata. Props is prepended
# and so may be overruled by host/env. To update metadata directly,
# use pd__meta{,_sq} update-repo.
pd_flags__update_repo=f
pd__update_repo()
{
  local cwd=$PWD; prefix=$1; shift; local props="$@"

  #test -d "$prefix/.git" || {
  #  trueish "$choice_enable" && {
  #    note "Enabling pd repo.."
  #    pd__enable $3 || return $?
  #  }
  #}

  test -d "$prefix/.git" && props="$props enabled=true"

  test -d $prefix/.git/annex && {
    props="$props annex=true"
  }

  # scan checkout remotes

  # FIXME: move here props="$props $(verbosity=0;cd $1;echo "$(vc.sh remotes sh)")"

  local remotes=
  for remote in $(cd $prefix; git remote)
  do
    remotes="$remotes remote_$remote=$(cd $prefix; git config remote.$remote.url)"
  done

  test -n "$remotes" && props="$props $remotes" || {
    error "No remotes for $prefix"
    echo "update:no-remotes:$prefix" >>$failed
    return
  }

  trueish "$dry_run" && warn "** DRY-RUN **" 1

  # Update existing, add newly found repos to metadata

  pd__meta update-repo $prefix $props \
    && note "Updated metadata for $prefix" \
    || {
      local r=$?;
      test $r -eq 42 && {
        std_info "Metadata already up-to-date for $prefix"
      } || {
        warn "Error updating $prefix with '$(echo $props)'"
        echo "update-repo:$prefix:$r" >>$failed
      }
      unset r
    }
}


# TODO: Copy prefix from other local or remote pdoc
pd__copy() # HOST PREFIX [ VOLUME ]
{
  test -n "$1" || error "expected hostname" 1
  test -n "$2" || error "expected prefix" 1
  test -z "$3" || error "unexpected arg '$3'" 1
  test -n "$hostname" || error "expected env hostname" 1

  for host in $hostname $1
  do
    test -d $PD_CONFDIR/$host || error "No dir for host $host" 1
    test -e $PD_CONFDIR/$host/$PD_DEFDIR.yaml || \
        error "No projectdoc for host $host" 1
  done
  test "$hostname" != "$1" || error "You ARE at host '$1'" 1


  $scriptpath/$scriptname.sh meta -sq get-repo "$2" \
    && error "Prefix '$2' already exists at $hostname" 1 || true


  pdoc=~/.conf/project/$1/projects.yaml \
    $scriptpath/$scriptname.sh meta dump $2 \
    | tail -n +2 - \
    >> ~/.conf/project/$hostname/projects.yaml \
    && note "Copied $2 from $1 to $hostname projects YAML"
}


# Run (project) helper commands and track results
pd_flags__run=yiIapq
pd_defargs__run=pd_prefix_target_args
pd_spc__run='run [ PREFIX | [:]TARGET ]...'
pd__run()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  #record_env_keys pd-run pd-subcmd pd-env
  note "Pd targets requested: $*"
  note "Pd prefixes requested: $(lines_to_words < $prefixes )"

  while read pd_prefix
  do
    key_pref=repositories/$(normalize_relative "$pd_prefix")
    cd $pd_realdir/$pd_prefix

    # Iterate targets
    set -- $(cat $arguments | lines_to_words )
    test -n "$1" || {
      std_info "Setting targets to states of 'init' for '$pd_root/$pd_prefix'"
      set -- $(pd__ls_targets init 2>/dev/null)
    }
    while test $# -gt 0
    do
      fnmatch ":*" "$1" && target=$(echo "$1" | cut -c2- ) || target=$1

      #record_env_keys pd-target pd-run pd-subcmd pd-env
      #pd_debug start $target pd-target pd_prefix
      (
        export $(pd__env)
        subcmd="$subcmd $pd_prefix#$target" \
          pd_run $1 && {
            echo "$pd_prefix#$target" >&3
          } || {
            echo "$pd_prefix#$target" >&5
          }
      )
      #pd_debug end $target pd-target pd_prefix
      shift
    done
  done < $prefixes
  cd $pd_realdir
}


pd_man_1__run_suite="Run test targets (for single prefix)"
pd_flags__run_suite=yiIp
pd__run_suite()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  test -n "$1" || error "Suite name expected" 1
  local suite_name=$1
  shift
  # TODO: handle prefixes
  test -z "$2" || error surplus-args 1
  pd_run_suite $suite_name $(pd__ls_targets $1 2>/dev/null)
}


pd_man_1__test="Run test targets (for single prefix)"
pd_flags__test=yiIap
pd_defargs__test=pd_prefix_target_args
pd__test()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  test -n "$1" || set -- $(pd__ls_targets test 2>/dev/null)
  std_info "Tests to run ($pd_prefixes): $*"
  pd_run_suite test "$@"
}


pd_flags__check_all=ybf
pd_man_1__check_all='Check if setup, with remote refs '
pd__check_all()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  note "Checking prefixes"
  pd__meta list-prefixes "$1" | while read prefix
  do
    pd_check $prefix || continue
    test -d "$prefix" || continue
    $scriptpath/$scriptname.sh sync $prefix || touch $failed
  done
}


pd_man_1__check='Run targets for "check" suite of local project'
pd_flags__check=yiIap
pd_defargs__check=pd_registered_prefix_target_args
pd__check()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  test -n "$1" || set -- $(pd__ls_targets check 2>/dev/null)
  std_info "Checks to run ($pd_prefixes): $*"
  pd_run_suite check "$@"
}


pd_flags__build=yiIap
pd_defargs__build=pd_registered_prefix_target_args
pd__build()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  test -n "$1" || set -- $(pd__ls_targets build 2>/dev/null)
  std_info "Checks to run ($pd_prefixes): $*"
  pd_run_suite build "$@" || return $?
}


pd_flags__tasks=yiIap
pd_defargs__tasks=pd_registered_prefix_target_args
pd__tasks()
{
  test -n "$pd_prefixes" -o \( -n "$pd_prefix" -a -n "$pd_root" \) \
    || error "Projectdoc context expected" 1
  test -n "$1" || set -- $(pd__ls_targets tasks 2>/dev/null)
  std_info "Checks to run ($pd_prefixes): $*"
  pd_run_suite tasks "$@" || return $?

  #local r=0 suite=tasks
  ## TODO: pd tasks
  #echo "sh:pwd" >$arguments
  #subcmd=$suite:run pd__run || r=$?
  #test -s "$errored" -o -s "$failed" && r=1
  #pd_update_records status/$suite=$r $pd_prefixes
  #return $r
}


pd_flags__show=yiap
pd_defargs__show=pd_prefix_args
pd_spc__show="show [ PREFIX ]..."
# Print Pdoc record and main section of package meta file.
pd__show()
{
  while test $# -gt 0
  do

    test "$dry_run" && {

      skipped "pd:show:$1"

    } || {

      note "Showing main package data for '$1'"

      pd__meta get-repo $1 | \
        jsotk.py -I json -O yaml --pretty \
        --output-prefix repositories/$1 merge - - || {
        error "decoding '$1' JSON" 1
      }

      local metaf=
      package_update "$1" && {
        test -n "$metaf" || error "metaf" 1
        test -e "$metaf" || error "metaf: $metaf" 1

        jsotk.py --output-prefix package -I yaml -O yaml --pretty objectpath \
          $metaf '$.*[@.main is not None]' || {

            error "decoding '$metaf' " 1
        }
      } || { r=$?
        note "Pd: No local package data for '$1'"
      }
    }

    shift
  done
}


pd__ls_sets()
{
  for name in $pd_sets
  do
    echo "$name"
  done
}

pd_named_set_args()
{
  local named_sets="$(pd__ls_sets | lines_to_words )"
  test -n "$1" || set -- $named_sets
  while test $# -gt 0
  do
    fnmatch "* $1 *" " $named_sets " && {
      echo $1
    } || {
      error "No such named set '$1'"
    }
    shift
  done | words_to_unique_lines >>$arguments
}

# List std named set(s)
pd__ls_comp()
{
  echo "Init comp: $pd_init__sets"
  echo "Check comp: $pd_check__sets"
  echo "Test comp: $pd_test__sets"
}


# List targets for given named set(s)
pd__ls_reg()
{
  while test $# -gt 0; do
    note "Targets for set '$1'"
    eval echo $(try_value sets $1) | words_to_lines
    shift
  done
}
pd_defargs__ls_reg=pd_named_set_args
pd_flags__ls_reg=ia


# Gather targets that apply for given named set(s) (in prefix)
pd_spc__ls_targets="ls-targets [ NAME ]..."
pd__ls_targets()
{
  test -n "$pd_prefixes" || error "pd_prefixes" 1
  local pd_prefix=
  for pd_prefix in $pd_prefixes
  do
    local name=
    while test $# -gt 0
    do
      note "Named target list '$1' ($pd_prefix)"; name=$1; shift
      read_if_exists $pd_prefix/.pd-$name && continue
      (
        cd $pd_prefix
        pd_package_meta "$name" && continue
        std_info "Autodetect for '$name'"
        pd_autodetect $name
      )
    done
  done | words_to_lines
}
pd_defargs__ls_targets=pd_named_set_args
pd_flags__ls_targets=yiapd


pd_spc__ls_auto_targets="ls-auto-targets [ NAME ]..."
# Gather targets that would apply by default for given named set(s)
pd__ls_auto_targets()
{
  while test $# -gt 0
  do
    note "Returning auto targets '$1' ($pd_prefix)"
    pd_autodetect $1
    shift
  done | words_to_lines
}
pd_defargs__ls_auto_targets=pd_named_set_args
pd_flags__ls_auto_targets=diap


# List all paths; -dfl or with --tasks filters
pd_flags__list_paths=iO
pd__list_paths()
{
  opt_args "$@"
  set -- "$(cat $arguments)"
  req_cdir_arg "$@"
  shift 1; test -z "$@" || error surplus-arguments 1
  local find_ignores="$(ignores_find $IGNORE_GLOBFILE) $(pd__list_paths_opts)"
  # FIXME: some nice way to get these added in certain contexts
  find_ignores="-path \"*/.git\" -prune $find_ignores "
  find_ignores="-path \"*/.bzr\" -prune -o $find_ignores "
  find_ignores="-path \"*/.svn\" -prune -o $find_ignores "

  debug "Find ignores: $find_ignores"
  eval find $path $find_ignores -o -path . -o -print
}
pd__list_paths_opts()
{
  while read option; do case "$option" in
      -d ) echo "-o -not -type d " ;;
      -f ) echo "-o -not -type f " ;;
      -l ) echo "-o -not -type l " ;;
      --src )
          echo " -o -not -type f "
        ;;
      --tasks )
          for tag in no-tasks shadow-tasks
          do
            meta_attribute tagged $tag | while read glob
            do
              glob_to_find_prune "$glob"
            done
          done
          echo " -o -not -type f "
        ;;
      * ) echo "$option " ;;
    esac
  done < $options
}


pd_spc__loc='loc SRC-FILE...'
# Count non-empty, non-comment lines from files
pd__loc()
{
  test $# -gt 0 || return
  while test $# -gt 0
  do
    read_nix_style_file "$1"
    shift
  done | count_lines
}


pd_flags__src_report=iO
pd__src_report()
{
  pd__list_paths . --src | while read path
  do
    test -e "$path" || continue
    echo $path chars=$(count_chars $path) lines=$(count_lines $path)
    # src_loc="$(line_count $path)"
  done
}


pd_man_1__versions=
pd__versions()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1
  test -n "$1" || set -- "$pd_prefix" "$2"
  test -n "$2" || set -- "$1" "origin"
  test -n "$3" || set -- "$1" "$2"
  # XXX: pd-prefix may not be enabled
  #local giturl="$(cd $pd_realdir/$1 && git config remote.$2.url)"
  local giturl=$(jsotk.py path -O py $pd_root/$pdoc "repositories/'$1'/remotes/$2")
  # Use semver to sort tags
  semver $( git ls-remote -t -h $giturl refs/tags/* \
		| cut -f 2 | grep -v '{}' | grep '[0-9]*\.[0-9]*\.[0-9]*' \
    | sort --general-numeric-sort | while read ref; do basename $ref; done )
}
pd_flags__versions=y


pd_man_1__latest="Show latest version tag(s) (see pd-versions)"
pd_spc__latest="latest PREFIX [REMOTE [NUM]]"
pd__latest()
{
  test -n "$3" || set -- "$1" "$2" "1"
  pd__versions "$1" "$2" | tail -n $3
}
pd_flags__latest=y


pd_man_1__stashes="List "
pd__stashes()
{
  test -n "$pd_prefix" -a -n "$pd_root" || error "Projectdoc context expected" 1

  pd list-prefixes | while read pd_prefix
  do
    test -e "$pd_root/$pd_prefix" || continue

    note "pd-prefix=$pd_prefix ($CWD)"
    ( cd $pd_root/$pd_prefix && vc.sh status )

  done
  cd $pd_realdir
}
pd_flags__stashes=yp


pd_man_1__exists='Path exists as dir with mechanism to handle local names.
'
pd__exists()
{
  test -z "$2" || error "One dir at a time" 1
  pd__meta_sq get-repo "$1"
  #{
  #  vc_getscm "$1" || { }
  #}
  #test -e "$(echo "$1"/package.y*ml | cut -f1 -d' ')"
  return $?
  note "Found '$1'"
  # XXX: cleanup
  #echo choice_known=$choice_known
  #echo choice_unknown=$choice_unknown
  #echo "args:'$*'"
}
pd_flags__exists=iao
pd_defargs__exists=opt_args
pd_optsv__exists()
{
  while read opt
  do
    case "$opt" in
      --known ) export choice_known=1 ;;
      --unknown ) export choice_unknown=1 ;;
      * )
          main_options_v "$opt"
        ;;
    esac
    shift
  done
}


pd_man_1__doc='

Commands `update`, `check`, `init` etc. are all used for per-prefix tasks. So
`doc` is reserved for working on the PD_CONFDIR, and tasks related to managing
pdoc/pdir instances.

    doctor
        Verify that we can map pdir names to paths.
    doc-update-all
        XXX: update every host
    doc-update
        XXX: Actualize document and dir?
            update dir from doc and doc from dir based on timestamping..
'

pd__doc_update_all()
{
   for host in $PD_CONFDIR/*/
   do echo
   done
   false
}

pd__doc_update()
{
   false
}

pd__doctor()
{
  for hostdir in $PD_CONFDIR/*/
  do
    host=$(basename $hostdir)
    test "$host" = "$hostname" && {

      for pdoc in $hostdir/*.yaml
      do
        name=$(basename $pdoc .yaml)-local

        # 1. Path exists (dir or symlink)
        test -e $PD_VOLDIR/$name-local || {
            warn "Missing volume for $hostname '$name'"
        }

        # 2. Local path(s) to pdir below volume can be retrieved

        # 3. host/domain can be retrieved and matches
        continue
      done

    } || {

        # Remote volumes
        echo TODO remote domain host $host
    }
  done
}


pd_flags__info=p
pd__info()
{
  local
  echo '-----------------'
  env
  echo '-----------------'
}


# ----


pd__usage()
{
  echo 'Usage: '
  echo "  $scriptname.sh <cmd> [<args>..]"
  echo
}

pd__help()
{
  test $# -le 1 || return 98
  test -z "${1-}" && {
    lib_require ctx-std || return
    choice_global=1 std__help "$@"
    return $?
  } || {
    echo_help $1 || {
      for func_id in "$1" "${base}__$1" "$base-$1"
      do
          htd_function_comment $func_id 2>/dev/null || continue
          htd_function_help $func_id 2>/dev/null && return 1
      done
      error "Got nothing on '$1'" 1
    }
  }
}

# Setup for subcmd; move some of this to box.lib.sh eventually
pd_preload()
{
  scriptpath="$(dirname "$(realpath "$0")")"
  true "${PD_ENV:="$scriptpath/.meta/package/envs/main.sh"}"
  CWD="$scriptpath"
  test ! -e $PD_ENV || { source $PD_ENV || return; }
  test -n "${LOG-}" -a -x "${LOG-}" || export LOG=$CWD/tool/sh/log.sh
  : "${EDITOR:=nano}"
  : "${hostname:=$(hostname -s)}"
  : "${uname:=$(uname -s)}"
  : "${SCRIPT_ETC:=$(os_dirs_exist \
      {$PWD,$(dirname -- "$0"),${US_BIN:-~/bin},${UCONF:-~/.conf}}/etc/htd)}"
}

pd_subcmd_load()
{
  local scriptname_old=$scriptname; export scriptname=pd-subcmd-load

  test -n "${subcmd_func-}" || {
    main_subcmd_func "$subcmd"
    c=1
  }

  main_var flags "$baseids" flags "${flags_default-}" "$subcmd"

  test -x "$(which sponge)" || warn "dep 'sponge' missing, install 'moreutils'"
  # FIXME: test with this enabled
  #test "$(echo $PD_TMPDIR/*)" = "$PD_TMPDIR/*" \
  #  || warn "Stale temp files $(echo $PD_TMPDIR/*)"

  test -n "${UCONF-}" || {
    test -e $HOME/.conf && UCONF=$HOME/.conf || error env-UCONF 1
  }

  # Master dir for per-host pdocs, used by some pdoc management commands
  test -n "${PD_CONFDIR-}" || PD_CONFDIR=$UCONF/project

  # Default local project doc/volume
  test -n "${PD_DEFDIR-}" || PD_DEFDIR=projects

  # Keep symlinks /srv/*-local to map Pdoc name to local path.

  # FIXME: ignore files for projectdir commands
  ignores_lib__load $lst_base || error "pd-load: failed loading ignores.lib" 1
  test -n "${IGNORE_GLOBFILE-}" -a -e "${IGNORE_GLOBFILE-}" && {
    test -n "$PD_IGNORE" -a -e "$PD_IGNORE" ||
        error "expected $base ignore dotfile (PD_IGNORE)" 1
    lst_init_ignores
  }

  ### Finish env setup with per-command flags

  pd_inputs="arguments prefixes options"
  pd_outputs="passed skipped errored failed"

  pd_cid=pd-cid
  test -n "$pd_session_id" || pd_session_id=$(get_uuid)

  SCR_SYS_SH=bash-sh

  # Selective per-subcmd init
  debug "Loading subcmd '$subcmd', flags: $flags"
  for x in $(echo $flags | sed 's/./&\ /g')
  do case "$x" in
    a )
        # Set default args or filter. Value can be literal or function.
        make_local pd_default_args $base defargs "" $subcmd
        pd_default_args "$pd_default_args" "$@"
      ;;

    b )
        # run metadata server in background for subcmd
        main_sock=$pd_sock main_bg=pd__meta box_bg_setup
      ;;

    B )
        # test for bg and allow passthrouh, but don't require running instance
        # and allow for inline executing of command
      ;;

    d ) # XXX: Stub for no Pd context?
        #test -n "$pd_root" \
        test -e "$pdoc" || unset pdoc
        test -n "$pd_prefix" || pd_prefix=.
        pd_realpath= pd_root=. pd_realdir=$(pwd -P)

        #test "$pd_prefix" = "." || {
        #  test ! -e $pd_prefix || cd $pd_prefix
        #}
      ;;

    f )
        # Preset name to subcmd failed file placeholder
        # include realpath of projectdoc (p)
        test -n "$pdoc" && {
          export failed=$(setup_tmpf .failed -$pd_cid-$subcmd-$pd_session_id)
        } || failed=$(setup_tmpf .failed -$subcmd-$pd_session_id )
      ;;

    g )
        # Set default args based on file glob(s), or expand short-hand arguments
        # by looking through the globs for existing paths
        make_var pd_trgtglob $htd trgtglob "" $subcmd
        pd_globstar_search "$pd_trgtglob" "$@"
      ;;

    I ) # setup IO descriptors (requires i before)
        req_vars pdoc pd_cid pd_realpath pd_root $pd_inputs $pd_outputs
        local fd_num=2 io_dev_path=$(io_dev_path)
        for fd_name in $pd_outputs $pd_inputs
        do
          fd_num=$(( $fd_num + 1 ))
          # TODO: only one descriptor set per proc, incl. subshell. So useless?
          test -e "$io_dev_path/$fd_num" || {
            debug "exec $(eval echo $fd_num\\\>$(eval echo \$$fd_name))"
            eval exec $fd_num\>$(eval echo \$$fd_name)
          }
        done
      ;;

    i )
        # TODO: replace below with setup_io_paths, but rename pd_in/outputs frst

        test -n "$pd_root" && {
          # expect Pd Context; setup IO paths (req. y)
          req_vars pdoc pd_cid pd_realpath || error \
            "Projectdoc context expected ($pdoc; $pd_cid; $pd_realpath; $pd_root)" 1

          io_id=-${pd_cid}-${subcmd}-${pd_session_id}
        } || {
          io_id=-$base-$subcmd-${pd_session_id}
        }
        fnmatch "*/*" "$io_id" && error "Illegal chars" 11
        for io_name in $pd_inputs $pd_outputs
        do
          #test -n "$(eval echo \$$io_name)" || {
            tmpname=$(setup_tmpf .$io_name $io_id)
            touch $tmpname
            eval $io_name=$tmpname
            unset tmpname io_name
          #}
        done
        export $pd_inputs $pd_outputs
      ;;

    l )
        pd_subcmd_libs="$(try_value $subcmd libs pd)" ||
            pd_subcmd_libs=$subcmd

        lib_load $pd_subcmd_libs || return
        lib_init $pd_subcmd_libs || return
      ;;

    o )
        local pd_optsv="$(make_local $base optsv "" $subcmd)"
        func_exists "$pd_optsv" || pd_optsv="${!pd_optsv}"
        test -s "$options" && {
          $pd_optsv < $options
        } || true
      ;;

    P )
        package_lib_set_local "$pd_root/$pd_prefix"
        pd__meta_sq get-repo "$pd_prefix" && {
          echo package_update "$pd_prefix"

          package_update "$pd_prefix" || { r=$?
            test  $r -eq 1 || error "package_update" $r
            continue
          }
        } || warn "No repo for '$pd_prefix'"

        test -e $pd_root/$pd_prefix/.package.sh \
          && eval $(cat $pd_root/$pd_prefix/.package.sh)

        test -n "$package_id" && {
          note "Found package '$package_id'"
        } || {
          trueish "$require_prefixes" && error "package_id" 1

          package_id="$(basename $(realpath $pd_prefix))"
          note "Using package ID '$package_id'"
        }
      ;;

    p ) # Load/Update package meta at prefix; should imply y or d
        test -n "$prefixes" -a -s "$prefixes" \
          && pd_prefixes="$(cat $prefixes | words_to_lines )" \
          || pd_prefixes=$pd_prefix

        note "Checking '$pd_prefixes'..."
        local pref=
        for pref in $pd_prefixes; do
          pd__meta_sq get-repo "$pref" && {
              package_update "$pref" || warn "No repo for '$pref'"
            }
        done
        unset pref
      ;;

    q )
        # Evaluate package env
        test -n "$PACK_SH" -a -e "$PACK_SH" && {
            . $PACK_SH || error "No package Sh" 1
        } ||
            error "Pd: No local package" 8
      ;;

    y )
        # look for Pd Yaml and set env: pd_prefix, pd_realpath, pd_root
        # including socket path, to check for running Bg metadata proc

        req_vars pdoc
        test -n "${pd_root-}" || pd_finddoc
      ;;

  esac; debug "'$subcmd' flag '$x' loaded"; done

  local tdy="$(try_value "${subcmd}" today)"
  test -z "$tdy" || {
    today=$(statusdir.sh file $tdy)
    tdate=$(date +%y%m%d0000)
    test -n "$tdate" || error "formatting date" 1
    touch -t $tdate $today
  }
}

# Close subcmd; move some of this to box.lib.sh eventually
pd_subcmd_unload()
{
  local subcmd_result=0

  for x in $(try_value "${subcmd}" load | sed 's/./&\ /g')
  do case "$x" in
    F )
        exec 6<&-
      ;;
    I )
        local fd_num=2
        for fd_name in $pd_outputs $pd_inputs
        do
          fd_num=$(( $fd_num + 1 ))
          #eval echo $fd_num\\\<\\\&-
          eval exec $fd_num\<\&-
        done
        eval unset $pd_inputs $pd_outputs
        unset pd_inputs pd_outputs
      ;;
    i ) # remove named IO buffer files; set status vars
        clean_io_lists $pd_inputs $pd_outputs
        std_io_report $pd_outputs || subcmd_result=$?
      ;;

    y )
        test -z "$pd_sock" || {
          main_sock=$pd_sock main_bg=pd__meta box_bg_teardown
          unset bgd pd_sock
        }
      ;;

  esac; done

  test -n "$PD_TMPDIR" || error "PD_TMPDIR unload" 1
  # FIXME: make so everything cleans up
  #test "$(echo $PD_TMPDIR/*)" = "$PD_TMPDIR/*" \
  #  || warn "Leaving temp files $(echo $PD_TMPDIR/*)"

  unset subcmd_pref \
          def_subcmd func_exists func \
          PD_TMPDIR \
          pd_session_id

  return $subcmd_result
}

pd_init()
{
  pd_preload || exit $?
  . $scriptpath/tool/sh/part/env-0-1-lib-sys.sh
  . ${U_S:?}/tool/sh/init.sh || return
  lib_load str sys os std stdio src match main args str-htd std-ht sys-htd htd
  # XXX: . $scriptpath/tool/sh/box.env.sh
  #box_run_sh_test
  lib_load meta box package src-htd
  # -- pd box init sentinel --
  test -n "${verbosity-}" && note "Verbosity at $verbosity" || verbosity=6
}

pd_lib()
{
  test -z "${lib_loading-}" || return 14
  #local lib_loading=1
  test -n "$scriptpath" || return 11
  lib_load box meta list match date doc table ignores vc-htd projectdir \
      package
  #. $scriptpath/vc.sh
  # -- pd box lib sentinel --
}


### Main

pd_main()
{
  local scriptname=projectdir scriptalias=pd \
    subcmd=$1 \
    base="$(basename "$0" .sh)" scriptpath=

  pd_init || exit $?
  debug "Initialized for '$base'..."

  case "$base" in

    $scriptname | $scriptalias )

        std_info "Starting for '$base': '$*'..."
        unset pd_session_id

        # invoke with function name first argument,
        local pd_session_id= bgd= \
          func_exists= \
          func= \
          pd_sock= \
          c=0 \
          ext_sh_sub= \
          base=pd

        shift $c

        pd_lib "$@" || error pd_lib $?

        main_subcmd_run "$@" || exit $?
        #try_subcmd "$@" && {

        #  #record_env_keys pd-subcmd pd-env
        #  echo XXX: box_lib $0 $scriptalias >&2
        #  shift 1

        #  pd_subcmd_load "$@" || error "pd-subcmd-load" $?

        #  test -z "$arguments" -o ! -s "$arguments" || {
        #    std_info "Setting $(count_lines $arguments) args to '$subcmd' from IO"
        #    set -f; set -- $(cat $arguments | lines_to_words) ; set +f
        #  }

        #  $subcmd_func "$@" || r=$?

        #  pd_subcmd_unload || r=$?

        #  exit $r
        #}

      ;;

    * )
        echo "Pd is not a frontend for $base ($scriptname)"
        exit 1
      ;;

  esac
}


case "$0" in "" ) ;; "-"* ) ;; * )

  test -z "$lib_load" || set -- "load-ext"
  case "$1" in load-ext ) ;; * )

      set -euo pipefail

      pd_main "$@"
    ;;

  esac ;;
esac

# Id: script-mpe/0.0.4-dev projectdir.sh
