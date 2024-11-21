#!/bin/sh

# Deal with package metadata files


package_lib__load () # (env PACKMETA) [env out_fmt=json]
{
  lib_require sys os os-htd src || return
  : "${out_fmt:=json}"
  : "${METADIR:=.meta}"
}

package_lib__init () #
{
  test -z "${package_lib_init-}" || return $_
  ENV_LIBS="${ENV_LIBS:-}${ENV_LIBS+" "}package"
  PACK_CACHE="PACKMETA_ID PACKMETA PACKMETA_SRC PACKAGE_JSON PACK_DIR PACK_ID PACK_JSON PACK_SH"

  : "${LCACHE_DIR:=$METADIR/cache}"
  : "${PACK_DIR:=$METADIR/package}"

  : "${PACK_TOOLS:=$PACK_DIR/tools}"
  : "${PACK_ENVD:=$PACK_DIR/envs}"
  : "${PACK_SCRIPTS:=$PACK_DIR/scripts}"

  # Clear to skip auto-load, or set to give local require-level
  ! "${package_lib_auto:-true}" && {
    ! sys_debug -dev -debug -init ||
      $LOG notice "" "Pre-initialized package.lib" "$(sys_debug_tag)"
  } || {
    package_init || return
    ! sys_debug -dev -debug -init ||
      $LOG notice "" "Initialized package.lib" "$(sys_debug_tag)"
  }
}

# Output lib env for static profile, cached load
package_lib_env () #
{
  PACKMETA_ID=1 # Static Id; to indicate static env was loaded already
  for var in $PACK_CACHE
  do printf '%s="%s"\n' "$var" "${!var}"
  done
}

package_lib_unset () #
{
  unset -v $PACK_CACHE
}

# Look at paths and list the first super-directory that has initialized
# package meta. (This will not check for package.y*ml and initialize dirs)
package_basedir_for_paths () # ~ <Paths...>
{
  #metadir_basedirs "${@:?}"
  fs_basedir_with "${METADIR:?}"/package/main.json "${@:?}"
}

#
package_basedir_split () # ~ <Path>
{
  local packagedir
  packagedir=$(package_basedir_for_paths "${1:?}") || return
  echo "$packagedir ${1:$(( 1 + ${#packagedir} ))}"
}

package_init () # [Package-Dir] [Package-Id]
{
  test $# -gt 0 || set -- .
  # Keep seed value if set
  test $# -gt 1 || set -- "$1" "${package_id-}"

  test -d "$1/$LCACHE_DIR" || mkdir -p "$1/$LCACHE_DIR"
  test -d "$1/$PACK_DIR" || mkdir -p "$1/$PACK_DIR"
  test -d "$1/$PACK_TOOLS" || mkdir -p "$1/$PACK_TOOLS"
  test -d "$1/$PACK_ENVD" || mkdir -p "$1/$PACK_ENVD"
  test -d "$1/$PACK_SCRIPTS" || mkdir -p "$1/$PACK_SCRIPTS"

  package_env_reset && package_lib_set_local "$@" || true
}

# Detect package format and set PACKMETA
package_detect () # [Package-Dir]
{
  test $# -gt 0 || set -- $package_dir
  local ext
  for ext in yml yaml sh
  do
    test -e $1/package.$ext || continue
    package_fmt=$ext
    break
  done
  test -n "${package_fmt-}" || return
  PACKMETA="package.$package_fmt"
}

# Require sh package env. (but don't prepare)
package_env_req () # ~
{
  local r
  test -n "${PACK_SH-}" -a -f "${PACK_SH-}" && {
    note "Loading package lib env <$PACK_SH>"
    . "$PACK_SH" || r=$?
  }
  package_defaults || return
  return ${r-}
}

# Preprocess source if needed
package_preproc () #
{
  test $# -eq 0 || return 98
  # If actual source file different than package file setting
  test -e "$PACKMETA" -a -z "$PACKMETA_SRC" || {
    test -e "$PACKMETA_SRC" || return
    # And source file is newer
    test -e "$PACKMETA" -a "$PACKMETA" -nt "$PACKMETA_SRC" &&
      debug "Reprocessed package up-to-date <$PACKMETA>" || {
      # Process include-directives
      add_sentinels=1 expand_include_sentinels "$PACKMETA_SRC" > "$PACKMETA"
      info "Re-processed package source <$PACKMETA_SRC>"
    }
  }
}

