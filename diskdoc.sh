#!/bin/sh
# Created: 2016-02-22
diskdoc__source=$_


diskdoc__edit()
{
  $EDITOR \
    $0 \
    ~/bin/diskdoc.inc.sh \
    $(which diskdoc.py) \
    "$@"
}

diskdoc_run__meta=y
# Defer to python script for YAML parsing
diskdoc__meta()
{
  test -n "$1" || set -- --background

  fnmatch "$1" "-*" || {

    # Use socat as client, else performance is almost as bad as re-invoking
    # Python program each call.
    test -x $(which socat) -a -e "$sock" && {
      printf -- "$*\r\n" | socat -d - "UNIX-CONNECT:$sock" \
        2>&1 | tr "\r" " " | while read line
      do
        case "$line" in
          *" OK " )
            return
            ;;
          "? "* )
            return 1
            ;;
          "! "*": "* )
            return $(echo $line | sed 's/.*://g')
            ;;
        esac
        echo $line
      done
      return
    }
  }

  diskdoc.py -f $diskdoc --address $sock "$@" || return $?
}

# silent/quit
diskdoc__meta_sq()
{
  diskdoc__meta "$@" >/dev/null || return $?
}

diskdoc_run__status=ybf
# Run over known prefixes and present status indicators
diskdoc__status()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  note "Getting status for checkouts $prefix"
  diskdoc__list_prefixes "$prefix" | while read prefix
  do
    vc_check $prefix || continue
    test -d "$prefix" || continue
    diskdoc__clean $prefix || touch $failed
  done
}

diskdoc_run__check=ybf
# Check with remote refs
diskdoc__check()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  note "Checking prefixes"
  diskdoc__meta list-prefixes "$1" | while read prefix
  do
    vc_check $prefix || continue
    test -d "$prefix" || continue
    diskdoc sync $prefix || touch $failed
  done
}

diskdoc__clean()
{
  vc_clean "$1"
  case "$?" in
    0|"" )
      info "OK $(__vc_status "$1")"
    ;;
    1 )
      warn "Dirty: $(__vc_status "$1")"
      return 1
    ;;
    2 )
      warn "Crufty: $(__vc_status "$1")"
      test $verbosity -gt 6 &&
        printf "$cruft\n" || noop
      return 2
    ;;
  esac
}

# drop clean checkouts and disable repository
diskdoc__disable_clean()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  pwd=$(pwd)
  diskdoc__meta list-prefixes "$1" | while read prefix
  do
    test ! -d $prefix || {
      cd $pwd/$prefix
      git diff --quiet && {
        test -z "$(vc ufx)" && {
          warn "TODO remove $prefix if synced"
          # XXX need to fetch remotes, compare local branches
          #diskdoc__meta list-push-remotes $prefix | while read remote
          #do
          #  git push $remote --all
          #done
        }
      }
      cd $pwd
    }
  done
}

