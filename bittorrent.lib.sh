bittorrent_lib__load ()
{
  : "${BTCLIENTS:=transmission}"
  #test -z "${BTCLIENTS:-}" && return
  lib_require meta $BTCLIENTS || return

  : "${BT_INFODIR:=${METADIR:?}/info}"
  : "${BT_LOGDIR:=${METADIR:?}/log}"
  : "${BT_TABS:=${METADIR:?}/tab}"

  : "${BT_CACHEDIR:=${METADIR:?}/cache}"

  : "${BTLOG_PEERS:=$BT_LOGDIR/torrents-net.log}"

  : "${btjs_cachefp:=${BT_CACHEDIR:?}/bittorrent.lib.json-cache.sh}"

  local -gA btjs_cache
  [[ ! -s "${btjs_cachefp:?}" ]] ||
    . "${btjs_cachefp:?}" || return
}

bittorrent_lib__init ()
{
  lib_require cache || return
  test -z "${BTCLIENTS:-}" && return
  test -d "$BT_LOGDIR" || mkdir -vp "$BT_LOGDIR" >&2
  test -d "$BT_INFODIR" || mkdir -vp "$BT_INFODIR" >&2

  bittorrent_info_vars_static="{info_{length,name,pcs,priv},magnet_{dn,btih}}"
  set -- {info_{length,name,pcs,priv},magnet_{dn,btih}}
  bittorrent_info_vars=$_
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized bittorrent.lib" "$(sys_debug_tag)"
}

bittorrent_lib__install ()
{
  command -v pytp >/dev/null 2>&1 &&
  command -v jq >/dev/null 2>&1
}