# Reset package_* vars (clear or default)
package_env_reset () #
{
  test $# -eq 0 || return 98

  default_package_id=
  default_package_shell=/bin/sh

  package_dir=
  package_id=
  # XXX: rename
  package_build_unit_spec=
  package_specs_units=
  #
  package_components=
  package_component_name=
  package_cwd=
  package_default=
  package_description=
  package_doc_find=
  package_docs_find=
  package_lists_documents=
  package_env=
  package_ext_make_files=
  package_lists_contexts_std=
  package_log=
  package_log_dir=
  package_log_doctitle_fmt=
  package_main=
  package_paths=
  package_pd_meta_checks=
  package_pd_meta_tests=
  package_pd_meta_git_hooks_pre_commit_script=
  package_pd_meta_stats=
  package_pd_meta_tasks_document=
  package_pd_meta_tasks_done=
  package_repo=
  package_shell=
  package_type=
  package_vendor=
  package_version=
  package_check_method=
  package_build_method=
  package_test_method=
  package_permalog_method=
}

package_env_unset ()
{
  unset -n $( type package_env_reset | grep -oP '(?<=    )([^=]+)(?==)')
}

# Setup env to process package from YAML to JSON, and Sh
# TODO: require-level
# 0):
#   - do not return any error (ie. for missing files, empty env)
#   - allow static init if
#   - set for PACKMETA (even if OOD, PACKMETA_SRC is newer)
#   - use main.json symlink to determine package-id, if not given
#   - set other PACKMETA_* vars, do not load anything
# 1):
#   - load static if available or else update entire env, return if error
#   - detect PACKMETA Y*ml or Sh, convert to json
#   - determine main package-id, if not given. Symlink main JSON and Sh
#   - convert main package part to JSON
# 2):
#   - ignore static env, reset and then 0)
# 3):
#   - ignore static env, reset and then 1)
package_lib_set_local () # ~ <Package-path> [<Id>]
{
  test -d "${1-}" || error "package.lib set-local path" 1
  #test $# -gt 1 -a -n "${2-}" ||
  #    set -- "$1" "${package_lib_auto:-0}" "${3-}"

  # If static env loaded (non-zero ID), use that; abort further dynamic init
  #test "${PACKMETA_ID=0}" -eq 0 -a \( $2 -le 1 \) || return 0

  package_dir="$1"
  package_detect || {
    sys_astat -eq 1 || return
    ! "${package_require:-false}" && return || return 127
  }

  # Detect wether Pre-process is needed
  grep -q '^#include\ ' "$PACKMETA" && {
    PACKMETA_SRC="$PACKMETA"
    PACKMETA=$METADIR/cache/package.$package_fmt
    package_preproc || return
  } || PACKMETA_SRC=''

  PACKAGE_JSON=$METADIR/cache/package.json
  test -s $PACKAGE_JSON -a $PACKMETA -ot $PACKAGE_JSON || {

    package_lib_update_json || return
  }

  test -n "${2-}" -a "${2-}" != "(main)" && {
    package_id=$(package_id "$2") || return

  } || {
    default_package_id=$(package_default_id) || return
    package_id="$default_package_id"
    symlink_assert $1/$PACK_DIR/main.sh $package_id.sh
    symlink_assert $1/$PACK_DIR/main.json $package_id.json
  }
  test -n "$package_id" || return
  $LOG note "" "Set package-Id" "$package_id"
  PACK_JSON=$PACK_DIR/$package_id.json
  PACK_SH=$PACK_DIR/$package_id.sh
}

