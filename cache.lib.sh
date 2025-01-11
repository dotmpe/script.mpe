# extracted simplified bits from urlres.lib to do cache key management.
# cache-ref sets two things: a reference being some sort of global resource Id,
# and a name for a local cache entry of that entity.

cache_lib__load ()
{
  : "${CACHE_DIR:=.meta/cache}"
  #: "${cache_ref_format:=printf}"
  : "${cachekey_format:=cksums}"
  #: "${cachekey_store:=env}"
  #: "${cachekey_algo:=sha1}"
  #: "${cachekey_salt:=123}"
  : "${cachekey_idhash:=false}"
  : "${cachekey_prefix:=cache.lib:}"

  # XXX: test data
  : "${cache_lib_root_format:=printf}"
  : "${cache_lib_root_pattern:="::input:%s"}"
}

cache_lib__init ()
{
  test -z "${cache_lib_init-}" || return $_
  lib_require hash || return
  set -- cache_{name,ref{,_format,_pattern}} cachekey{,_{format,inputs,name}}
  cache_lib_vars=$*
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized cache.lib" "$(sys_debug_tag)"
}


cachekey_clear () # ~ ...
{
  unset ${cache_lib_vars:?Expected cache vars to unset}
}

# TODO: may want to optionally look for prefix, pattern and/or format at
cachekey_fetch_env () # ~ ...
{
  declare lk=${lk:-}:ref-env
  cache_ref_pattern=${!cachekey_name:-}
  [[ ${cache_ref_pattern:+set} ]] && {
    $LOG debug "$lk" "Found single spec cache_ref_pattern at key '$cachekey'" "${_//%/%%}"
    cache_ref_format=${cache_ref_pattern/:*}
    : "$(( ${#cachekey_format} + 1 ))"
    cache_ref_pattern="${cache_ref_pattern:$_}"
  } || {
    : "${cachekey_name}_format"
    cache_ref_format=${!_:-printf}
    : "${cachekey_name}_pattern"
    : "${!_:?"$(sys_exc cachekey-fetch-env "Pattern expected for \'$cachekey\'")"}"
    cache_ref_pattern=$_
    $LOG debug "$lk" "Found pattern" "$cachekey_name:$cache_ref_pattern"
  }
}

cachekey_format () # ~ ...
{
  cache_ref=$(strfmt_${cache_ref_format:?} "${cache_ref_pattern:?}" "${cachekey_inputs[@]:?}")
}

# cksums key format encrypts inputs and optionally cachekey id itself.
cachekey_from_cksums () # ~ <Key> <Inputs...>
{
  declare lk=${lk-}:cachekey-cksums
  declare salt=${cachekey_salt-} kalgo=${cachekey_algo:-sha1}

  if_ok "$(hash_str_py "$kalgo" "$salt${*:2}")" || return
  "${cachekey_idhash:-false}" "$_" && {
    if_ok "${cachekey_prefix-}$(hash_str_py "$kalgo" "$salt$1"):$_" || return
  } || {
    : "${cachekey_prefix-}$1:$_"
  }
  cache_name=$_
}

cachekey_from_plain () # ~ <Key-id> <Inputs...>
{
  # Concatenate key+inputs by ':'
  local oldIFS=$IFS;IFS=:
  cache_name=$(echo "${cachekey_prefix-}${*:?}")
  IFS=$oldIFS
}

cachekey_parse_arg () # ~ <Key> <Inputs...>
{
  [[ $# -ge 2 ]] || return ${_E_GAE:?}
  cachekey=${1:?} cachekey_name="${1//[:-]/_}"
  cachekey_inputs=( "${@:2}" )
  cachekey_from_${cachekey_format:-cksums} "$@"
}

cache_ref () # ~ <Key> <Inputs...> # Init cache reference
{
  cachekey_parse_arg "$@" &&
  cachekey_fetch_${cachekey_store:-env} &&
  cachekey_format
}

#
