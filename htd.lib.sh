
htd_relative_path()
{
  cwd=$(pwd)
  test -e "$1" && {
    x_re "${1}" '\/.*' && {
      error "TODO make rel"
    }
    x_re "${1}" '[^\/].*' && {
      x_re "${1}" '((\.\/)|(\.\.)).*' && {
        relpath="${1: 2}"
      } || {
        relpath="$1"
      }
      return 0
    }
  }
  return 1
}


req_htdir()
{
  test -n "$HTDIR" -a -d "$HTDIR" || return 1
}

# Check if binary is available for tool
installed()
{
  test -e "$1" || error installed-arg1 1
  test -n "$2" || error installed-arg2 1
  test -z "$3" || error "installed-args:$3" 1

  # Get one name if any
  local bin="$(jsotk.py -O py path $1 tools/$2/bin)"
  test "$bin" = "True" && bin="$2"
  test -n "$bin" || {
    warn "Not installed '$2' (bin/$bin)"
    return 1
  }

  case "$bin" in
    "["*"]" )

        statusdir.sh set "htd:installed:$1:$2" 0 180

        # Or a list of names
        jsotk.py -O py items $1 tools/$2/bin | while read bin_
        do
          test -n "$bin_" || continue
          test -n "$(eval echo "$bin_")" || warn "No value for $bin_" 1
          test -n "$(eval which $bin_)" && {
            statusdir.sh incr "htd:installed:$1:$2"
          }
        done

        count=$(statusdir.sh get htd:installed:$1:$2)
        test -n "$count" -a 0 -ne $count || return 1

        return 0;
      ;;
  esac

  test -n "$(eval echo "$bin")" || warn "No value for $bin" 1
  test -n "$(eval which $bin)" && return
  #local version="$(jsotk.py objectpath $1 '$.tools.'$2'.version')"
  #$bin $version && return || break

  return 1;
}

install_bin()
{
  test -e "$1" || error install-bin-arg1 1
  test -n "$2" || error install-bin-arg2 1
  test -z "$3" || error "install-bin-args:$3" 1

  installed "$@" && return

  # Look for installer
  installer="$(jsotk.py -N -O py path $1 tools/$2/installer)"
  test -n "$installer" || return 3
  test -n "$installer" && {
    id="$(jsotk.py -N -O py path $1 tools/$2/id)"
    test -n "$id" || id="$2"
    debug "installer=$installer id=$id"
    case "$installer" in
      npm )
          npm install -g $id || return 2
        ;;
      pip )
          pip install --user $id || return 2
        ;;
      git )
          url="$(jsotk.py -N -O py path $1 tools/$2/url)"
          test -d $HOME/.htd-tools/cellar/$id || (
            git clone $url $HOME/.htd-tools/cellar/$id
          )
          (
            cd $HOME/.htd-tools/cellar/$id
            git pull origin master
          )
          bin="$(jsotk.py -N -O py path $1 tools/$2/bin)"
          src="$(jsotk.py -N -O py path $1 tools/$2/src)"
          test -n "$src" || src=$bin
          (
            cd $HOME/.htd-tools/bin
            test ! -e $bin || rm $bin
            ln -s $HOME/.htd-tools/cellar/$id/$src $bin
          )
        ;;
    esac
  } || {
    jsotk.py objectpath $1 '$.tools.'$2'.install'
  }

  jsotk.py items $1 tools/$2/post-install | while read scriptline
  do
    scr=$(echo $scriptline | cut -c2-$(( ${#scriptline} - 1 )) )
    note "Running '$scr'.."
    eval $scr || exit $?
  done
}

uninstall_bin()
{
  test -e "$1" || error uninstall-bin-arg1 1
  test -n "$2" || error uninstall-bin-arg2 1
  test -z "$3" || error uninstall-bin-args 1

  installed "$@" || return 0

  installer="$(jsotk.py -N -O py path $1 tools/$2/installer)"
  test -n "$installer" || return 3
  test -n "$installer" && {
    id="$(jsotk.py -N -O py path $1 tools/$2/id)"
    debug "installer=$installer id=$id"
    test -n "$id" || id=$2
    case "$installer" in
      npm )
          npm uninstall -g $id || return 2
        ;;
      pip )
          pip uninstall $id || return 2
        ;;
    esac
  }

  jsotk.py items $1 tools/$2/post-uninstall | while read scriptline
  do
    note "Running '$scriptline'.."
    eval $scriptline || exit $?
  done
}

tools_json()
{
  test -e $HTD_TOOLSFILE
  test $HTD_TOOLSFILE -ot ./tools.json \
    || jsotk.py yaml2json $HTD_TOOLSFILE ./tools.json
}

define_var_from_opt()
{
  case "$1" in
    --*=* )
        eval $(echo "$1" | cut -c3- | tr '-' '_')
      ;;
    --* )
        eval $(echo "$1" | cut -c3- | tr '-' '_')=1
      ;;
  esac
}

htd_options_v()
{
  set -- $(lines_to_words $options)
  while test -n "$1"
  do
    case "$1" in
      --yaml ) format_yaml=1 ;;
      --interactive ) choice_interactive=1 ;;
      --non-interactive ) choice_interactive=0 ;;
      * ) trueish "$define_all" && {
          define_var_from_opt "$1"
        } || {
          error "unknown option '$1'" 1
        };;
    esac
    shift
  done
}

htd_report()
{
  # leave htd_report_result to "highest" set value (where 1 is highest)
  htd_report_result=0

  while test -n "$1"
  do
    case "$1" in

      passed )
          test $passed_count -gt 0 \
            && info "Passed ($passed_count): $passed_abbrev"
        ;;

      skipped )
          test $skipped_count -gt 0 \
            && {
              note "Skipped ($skipped_count): $skipped_abbrev"
              test $htd_report_result -eq 0 -o $htd_report_result -gt 4 \
                && htd_report_result=4
            }
        ;;

      error )
          test $error_count -gt 0 \
            && {
              error "Errors ($error_count): $error_abbrev"
              test $htd_report_result -eq 0 -o $htd_report_result -gt 2 \
                && htd_report_result=2
            }
        ;;

      failed )
          test $failed_count -gt 0 \
            && {
              warn "Failed ($failed_count): $failed_abbrev"
              test $htd_report_result -eq 0 -o $htd_report_result -gt 3 \
                && htd_report_result=3
            }
        ;;

      * )
        ;;

    esac
    shift
  done

  return $htd_report_result
}

htd_passed()
{
  test -n "$passed" || error htd-passed-file 1
  stderr ok "$1"
  echo "$1" >>$passed
}

htd_main_files()
{
  for x in "" .txt .md .rst
  do
    for y in ReadMe main ChangeLog index doc/main docs/main
    do
      for z in $y $(str_upper $y) $(str_lower $y)
      do
        test -e $z$x && printf "$z$x "
      done
    done
  done
}

# Build a table of paths to env-varnames, to rebuild/shorten paths using variable names
htd_topic_names_index()
{
  test -n "$1" || set -- pathnames.tab
  { test -n "$UCONFDIR" -a -s "$UCONFDIR/$1" && {
    local tmpsh=$(setup_tmpf .topic-names-index.sh)
    { echo 'cat <<EOM'
      read_nix_style_file "$UCONFDIR/$1"
      echo 'EOM'
    } > $tmpsh
    $SHELL $tmpsh
    rm $tmpsh
  } || { cat <<EOM
/ ROOT
$HOME/ HOME
EOM
    }
  } | uniq
}