# Add/remove repos, udiskdocate remotes at first level. git only.
diskdoc_run__udiskdocate=yfb
diskdoc__udiskdocate()
{
  test -n "$1" || set -- "*"

  backup_if_comments "$diskdoc"

  while test ${#@} -gt 0
  do

    test -d "$1" -a -e "$1/.git" || {
      info "Skipped non-checkout path $1"
      shift
      continue
    }

    # Run over implicit enabled prefixes
    diskdoc__meta list-enabled "$1" | while read prefix
    do
      # If exists save for next step, else disable if explicitly disabled
      test -d $prefix || {
        diskdoc__meta -s enabled $prefix \
          && continue \
          || {

          diskdoc__meta udiskdocate-repo $prefix disabled=true \
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

      #{ cd $prefix; git remotes; } | while read remote
      #do
      #  echo
      #done

      # Assemble metadata properties

      props=
      test -d $prefix/.git/annex && {
        props="annex=true"
      }

      props="$props $(verbosity=0;cd $prefix;echo "$(vc remotes sh)")"
      test -n "$props" || {
        error "No remotes for $prefix"
        touch $failed
      }

      # Udiskdocate existing, add newly found repos to metadata

      diskdoc__meta_sq get-repo $prefix && {
        diskdoc__meta udiskdocate-repo $prefix $props \
          && note "Udiskdocated metadata for $prefix" \
          || { r=$?; test $r -eq 42 && info "Metadata up-to-date for $prefix" \
            || { warn "Error udiskdocating $prefix with '$props'"
              touch $failed
            } }
      } || {

        info "Testing add $prefix props='$props'"
        diskdoc__meta put-repo $prefix $props \
          && note "Added metadata for $prefix" \
          || error "Unexpected error adding repo $?" $?
      }
    done

    shift
  done
}

diskdoc_run__find=y
diskdoc_spc_find='[<path>|<localname> [<project>]]'
diskdoc__find()
{
  test -z "$3" || error "Surplus arguments: $3" 1
  test -n "$2" && {
    fnmatch "*/*" "$1" && {
      diskdoc__meta list-prefixes "$1"
    } || {
      diskdoc__meta list-local -g "$2" "*$1*"
    }
  } || {
    diskdoc__meta list-prefixes -g "*$1*"
  }
}

diskdoc_run__list_prefixes=y
diskdoc__list_prefixes()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  diskdoc__meta list-prefixes "$1"
}

diskdoc_run__compile_ignores=y
diskdoc__compile_ignores()
{
  test -z "$2" || error "Surplus arguments: $2" 1
  diskdoc__meta list-prefixes "$1" | while read prefix
  do
    match_grep_pattern_test "$prefix"
    grep -q "$p_" .gitignore || {
      echo $prefix >> .gitignore
    }
    echo $prefix
  done
}

# prepare Pd var, failedfn
diskdoc_run__sync=yf
# Udiskdocate remotes and check refs
diskdoc__sync()
{
  test -n "$1" || error "prefix argument expected" 1
  prefix=$1

  shift 1
  test -n "$1" || set -- $(vc_list_local_branches $prefix)
  pwd=$(pwd -P)

  cd $pwd/$prefix

  test -d .git || error "Not a standalone .git: $prefix" 1

  test -e .git/FETCH_HEAD && younger_than .git/FETCH_HEAD $PD_SYNC_AGE && {
    return
  }

  test ! -d .git/annex || {
    git annex sync
    return $?
  }

  cd $pwd

  (
    diskdoc__meta -s list-upstream "$prefix" "$@" \
      || {
        warn "No sync setting, skipping $prefix"
        return 1
      }
  ) | while read remote branch
  do
    fnmatch "*annex*" $branch && continue || noop

    cd $pwd/$prefix

    git fetch --quiet $remote || {
      error "fetching $remote"
      touch $failed
      continue
    }

    local remoteref=$remote/$branch

    git show-ref --quiet $remoteref || {
      test -n "$choice_sync_push" && {
        git push $remote +$branch
      } || {
        error "Missing remote branch in $prefix: $remoteref"
        touch $failed
        continue
      }
    }

    local ahead=0 behind=0

    git diff --quiet ${remoteref}..${branch} \
      || ahead=$(git rev-list ${remoteref}..${branch} --count) \

    git diff --quiet ${branch}..${remoteref} \
      || behind=$(git rev-list ${branch}..${remoteref} --count)

    test $ahead -eq 0 -a $behind -eq 0 && {
      info "In sync: $prefix $remoteref"
      continue
    }

    test $ahead -eq 0 || {
      note "$prefix ahead of $remote#$branch by $ahead commits"
      test -n "$dry_run" \
        || git push $remote $branch \
        || touch $failed
    }

    test $behind -eq 0 || {
      # ignore upstream commits?
      test -n "$choice_sync_dismiss" \
        || {
          note "$prefix behind of $remote#$branch by $behind commits"
          test -n "$dry_run" || touch $failed
        }
    }

  done

  # XXX: look into git config for this: git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads
}

# Assert checkout exists, or reinitialize from Pd document.
diskdoc_run__enable=y
diskdoc__enable()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1
  diskdoc__meta_sq get-repo $1 || error "No repo for $1" 1
  diskdoc__meta -sq enabled $1 || diskdoc__meta enable $1
  test -d $1 || {
    upstream="$(diskdoc__meta list-upstream "$1" | sed 's/^\([^\ ]*\).*$/\1/g' | head -n 1)"
    test -n "$upstream" || upstream=origin
    uri="$(diskdoc__meta get-uri "$1" $upstream)"
    test -n "$uri" || error "No uri for $1 $upstream" 1
    git clone $uri --origin $upstream $1 || error "Cloning $uri" 1
  }
  diskdoc__init $1
}

diskdoc_run__init=y
diskdoc__init()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1
  diskdoc__meta_sq get-repo $1 || error "No repo for $1" 1
  diskdoc__set_remotes $1
  cwd=$(pwd)
  cd $1
  git submodule udiskdocate --init --recursive
  cd $cwd
}