# Read all simple values from torrent (currently 11 values, using files found
# in the wild).
# Other complex values: announce-list, info.files, and info.pieces.
bittorrent_info_vars () # ~ <Key>
{
  [[ $# -eq 11 ]] ||
    set -- ${1:-torrent_}{info_{length,name,pcs,priv,enc,comment,by,date},magnet_{dn,btih},announce}
  json_read_oneline '[
        .info.length // " ",
        .info.name // " ",
        .info["piece length"] // " ",
        .info.private // " ",
        .info.encoding // " ",
        .info.comment // " ",
        .info["created by"] // " ",
        .info["creation date"] // " ",
        .["magnet-info"]["display-name"] // " ",
        .["magnet-info"].info_hash // " ",
        .announce // " "
      ] | join("\t")' "$@"
}

bittorrent_instances () # ~ ...
{
  local btclient
  for btclient in $BTCLIENTS
  do
    "$btclient"_instances
  done
}

bittorrent_json () # ~ <Torrent-file> <JSON-file>
{
  pytp "${1:?}" >| "${2:?}"
}

# Cache JSON from torrent file. This uses cache.lib and can encode the cache
# key values using an external checksum/hash program but that does unreasonably
# increase run time.
bittorrent_json_cache () # ~ <Torrent-file> [<Var-key=bittorrent_json_>]
{
  [[ -s "${1:?}" ]] || return ${_E_no_file:-124}
  local $cache_lib_vars _btjs_stat
  [[ ! ${btjs_cache["${1:?}"]:+set} ]] && {
    cache_ref bittorrent-file "${1:?}" || return
    : "${2:-bittorrent_json_}"
    local -n cachef=${_}file \
        cacheref=${_}ref \
        cachename=${_}cachename &&
    cacheref=$cache_ref &&
    cachename=$cache_name &&
    cachef=${BT_CACHEDIR:?}/$cache_name.json
  } || {
    <<< "${btjs_cache["${1:?}"]:?}" read -r _ _ _ cachef
    : "${cachef##*/}"
    : "${_%.json}"
    cache_name=$_
  }

  [[ -s "$cachef" && "$cachef" -nt "$1" ]] &&
  $LOG debug "$lk" "Torrent meta JSON cache is up-to-date" "$1:$cache_name" ||
    {
      bittorrent_json "$1" "$cachef" &&
      $LOG debug "$lk" "Loading torrent meta into JSON cachefile" "$1:$cache_name" || _btjs_stat=$?
    }

  : "${_btjs_stat:--} $(date +'%s')"
  : "$_ $(filemtime "${1:?}")"
  : "$_ $cache_name"
  local new="${_@Q}"
  [[ ${btjs_cache["${1:?}"]:+set} &&
    "$new" == "${btjs_cache["${1:?}"]}"
  ]] ||
    >> "${btjs_cachefp:?}" echo "btjs_cache[\"${1:?}\"]=$new"

  [[ ! ${_btjs_stat:+set} ]] ||
    $LOG alert "$lk" "Loading torrent meta into JSON cachefile" "E$_btjs_stat:$1:$cache_name" $_btjs_stat
}

# FIXME: client-id is not properly tracked yet, but one instance works fine
bittorrent_list_run () # ~ <List-run-arg...> # Go over every open torrent
{
  test -z "${CLIENT_ID:-}" && {
    local btclient
    for btclient in $BTCLIENTS
    do
      "$btclient"_list_run "$@"
    done
  } || {
    lk=bittorrent:$CLIENT/${CLIENT_PID:-} \
    REMOTE=$CLIENT_ID "${CLIENT:?}"_list_run "$@"
  }
}

# Parse Magnet URI reference with btih key. Pure bash solution to decode, split
# and read values into variables. This captures the like-named field values as
# variables ``magnetref-{dn,btih,tr}`` where the last one is an indexed array.
bittorrent_magnet_parse () # ~ <Magnet-uriref> # Decode and set $magnetref_{dn,btih,tr}
{
  magnetref_dn=
  magnetref_btih=
  declare -ga magnetref_tr=()

  : "${1:?}"
  # Strip scheme:?
  : "${1:8}"
  # URL encoded spaces
  : "${_//+/ }"
  # Replace other URL encoded chars with something echo -e/printf understands
  : "${_//%/\\x}"

  magnetref_decoded="$_"
  local query_field
  while read -r query_field
  do
    case "$query_field" in
      ( "dn="* )
          magnetref_dn=${query_field:3}
        ;;
      ( "tr="* )
          magnetref_tr+=( ${query_field:3} )
        ;;
      ( "xt=urn:btih:"* )
          magnetref_btih=${query_field:12}
        ;;
      ( * ) echo "Unknown field: '$query_field'" >&2
        return 2 ;;
    esac
  done <<< "$(printf "${magnetref_decoded//&/\\n}")"
}

# Read initial parts from torrent file (the magnet info-hash and display-name)
# Uses pytp and jq to retrieve data.
bittorrent_magnet_read () # ~ <Torrent-file> # Read torrent-magnet parts: infohash and displayname
{
  tjs= mijs= btih= dn=
  bittorrent_read_json "${1:?}" tjs &&
  # Parse-out and keep magnet-info JSON since if info/parts etc present JSON
  # can be much larger than just magnet-info.
  mijs="$(<<< "$tjs" jq -r '.["magnet-info"]')" &&
  btih="$(<<< "$mijs" jq -r '.info_hash')" &&
  dn="$(<<< "$mijs" jq -r '.["display-name"]')"
}

# Use pytp to parse torrent file to JSON, and get pieces of data from it,
# TODO progressively parse json
# Return 12 if magnet info but no share metadata is present.
bittorrent_read () # ~ <Torrent-File> # Read .torrent magnet info and metadata if available
{
  in= length= parts=
  : "${1##*/}"
  tbn="${_}"
  bittorrent_magnet_read "$1" || return

  test "$btih" != null || {
    sys_debug quiet ||
      $LOG warn "torrent-read" "No BTIH in torrent file" "$tbn"
    return 11
  }

  test "$(<<< "$tjs" jq '.info' )" != "null" || {
    sys_debug quiet ||
      $LOG warn "torrent-read" "No metadata for BTIH" "$btih:$tbn"
    return 12
  }

  # Read torrent metadata: file or folder name
  in="$(<<< "$tjs" jq -r '.info.name' )"

  # If we find a length, we have a single-part torrent. Otherwise we have a
  # folder.
  length=$(<<< "$tjs" jq '.["info"].length' )
  test "${length:-null}" != "null" && parts= || {
    length=
    parts=$(<<< "$tjs" jq '.["info"].files | length' )
  }
}

bittorrent_read_json () # ~ <Torrent-file> <Result-ref>
{
  local -n __tjs=${2:-tjs} &&
  __tjs=$(pytp "${1:?}")
}

json_read_oneline () # ~ <Query> <Vars...>
{
  if_ok "$(jq -r "${1:?}")" &&
  IFS=$'\t\n' read -r ${*:2} <<< "$_" &&
  # NOTE: unfortenately Bash insist on reading non-zero values, so we do a bit
  # of cleaning.
  local var &&
  for var in ${*:2}
  do [[ "${!var}" != " " ]] || eval "$var="
  done
}
