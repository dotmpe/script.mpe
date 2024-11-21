#!/bin/sh

## Htd:Sys: dealing with vars, functions, env.

sys_htd_lib__load()
{
  export _14MB=14680064
  export _6MB=7397376
  export _5k=5120

  #test -n "$MIN_SIZE" || MIN_SIZE=1
  test -n "${MIN_SIZE-}" || MIN_SIZE=$_6MB

  : "${htd_os:="$(uname -s | tr '[:upper:]' '[:lower:]')"}"
  test -n "${username-}" || username="$(whoami | tr -dc 'A-Za-z0-9_-')"
  test -n "${arch-}" || arch="$(uname -p)"
  test -n "${mach-}" || mach="$(uname -m)"
}

sys_htd_lib__init()
{
  test -z "${sys_htd_lib_init-}" || return $_
  test -n "${INIT_LOG-}" || return 102

  #lib_require sys || return

  return 0 # FIXME: init-log

  lib_assert sys os str main match || {
    $INIT_LOG error "" "In sys.lib init" $0"" 1
    return 100
  }

  test -n "${SCR_SYS_SH-}" ||  {
    test -n "$SHELL" &&
        SCR_SYS_SH="$(basename "$SHELL")" ||
        SCR_SYS_SH=bash
  }

  test -n "$TMPDIR" && {
    test -z "$RAM_TMPDIR" && {
      require_fs_casematch $TMPDIR
    } || {
      test -d "$RAM_TMPDIR" || error "Not a dir $RAM_TMPDIR" 1
      require_fs_casematch "$RAM_TMPDIR"
    }
  } || {
    test -d /tmp || error "No /tmp" 1
    TMPDIR=/tmp
    $INIT_LOG info "$scriptname" "TMPDIR=$TMPDIR (should be in shell profile)" >&2
  }

  #$INIT_LOG info "" "Loaded sys.lib" "$0"
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized sys-htd.lib" "$(sys_debug_tag)"
}


# If any of VALUES it not in variable LIST, add it
assert_list() # LIST VALUES...
{
	local to_add= list=$1 items="$(eval echo "\$$1")"
	shift 1
	to_add="$( for value in $@;
		do
			fnmatch "* $value *" " $items " && continue;
			echo $value;
		done )"
	eval $list="$(echo $items $to_add)"
}

create_ram_disk()
{
  test -n "$1" || error "Name expected" 1
  test -n "$2" || error "Size expected" 1
  test -z "$3" || error "Surplus arguments '$3'" 1

  case "$htd_os" in

    darwin )
        local size=$(( $2 * 2048 ))
        diskutil erasevolume 'Case-sensitive HFS+' \
          "$1" `hdiutil attach -nomount ram://$size`
      ;;

      # Linux
      # mount -t tmpfs -o size=512m tmpfs /mnt/ramdisk

    * )
        error "Unsupported platform '$htd_os'" 1
      ;;

  esac
}

calc() { echo "$*" | bc; }
dec2hex() { awk 'BEGIN { printf "%x\n",$1}'; }

# If ITEM is in items of LIST, add VALUES not already in list
expand_item() # LIST ITEM VALUES...
{
	local to_add= list=$1 item=$2 items="$(eval echo "\$$1")"
	shift 2
	fnmatch "* $item *" " $items " && {
		assert_list $list "$@"
	} || true
}

get_kv_k() # Key-Value-Str
{
  echo "$1" | cut -d'=' -f1
}