# Set the remotes from metadata
diskdoc_run__set_remotes=y
diskdoc__set_remotes()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1

  cwd=$(pwd)
  diskdoc__meta list-remotes "$1" | while read remote
  do
    cd "$cwd"
    url=$(diskdoc__meta get-uri "$1" $remote)
    cd "$cwd/$1"
    git config remote.$remote.url >/dev/null && {
      test "$(git config remote.$remote.url)" = "$url" || {
        no_act \
          && echo "git remote add $remote $url ( ** DRY RUN ** )" \
          || git remote set-url $remote $url
      }
    } || {
      no_act \
        && echo "git remote add $remote $url ( ** DRY RUN ** )" \
        || git remote add $remote $url
    }
  done

  cd $cwd
}

no_act()
{
  test -n "$dry_run"
}


# Disable prefix. Remove checkout if clean.
diskdoc_run__disable=y
diskdoc__disable()
{
  test -n "$1" || error "prefix argument expected" 1
  test -z "$2" || error "Surplus arguments: $2" 1

  diskdoc__meta_sq disabled $1 && {
    info "Already disabled: $1"

  } || {

    diskdoc__meta disable $1 \
      && note "Disabled $1"
  }

  test ! -d $1 && {
    info "No checkout, nothing to do"
  } || {
    note "Found checkout, getting status.."

    choice_strict=1 \
      vc_clean $1 \
      || case "$?" in
          1 ) warn "Dirty: $(__vc_status "$1")" 1 ;;
          2 ) note "Crufty: $(__vc_status "$1")" 1 ;;
        esac

    choice_sync_dismiss=1 \
    diskdoc sync $1 \
      || error "Not in sync: $1" 1

    rm -rf $1 \
      && note "Removed checkout $1"
  }
}


diskdoc_run__add=y
diskdoc__add()
{
  test -n "$1" || error "expected GIT URL" 1
  test -n "$2" || error "expected prefix" 1
  test -d "$(dirname "$2")" || error "not in a dir: $2" 1
  diskdoc__meta put-repo $2 origin=$1 enabled=true clean=tracked sync=pull || return $?
  diskdoc__enable $2
}



# ----


diskdoc__usage()
{
  echo 'Usage: '
  echo "  $scriptname.sh <cmd> [<args>..]"
}

diskdoc__help()
{
  diskdoc__usage
  echo 'Functions: '
  echo '  status                           List abbreviated status strings for all repos'
  echo ''
  echo '  help                             print this help listing.'
  # XXX _init is bodged, std_help diskdoc "$@"
}