package_defaults()
{
  test $# -eq 0 || return 98
  test -n "${package_main-}" || package_main="${package_id-}"
  test -n "${package_log_dir-}" && {
      test -n "${package_log-}" || package_log="$package_log_dir"
  } || {
      test -z "${package_log-}" || package_log_dir="$package_log"
  }
  # XXX: package_environments=main\ dev\ test\ ci\ build\ redo
  test -n "${package_env_name-}" || package_env_name=main

  test -n "${package_components-}" || package_components=package_components
  test -n "${package_component_name-}" || package_component_name=package_component_name

  test -n "${package_permalog_path-}" || package_permalog_path=cabinet
  test -n "${package_permalog_method-}" || package_permalog_method=archive
  test -n "${package_pd_meta_checks-}" || package_pd_meta_checks=
  test -n "${package_check_method-}" || package_check_method=
  test -n "${package_pd_meta_tests-}" || package_pd_meta_tests=
  test -n "${package_pd_meta_targets-}" || package_pd_meta_targets=
  test -n "${package_lists_documents-}" ||
      package_lists_documents=doc-list-files-exts-re
  test -z "${tasks_lib_load-}" && return # XXX: other way to deal with components

  tasks_package_defaults
}

# Look for package with main attribute
package_default_id () # [Package-Type] [Package-JSON]
{
  test -n "${1-}" || set -- "${package_type:-"application/vnd.org.wtwta.project"}"
  jq -r 'map(select(.type=="'"$1"'" and .main)) | .[] | (.main,.id)' $PACKAGE_JSON | tail -n 1
}

package_id () # Package-Id [Package-Type]
{
  test -n "${2-}" || set -- "$1" "${package_type:="application/vnd.org.wtwta.project"}"
  jq -r 'map(select(.type=="'"$2"'" and .id=="'"$1"'")) | .[].id' $PACKAGE_JSON
}

package_file () # [metaf] ~ [<Dir>] # Check for or set metaf{,_src} and run preproc
{
  test -n "${metaf-}" || metaf="$(echo $1/package.y*ml | cut -f1 -d' ')"
  test -e "$metaf" || error "No package-file at '$1' '$metaf'" 1
  metaf="$(normalize_relative "$metaf")"

  # Check wether we need to pre-proc file
  grep -q '^#include\ ' "$metaf" && {
    metaf_src="$metaf"
    metaf="$1"/.htd/package.yaml
  } || metaf_src=''

  test -e "$metaf" -a -z "$metaf_src" || {
    test -e "$metaf_src" || return
    mkdir -p "$(dirname "$metaf")"
    test -e "$metaf" -a "$metaf" -nt "$metaf_src" || {
      add_sentinels=1 expand_include_sentinels "$metaf_src" > "$metaf"
    }
  }
  test -e "$metaf" || return 1
}


package_basename()
{
  test -n "${1-}" || set -- "$PACKMETA"
  basename "$(basename "$(basename "$1" .json)" .yaml)" .yml
}


package_lib_update_json () # FILE SRC
{
  test $# -gt 0 || set -- "$PACKMETA"
  test $# -gt 1 || set -- "$1" "$PACKAGE_JSON"
  test $# -eq 2 || return 98

  case "$1" in
      *.sh ) grep '^[^]*=' "$1" | jsotk.py dump -I fkv - "$2" || return ;; # FIXME: jsotk.py dump -I fkv
      *.yml | *.yaml ) jsotk.py yaml2json "$1" "$2" || return ;;
      * ) return 99;
  esac
}


package_update_json ()
{
  test $# -gt 0 || set -- "$PACKAGE_JSON"
  test $# -gt 1 || set -- "$1" "$PACK_JSON"
  test -e $1 || return 96
  test -s $2 -a $1 -ot $2 && return

  stderr debug "$1 is newer than $2"
  note "Regenerating $2 from $1.."
  jq 'map(select(.id=="'"$package_id"'" or .main=="'"$package_id"'")) | .[0]' \
      $1 >"$2" || return
  grep -qv '^null$' "$2" || {
    rm "$2"
    error "Failed reading package '$package_id' from $1 ($?)" 1
  }
}


jsotk_package_sh_defaults()
{
  test -e "$1" || error "jsotk-package-sh-defaults no file '$1'" 1
  {
    jsotk.py -I yaml -O fkv objectpath $1 '$..*[@.*.defaults]' \
      || {
        # TODO: check ret codes warn "Failed reading package defaults from $1 ($?)"
        return 1
      }

  } | sed 's/^\([^=]*\)=/test -n "$\1" || \1=/g'
}

