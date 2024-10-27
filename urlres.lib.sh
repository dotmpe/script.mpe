### URLRes: manage local copies for URL's

# FIXME: should really rename part url{res->tpl},
# also use web/urlref api better

urlres_lib__load ()
{
  lib_require hash str web || return
  : "${CACHE_DIR:=.meta/cache}"
  #: "${urlres_cachekey_format:=cksums}"
  #: "${urlres_cachekey_algo:=md5}"
  #: "${urlres_cachekey_salt:=123}"
  # TODO
  : "${urlres_cachekey_idhash:=false}"
  : "${urlres_key_prefix:=urlres:}"
}

urlres_lib__init ()
{
  true # XXX: Update lib.lib, and move lib-require here
  test -d "${CACHE_DIR:?}" ||
    $INIT_LOG alert ":urlres-lib" "No such directory" "$_" 1
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized urlres.lib" "$(sys_debug_tag)"
}


# Retrieve resource URL using cUrl backend (http-deref*)
urlres () # ~ <Key> [<Inputs...>]
{
  declare lk=${lk:-}:urlres
  # Determine cache file names, do HTTP HEAD to determine extension if needed
  urlres_files "$@" || return
  #http_deref "$url" "$cachef" "$etagf"
  http_deref_cache_etagfile "$cachef" "$etagf" "$url"
}

# Encode urlres key and checksum of options into cache file name
urlres_cachekey_cksums () # ~ <Key> <Inputs...>
{
  declare lk=${lk:-}:cachekey-cksums
  declare salt=${urlres_cachekey_salt-} kalgo=${urlres_cachekey_algo:-md5}
  if_ok "$(hash_str "$kalgo" "$salt${*:2}")" || return
  "${urlres_cachekey_idhash:-false}" "$_" && {
    if_ok "${urlres_key_prefix-}$(hash_str "$kalgo" "$salt$1"):$_" || return
  } || {
    : "${urlres_key_prefix-}$1:$_"
  }
  cache_name=$_
  $LOG info "$lk" "Set cache file location" "$cache_name"
}

# Encode urlres key and options directly into cache name
urlres_cachekey_plain () # ~ <Key> <Inputs...>
{
  # Concatenate key+inputs by ':'
  local oldIFS=$IFS;IFS=:
  cache_name=$(echo "${urlres_key_prefix:-}${*:?}")
  IFS=$oldIFS
}

urlres_clear () # ~ <...>
{
  unset urlres_{key,keyid} pattern format format_inputs inputs url cache_name cachef etagf
}

# Set url, and paths of cache files for entity and etag.
urlres_files () # ~ <urlres-ref-args...>
{
  urlres_ref "$@" || return
  : "${cachep:="${CACHE_DIR:?}/${cache_name:?}"}"
  : "${etagf:="${cachep:?}.etag"}"
  cachef_ext=${urlres_fext:-}
  [[ $cachef_ext ]] || {
    # Best effort to get filename extension, try URL and else do HEAD request.
    cachef_ext=$(urlref_abs "$url" .filename-extension) || {

      : "${headf:="${CACHE_DIR:?}/$cache_name.about"}"
      # XXX: assume here res mt doesnt change (needs cache-v as well)
      test -e "$headf" || {
        web_about "$url" "$headf" ||
          $LOG error ":web-about" "Retrieving filename extension for URL" E$? $? || return
      }
      file -s "$headf"
      stderr declare -p headf
      if_ok "$(< "${headf:?}" grep -oiP '^content-type: \K.*$')" &&
      test -n "$_" && {
        : "${_%%; *}"
        cachef_ext=$(basename-reg getext --one "$_") || return
      } || cachef_ext=.web
    }
  }
  : "${cachef:="${cachep:?}$cachef_ext"}"
}

# Process arguments and set url, but do nothing else.
urlres_ref () # ~ <Key> <Inputs...> # Produce URL reference
{
  # Reset env if key doesnt match current
  test "${1:-${urlres_id:?}}" = "${urlres_id:-}" || {
    test -z "${urlres_id:-}" || {
      urlres_clear
      urlres_id=$1
    }
    urlres_parse_arg "$@" || return
  }
  # Retrieve env from urlres-store (XXX: should be in above clause?)
  urlres_ref_${urlres_store:-env} &&
  # Output URL
  urlres_format
}

# Take key to retrieve URL pattern and options from env variable(s)
urlres_ref_env () # ~ <...>
{
  declare lk=${lk:-}:ref-env key=${urlres_key:?} kid=${urlres_keyid:?}
  pattern=${!kid:-}
  test -n "$pattern" && {
    $LOG debug "$lk" "Found pattern spec at key '$key'" "${_//%/%%}"
    local spec=${pattern}
    format=${spec/:*}
    spec="${spec:$(( ${#format} + 1 ))}"
    : "${format:=printf}"
    format_inputs=${spec/:*}
    pattern=${spec:$(( ${#format_inputs} + 1 ))}
    : "${format_inputs:=urlencode}"
  } || {
    : "${kid}_format"
    format=${!_:-printf}
    : "${kid}_format_inputs"
    format_inputs=${!_:-urlencode}
    : "${kid}_pattern"
    pattern=${!_:?Pattern expected for \'$key\'}
    $LOG info "$lk" "Found pattern at basename" "$key"
  }
}

# Format the url using the method, first formatting inputs if function for that
# was specified.
urlres_format () # ~ <...>
{
  [[ ! $format_inputs ]] || {
    local i
    for i in ${!inputs[*]}
    do
      inputs[i]=$($format_inputs "${inputs[i]}") || return
    done
  }
  url=$(strfmt_${format:?} "${pattern:?}" "${inputs[@]:?}")
}

# Parse key and inputs, so that URL pattern can be retrieved. Also sets
# cache-name, but cache extension will depend on formatted url or HTTP HEAD
# later.
urlres_parse_arg () # ~ <Key> <Inputs...>
{
  urlres_key=${1:?} urlres_keyid="${1//[:-]/_}"

  declare -ga inputs=( "${@:2}" )

  urlres_cachekey_${urlres_cachekey_format:-cksums} "$@"
}

#