diskdoc__load()
{
  for x in $(try_value "${subcmd}" "" run | sed 's/./&\ /g')
  do case "$x" in

      y )
        # set/check for Pd for subcmd

        diskdoc=projects.yaml

        # Find dir with metafile
        prerun=$(pwd)
        prefix=$2

        while test ! -e "$diskdoc"
        do
          test -n "$prefix" \
            && prefix="$(basename $(pwd))/$prefix" \
            || prefix="$(basename $(pwd))"
          cd ..
          test "$(pwd)" = "/" && break
        done

        test -e "$diskdoc" || error "No projects file $diskdoc" 1
        p="$(realpath $diskdoc | sed 's/[^A-Za-z0-9_-]/-/g' | tr -s '_' '-')"
        sock=/tmp/diskdoc-$p-serv.sock
        ;;

      f )
        # Preset name to subcmd failed file placeholder
        req_vars base subcmd
        test -n "$diskdoc" && {
          req_vars p
          failed=/tmp/${base}-$p-$subcmd.failed
        } || {
          failed=/tmp/${base}-$subcmd.failed
        }
        ;;

      b )
        # run metadata server in background for subcmd
        diskdoc_meta_bg_setup
        ;;

    esac
  done

  export PD_SYNC_AGE=$_3HOUR

  local tdy="$(try_value "${subcmd}" "" today)"
  test -z "$tdy" || {
    today=$(statusdir.sh file $tdy)
    tdate=$(date +%y%m%d0000)
    test -n "$tdate" || error "formatting date" 1
    touch -t $tdate $today
  }

  uname=$(uname)
}

diskdoc__unload()
{
  for x in $(try_value "${subcmd}" "" run | sed 's/./&\ /g')
  do case "$x" in
      y )
        test -z "$sock" || {
          diskdoc_meta_bg_teardown
          unset bgd sock
        }
        ;;
  esac; done
  unset subcmd subcmd_pref \
          def_subcmd func_exists func

  test -z "$failed" -o ! -e "$failed" || {
    rm $failed
    unset failed
    return 1
  }
}

diskdoc_init()
{
  local __load_lib=1
  . ~/bin/std.sh
  . ~/bin/main.sh
  #while test $# -gt 0
  #do
  #  case "$1" in
  #      -v )
  #        verbosity=$(( $verbosity + 1 ))
  #        incr_c
  #        shift;;
  #  esac
  #done
  . ~/bin/diskdoc.inc.sh "$@"
  . ~/bin/os.lib.sh
  . ~/bin/date.lib.sh
  . ~/bin/match.sh load-ext
  . ~/bin/vc.sh load-ext
  test -n "$verbosity" || verbosity=6
  # -- diskdoc box init sentinel --
}

diskdoc__lib()
{
  local __load_lib=1
  . ~/bin/util.sh
  . ~/bin/box.lib.sh
  # -- diskdoc box lib sentinel --
}


### Main

diskdoc__main()
{
  local scriptname=diskdoc base=$(basename $diskdoc__source .sh) \
    subcmd=$1

  case "$base" in

    $scriptname )

        # invoke with function name first argument,
        local scsep=__ bgd= \
          subcmd_pref=${scriptalias} \
          def_subcmd=status \
          func_exists= \
          func= \
          sock= \
          c=0

        diskdoc_init "$@"
        shift $c

        try_subcmd && {
          diskdoc__lib
          box_src_lib diskdoc
          shift 1
          diskdoc__load $subcmd "$@" || return
          $func "$@" || r=$?
          diskdoc__unload
          exit $r
        }

      ;;

    * )
      echo "Not a frontend for $base ($scriptname)"
      exit 1
      ;;

  esac
}

case "$0" in "" ) ;; "-*" ) ;; * )

  # Ignore 'load-ext' sub-command
  # XXX arguments to source are working on Darwin 10.8.5, not Linux?
  # fix using another mechanism:
  test -z "$__load_lib" || set -- "load-ext"
  case "$1" in load-ext ) ;; * )

      diskdoc__main "$@"
    ;;

  esac ;;
esac