# Easy access for shell to package: convert to Sh vars.
package_update_sh () # [Package-Dir]
{
  test $# -gt 0 || set -- .
  test -n "$1" -a -d "$1" || error "update-package-sh dir '$1'" 21
  test -s "$PACK_JSON" || error "update-package-sh json '$PACK_JSON'" 22

  local metash=$PACK_SH metaf=$PACK_JSON
  #metash=$(normalize_relative "$metash")

  test ! -e "$1/$metash" -o -f "$1/$metash" || {
    error "metash file: $1/$metash"
    return 1
  }
  test -s $1/$metash -a $1/$metaf -ot $1/$metash || {
    # Format Sh script/vars from local package
    note "Regenerating $metash from $metaf.."

    # Format Sh default env settings
    { echo "#!${package_shell:="$default_package_shell"}"; {
        jsotk_package_sh_defaults "$1/$metaf" || {
        test ! -e $1/$metash || rm $1/$metash
      }; } | sort -u ; } > $1/$metash

    test -s "$1/$metash" && {
      grep -q Exception $1/$metash && rm $1/$metash
    } || {
      test -z "$metash" -o ! -e "$1/$metash" || rm $1/$metash
    }

    #test -s "$metamain" || {
    #  warn "Failed reading package main from $1 ($package_id)"
    #  test -z "$metamain" -o ! -e "$metamain" ||
    #    rm $metamain
    #  return 16
    #}

    { { echo "#!$package_shell";
      jsotk.py --output-prefix=package to-flat-kv "$1/$metaf" | sort -u
    } >> "$1/$metash" ; } || {
      warn "Failed writing package Sh from $1 ($?)"
      test -z "$1/$metash" -o ! -e "$1/$metash" ||
        rm "$1/$metash"
      return 15
    }
  }
}


# Allow for a sole .package.sh file to be used iso. full package.yml
# In this case create a YAML elsewhere
update_temp_package()
{
  test -n "${pdoc-}" || error pdoc 21
  test -n "${ppwd-}" || local ppwd=$(cd $1 && pwd)

  vid=$(str_word "$ppwd")
  metaf=$(setup_tmpf .yml "-meta-$vid")
  test -e $metaf || touch $metaf $pdoc

  metash=$(pathname "$metaf" .yml .yaml).sh
  fnmatch "$TMPDIR/*" "$metash" || metash=$(dotname "$metash")
  metajs=$(pathname "$metaf" .yml .yaml).js
  fnmatch "$TMPDIR/*" "$metajs" || metajs=$(dotname "$metajs")
  metamain=$(pathname "$metaf" .yml .yaml).main
  fnmatch "$TMPDIR/*" "$metamain" || metamain=$(dotname "$metamain")

  test -e $metaf -a $metaf -nt $pdoc || {
    pd__meta package $1 > $metaf
  }
  PACKMETA=$metaf
}


# Given package.yaml metafile, extract and fromat as SH, JSON. If no local
# package.yaml exists, try to extract one temp package YAML from Pdoc.
package_update () # Dir
{
  test $# -gt 0 || set -- .
  test -n "${1-}" -a -d "${1-}" || error "update-package dir '$1'" 21
  test $# -eq 1 || error "update-package surplus args '$2'" 22

  metaf=
  local metash= metamain=
  test -n "${ppwd-}" || ppwd=$(cd $1; pwd)

  package_file "$1" || {
    std_info "Creating temp package since none exists at '$metaf'"
    update_temp_package "$1" || { r=$?
      test -z "$metaf" -o ! -e "$metaf" || rm $metaf
      error "update-temp-package: no '$metaf' for '$1'"
      return 23
    }
  }
  test -e "$metaf" || error "no such file ($PWD, $1) PACKMETA='$PACKMETA'" 34
  package_lib_set_local "$1"

  std_info "Metafile: $metaf ($PWD)"

  # Package.sh is used by other scripts
  package_update_sh "$1" || { r=$?
    test -f "$metash" || return $r
    grep -q Exception $metash && rm $metash ; return $r
  }

  # .package.json is not used, its a direct convert of te entire YAML doc.
  # Other scripts can use it with jq if required
  package_update_json || return $?
}