get_kv_v() # Key-Value-Str [Env-Prefix [Key-Str]]
{
  test -n "$3" || set -- "$1" "$2" "$(get_kv_k "$1")"
  fnmatch "*=*" "$1" && {
    eval echo \"$(expr_substr "$1" "$(( 2 + ${#3} ))" "$(( ${#1} - ${#3}  ))")\"
  } || {
    eval echo \"\$$2$3\"
  }
}

hex2dec() { awk 'BEGIN { printf "%d\n",0x$1}'; }

max()
{
  # XXX: use awk for this
  p= s= act=echo foreach_do "$@" | sort | tail -n 1
}

min()
{
  # XXX: use awk for this
  p= s= act=echo foreach_do "$@" | sort -r | tail -n 1
}

mktar() { tar czf "${1%%/}.tar.gz" "${1%%/}/"; }
mkmine() { sudo chown -R ${USER} ${1:-.}; }

pwd_p()
{
  test -n "${PWP-}"
}

pop_pwd()
{
  test -n "${PWP-}" || return 0
  PWP="${PWP%:*}"
  local pwd="${PWP//*:}"
  #local pwd="$(echo "$PWP" | cut -d':' -f1)"
  #PWP="$(echo "$PWP" | cut -d':' -f2- --output-delimiter=':')"
  test -n "$PWP" || unset PWP
  cd "$pwd"
}

pretty_print_var()
{
  sh_isset kvsep || kvsep='='
  pretty_var="$(printf -- "$1" | tr -s '_' '-')"
  falseish "$2" && {
    printf "!$pretty_var\n"
  } || {
    trueish "$2" && {
      printf "$pretty_var\n"
    } || {
      value="$(printf -- "$2" | sed 's/\ /\\ /g')"
      printf "$pretty_var$kvsep$value\n"
    }
  }
}

print_var()
{
  case "$2" in
    *'"'*|*" "*|*"'"* )
      printf -- '%s\n' "$1=\"$2\"" ;;
    * )
      printf -- '%s\n' "$1=$2" ;;
  esac
}

# prompt-ac is used to select a value based on a prefix that is either given as
# pre-filled and/or entered by the user. This is useful when the user knows the
# structure of all known values, to quickly get to a full string using only and
# as minimal key inputs, and then to possibly amend that value to create a new
# string before returning the whole value.
#
# When the structure is unclear, or the entire body of values is just to big, a
# fuzzy matcher would be more appropiate for UX.
# Also a proper UI with arrow key and other selections modes.
#
prompt_autocomplete () # ~ <Prompt> <Var> <ac>
{
  local prompt=${1:?} var=${2:?} ac=${3:?}
  prompt_autocomplete_tab () {
    # XXX: silence compgen about '-C may not work as expected'...
    # maybe should rewrite to function
    if_ok "$(compgen -C $ac "$READLINE_LINE" 2>/dev/null)" &&
    mapfile -t matches <<< "$_" && {
      [[ "${#matches[@]}" -eq 1 ]] &&
      READLINE_LINE=${matches[0]} || {
        # Print all possible values
        stderr echo "No exact match, possible values:"
        printf '%s\n' "${matches[@]}" | column
        # Common string prefix from list: Longest match using sed
        READLINE_LINE=$(<<< "$(printf '%s\n' "${matches[@]}")"  \
          sed -e 'N;s/^\(.*\).*\n\1.*$/\1\n\1/;D' )
      }
    }
    READLINE_POINT="${#READLINE_LINE}"
  }
  bind -x '"\t":"prompt_autocomplete_tab"';
  read -rep "$prompt" "${var?}";
}

push_pwd() # [Dir]
{
  test -z "${1-}" || { cd $1 || return; }
  case "$PWP" in *":$PWD" ) return ;; esac
  PWP=${PWP}:$PWD
}

pwd_init()
{
  pwd_p || PWP=$PWD
}

# require vars to be initialized, regardless of value
req_vars()
{
  while test $# -gt 0
  do
    sh_isset "$1" || { $LOG error "" "Missing variable" "$1"; return 1; }
    shift
  done
}

require_fs_casematch()
{
  local CWD="$PWD"
  test -n "$1" && {
    cd "$1"
  }
  test -e ".fs-casematch" || {
    test -e ".fs-nocasematch" && {
      $LOG warn "$scriptname" "Case-insensitive fs '$1' detected!" >&2
    } || {

      echo 'ok' > abc
      echo 'notok' > ABC
      test "$(echo $( cat abc ABC))" = "ok notok" && {
        $LOG debug "$scriptname" "Case-sensitive fs '$1' OK" >&2
        rm abc ABC || true
        touch .fs-casematch
      } || {
        test "$(echo $( cat abc ABC))" = "notok notok" && {
          rm abc || true
          $LOG warn "$scriptname" "Case-insensitive fs '$1' detected!" >&2
          touch .fs-nocasematch
        } || {
          rm abc ABC || true
          cd "$CWD"
          $LOG error "$scriptname" "Unknown error" 1 >&2
        }
      }
    }
  }
  cd "$CWD"
}

sendkey ()
{
  if [ $# -ne 0 ]; then
    echo '#' $*
    ssh $* 'cat >> ~/.ssh/authorized_keys' < ~/.ssh/id_dsa.pub
  fi
}

sys_running () # ~ <Exec>
{
  pgrep "$1" >/dev/null
}

# Sync: U-S:src/sh/lib/sys.lib.sh
