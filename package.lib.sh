#!/bin/sh


# Deal with package metadata files


package_load()
{
  # FIXME: properly initalize and use, but deal with non-CWD pack too
  PACKMETA=package.yaml
  PACKMETA_BN=$(package_basename)
  PACKMETA_JSON=.$PACKMETA_BN.json
  #PACKMETA_JS_MAIN=.$PACKMETA_BN.main.json
  #PACKMETA_SH_MAIN=.$PACKMETA_BN.main.sh
  PACKMETA_JS_MAIN=.$PACKMETA_BN.main
  PACKMETA_SH_MAIN=.$PACKMETA_BN.sh
}


package_basename()
{
  test -n "$1" || set -- "$PACKMETA"
  basename "$(basename "$(basename "$1" .json)" .yaml)" .yml
}


update_package_json()
{
  test -n "$1" || set -- ./
  test -n "$metajs" || local metajs=$1/.package.json
  metajs=$(normalize_relative "$metajs")
  test $metaf -ot $metajs \
    || {
    debug "$metaf is newer than $metajs"
    note "Regenerating $metajs from $metaf.."
    jsotk.py yaml2json $metaf $metajs \
      || return $?
  }
}


jsotk_package_sh_defaults()
{
  {
    jsotk.py -I yaml -O fkv objectpath $1 '$..*[@.*.defaults]' \
      || {
        # TODO: check ret codes warn "Failed reading package defaults from $1 ($?)"
        return 1
      }

  } | sed 's/^\([^=]*\)=/test -n "$\1" || \1=/g'
}


# Easy access for shell to package.yml/json: convert to Sh vars.
update_package_sh()
{
  test -n "$1" || set -- ./
  test -z "$2" || error "Surplus arguments '$*'" 1
  # XXX:
  #shopt -s extglob
  #fnmatch "+([A-ZA-z0-9./])" "$1" || error "Illegal format '$*'" 1

  test -n "$metash" || metash=$1/.package.sh
  test -n "$metamain" || metamain=$1/.package.main
  metash=$(normalize_relative "$metash")
  test $metaf -ot $metash \
    || {

    # Format Sh script/vars from local package
    note "Regenerating $metash from $metaf.."

    # Format Sh default env settings
    { jsotk_package_sh_defaults "$metaf" || {
      test ! -e $metash || rm $metash
    }; } | sort -u > $metash

    grep -q Exception $metash && rm $metash
    test -s "$metash" || rm $metash

    test -e "$metaf" || return

    # Format main block
    { jsotk.py -I yaml objectpath $metaf '$.*[@.main is not None]' || {
      warn "Failed reading package main from $1 ($?)"
      rm $metamain
      return 17
    }; }  > $metamain

    test -s "$metamain" || {
      warn "Failed reading package main from $1"
      rm $metamain
      return 16
    }

    jsotk.py --output-prefix=package to-flat-kv $metamain | sort -u >> $metash || {
      warn "Failed writing package Sh from $1 ($?)"
      rm $metash
      return 15
    }
  }
}


update_temp_package()
{
  test -n "$pd" || error pd 21
  test -n "$ppwd" || ppwd=$(cd $1; pwd)
  mkvid "$ppwd"
  metaf=$(setup_tmpf .yml "-meta-$vid")
  test -e $metaf || touch $metaf $pd
  #test -e "$metaf" && return || {
    metash=$1/.package.sh
    test -e $metaf -a $metaf -nt $pd || {
      pd__meta package $1 > $metaf
    }
  #}
}


# Given package.yaml metafile, extract and fromat as SH, JSON. If no local
# package.yaml exists, try to extract one temp package YAML from Pdoc.
update_package()
{
  test -n "$1" || set -- .
  test -d "$1" || error "update-package dir '$1'" 21
  test -z "$2" || error "update-package args '$*'" 22
  test -n "$ppwd" || ppwd=$(cd $1; pwd)
  test -n "$metaf" || metaf="$(echo $1/package.y*ml | cut -f1 -d' ')"
  metaf=$(normalize_relative "$metaf")

  test -e "$metaf" || {
    update_temp_package "$1" || { r=$?
      rm $metaf
      error update_temp_package-$r
      return 23
    }
  }
  test -e "$metaf" || error "metaf='$metaf'" 34

  # Package.sh is used by other scripts
  update_package_sh "$1" || {
    r=$?
    grep -q Exception $metash && rm $metash
    return $r
  }

  # .package.json is not used, its a direct convert of te entire YAML doc.
  # Other scripts can use it with jq if required
  update_package_json "$1" || return $?
}


# Given local .package.sh exists, see about and export some requested key-values.
# map=[ PREF[:SUB ] ] package-sh KEYS
# The env 'map' is a mapping consisting of the prefix to match and strip,
# with an optional subtitution key for the prefix. The rest of the arguments
# are the keys which are passed through as value declarations on stdout.
# Non-existant keys or empty values are passed over silently.
package_sh()
{
  # Set or use mapping from env
  test -n "$map" || map=package_
  fnmatch "*:*" "$map" && {
    prefix="$(printf "$map" | cut -d ':' -f 1)"
    sub="$(printf "$map" | cut -d ':' -f 2)"
  } || {
    prefix="$map"
    sub=
  }
  # Check/update package metadata
  test -e package.yaml && {
    update_package || return $?
  }
  test -e .package.sh || error package.sh 1
  # NOTE: Always be carefull about accidentally introducing newlines, will give
  # hard-to-debug syntax failures here or in the local evaluation
  (
    # Evalute matched vars in a subshell, and step over arguments
    eval "$(read_nix_style_file .package.sh | grep '^'"$prefix" | sed 's/^'"$prefix"'/'"$sub"'/g')"
    while test -n "$1"
    do
      key=$1
      value="$(eval printf -- \"\$$1\")"
      shift
      test -n "$value" || continue
      print_var "$key" "$value"
    done
  )
}


package_default_env()
{
  set --
}


package_sh_env()
{
  set --
}


# XXX: iso. using .package.sh read lines from JSON
# package-sh-script SCRIPTNAME [JSOTKFILE]
package_sh_script()
{
  test -n "$2" || set -- "$1" $PACKMETA_JS_MAIN
  test -e "$2"
  jsotk.py path -O lines "$2" scripts/$1 || {

    error "error getting lines for '$1'"
    return 1
  }
}


# package-sh-list PACKAGE-SH LIST-KEY
package_sh_list()
{
  test -n "$1" || set -- .package.sh
  test -n "$2" || error package_sh_list:list-key 1
  test -n "$show_index" || show_index=0
  test -n "$show_item" || show_item=1
  read_nix_style_file $1 | grep '^package_'"$2" |
    sed 's/^package_'"$2"'__\([0-9]*\)/\1/g' |
    while IFS='=' read index item
    do
      echo \
        $(trueish "$show_index" && echo $index) \
        $(trueish "$show_item" && echo $item)
    done
}


package_sh_list_exists()
{
  test -n "$(eval echo "\$package_${1}__0")"
}


# Id: script-mpe/0.0.4-dev package.lib.sh