# Given local .package.sh exists, see about and export some requested key-values.
# map=[ PREF[:SUB ] ] package-sh KEYS
# The env 'map' is a mapping consisting of the prefix to match and strip,
# with an optional subtitution key for the prefix. The rest of the arguments
# are the keys which are passed through as value declarations on stdout.
# Non-existant keys or empty values are passed over silently.
package_sh () # Key
{
  test -n "$1" || error "package-sh keys expected" 1
  # Set or use mapping from env
  test -n "${map-}" || map=package_
  fnmatch "*:*" "$map" && {
    prefix="$(printf "$map" | cut -d ':' -f 1)"
    sub="$(printf "$map" | cut -d ':' -f 2)"
  } || {
    prefix="$map"
    sub=
  }
  [[ ${PACK_SH:+set} && -s "${PACK_SH-}" ]] || {
    error "package-sh Missing or empty '${PACK_SH:-(unset)}'" 1 || return
  }
  # Use util from str.lib to get the keys from the properties file
  property "$PACK_SH" "$prefix" "$sub" "$@"
}


# Use ObjectPath to get values
# NOTE: double-quote elements with special chars: my.path."with special".element
package_get_keys() # Property...
{
  while test $# -gt 0
  do
    jsotk.py objectpath -O${out_fmt} $PACKMETA '$.*[@.id is "'$package_id'"].'$1
    shift
  done
}

package_dir_get_keys() # Dir Package-Id [Property...]
{
  test -d "$1" || error "dir expected" 1
  local dir="$1" package_id="$2" ; shift 2
  cd "$dir"
  {
    package_lib_set_local "$dir"
    # Check/update package metadata
    test -e $PACKMETA && {
      package_update $(pwd -P) || return $?
    }
    package_get_keys "$@"
  }
}


# TODO get or set
package_default_env()
{
  set --
}


# Example/CLI getting from env
package_sh_get_env() # Name V-Id
{
  test -n "$1" || error "Path/key name expected" 1
  test -n "$2" || set -- "$1" "$(lower=true str_word "$1")"
  eval echo "\$package_${2}"
}

# Read from package.sh
package_sh_get () # PACKAGE-SH NAME-KEY
{
  test -n "$1" || set -- $PACK_SH "$2"
  # XXX: eval modes anyway, for certain interpolations?
  grep '^package_'"$2"'=' "$1" |
    sed -E 's/^[^=]*=(['\''"](.*)['\''"]$|(.*))$/\2\3/g' | sed 's/\\"/"/g'
}

# List shell profile scriptline(s), to initialize shell env with for 'scripts'
# and other project tasks (sh routines, make, cron, CI/CD, etc.)
package_sh_env ()
{
  echo "#!${package_shell:="${default_package_shell:?}"}"

  # Single line or multiline script XXX: shouldnt use env-name first?
  envkey=package_ sh_envlist env ||
      envkey=package_envs_ sh_envlist ${package_env_name:?}
}

# XXX: may should just use array decl.
# still need to lookup single-line concatenated values vs actual list
# TODO: fields like package sh_list <Prop>
sh_envlist () # ~ <Var> [<Prop>]
{
  local listk=${envkey:-}${1:?}
  test -n "${!listk-}" && {
    echo "${!listk}"
  } || {
    local seqi=0 listki=$listk listi
    listk=${listki}__${seqi}
    test -n "${!listk-}" || return
    while true
    do
      printf '%s\n' "${!listk}"
      seqi=$(( seqi + 1 ))
      listk=${listki}__${seqi}
      listi=${!listk-} && test -n "$listi" || break
    done
  }
}

# Compile env-init scriptlines to executable script
package_sh_env_script() # [Path]
{
  test -n "${PACK_SH-}" || return 90

  . "$PACK_SH"
  package_defaults

  local script_out=
  test -n "${1-}" && script_out="$1" || {
    script_out="$PACK_ENVD/$package_env_name.sh"
  }

  test -s $script_out -a $script_out -nt $PACKMETA && {
    std_info "Newest version of Env-Script $script_out exists"
  } || {
    mkdir -vp "$(dirname "$script_out")" &&
    package_sh_env > "$script_out" &&
    note "Updated Env-Script <$script_out>"
  }
}


# iso. using .package.sh read scriptlines from JSON variant
# package-sh-script SCRIPTNAME [JSOTKFILE]
package_js_script()
{
  test -n "${PACK_SH-}" || {
    package_lib_set_local "$(pwd -P)" || return
  }
  test -n "${2-}" || set -- "$1" $PACK_JSON
  test -e "$2" || error "missing package main JSON '$2'" 1
  jsotk.py path -O lines "$2" scripts/$1 || {

    error "error getting lines for '$1'"
    return 1
  }
}


# Read from package.sh, no env required. But source env if using show-eval(on)
# to interpolate/expand values.
package_sh_list() # show_index=0 show_item=1 show_eval=1 PACKAGE-SH LIST-KEY [PROP]
{
  test -n "${1-}" || {
    set -- "${PACK_SH:?}" "${2-}" "${3-}" "${4-}"
  }
  : "${show_index:=0}"
  : "${show_item:=1}"
  test 1 -eq "${show_eval:=1}" && {
      test -n "${package_main-}" || . $1
    }
  # Dont get listitem but field from of object of item
  local subp="$3" ; test -n "$subp" && subp="__$subp" || subp=''
  grep '^'"${4:-package_}${2:?"Key required for variable"}__[0-9]*$subp=" "$1" |
    sed -E 's/^'"$4$2"'__([0-9]+)'"$subp"'=(['\''"](.*)['\''"]$|(.*))$/\1 \3\4/g' |
    while read -r index item
    do
      echo \
        $(trueish "$show_index" && echo "$index") \
        "$( trueish "$show_item" && { \
                trueish "$show_eval" && \
                { eval echo $item ; } || \
                { echo "$item" | sed 's/\\"/"/g' ; } ; \
            } )"
    done
}


# NOTE: scripts must be lists or this doesn't go.
package_sh_list_exists()
{
  test -n "$(eval echo "\$package_${1}__0")"
}

package_sh_name_exists()
{
  test -n "$(eval echo "\$package_${1}")"
}

package_sh_list_or_name_exists()
{
  package_sh_list_exists "$1" || package_sh_name_exists "$1"
}

package_component_name()
{
  test -n "$1" || error package-component-name 1
  filename_baseid "$1"
  echo "$id" | $gsed -E '
    s/-((spec)|(lib))//g
    s/-[0-9]+$//g
  '
}

# Use package's paths script, or vc-tracked, to retrieve component names and
# locations. This loads all lines to do a group on the first word and takes
# significant time, but should complete without a minute for a large project
package_components()
{
# Set package-paths to cat for stin, or handler
  ${package_paths:-"vc_tracked"} "$@" | while read -r name

# Then Id by basename, and use join-lines to group common paths at that prefix
    do
      compid="$($package_component_name "$name")"
      echo "$compid $name"

# Remove hidden files lazily, then group paths after first word
    done | grep -v '^[_-]' | join_lines - ' '
}

package_component_roots()
{
# Grok either given paths on stdin, or...
  package_paths_io "$@" | while read -r name

# Then Id by basename, and use join-lines to group common paths at that prefix
    do
      fnmatch "*/*" "$name" && name="$(basedir "$name")"
      filename_baseid "$name" && echo "$id $name"
    done | sort -u | join_lines - ' '
}

package_lists_contexts_map() #
{
  test $# -gt 0 || return 98
  local local_name="$1" vid
  while test -z "${2-}"
  do
    : "$(lower=true str_word "$local_name")"
    vid="package_lists_contexts_map_$_" ;
    #shellcheck disable=SC1083
    set -- $( eval echo \"\${$vid-}\" )
    test -z "${1-}" || echo "$1"
    local_name="$(dirname "$local_name")"
    test "$local_name" != "/" -a "$local_name" != "." || break
  done
}

# Id: script-mpe/0.0.4-dev package.lib.sh
