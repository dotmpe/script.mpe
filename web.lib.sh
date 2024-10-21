
web_lib__load ()
{
  #lib_require str:fnmatch

  # Match Ref-in-Angle-brachets or URL-Ref-Scheme-Path
  url_re='\(<[_a-zA-Z][_a-zA-Z0-9-]\+:[^> ]\+>\|\(\ \|^\)[_a-zA-Z][_a-zA-Z0-9-]\+:\/\/[^ ]\+\)'
  url_bare_re='[_a-zA-Z][_a-zA-Z0-9-]\+:\/[^>\ ]\+'
  test -x "$(which curl)" && bin_http=curl || {
    test -x "$(which wget)" && bin_http=wget || return
  }
}

web_lib__init ()
{
  declare -gA urlref_urlid
  declare -ga urlref_id
}


ext_to_format () # XXX
{
  echo "$1"
}

htd_urls_encode()
{
  p= s= act=urlencode foreach_do "$@"
}

htd_urls_decode()
{
  p= s= act=urldecode foreach_do "$@"
}

# Download urls
htd_urls_get() # (-|URL)...
{
  htd_urls_get_inner()
  {
    test -n "$fn" || fn="$(basename "$1")"
    test -e "$fn" || {
      wget -q "$1" -O "$fn" && {
        test -e "$fn" && note "New file $fn"
      } || {
        error "Retrieving file $fn"
      }
    }
  }

  p= s= act=htd_urls_get_inner foreach_do "$@"
}

# Scan for URL's, reformat if not enclosed in angles <>. Set second arg to
# rewrite file in place, give extension to make file backup.
htd_urls_todotxt() # File [1|ext]
{
  test -z "$2" && gsed_f= || { test "$2" = "1" && gsed_f=-i || gsed_f=-i$2 ; }
  $gsed $gsed_f 's/\(^\|\ \)\('"$url_bare_re"'\)/\1<\2>/g' "$1"
}

# List URLs in text file, and add to urlstat table. This matches both
# bare-URI references and angle bracked anclosed (<Ref>). See htd-urls-list
htd_urls_urlstat() # Text-File [Init-Tags]
{
  setup_io_paths -$subcmd-${htd_session_id}
  export ${htd_inputs?} ${htd_outputs?}
  opt_args "$@"
  htd_optsv $(lines_to_words $options)
  set -- $(lines_to_words $arguments)

  lib_load urlstat || return
  urlstat_file="$1" ; shift
  urlstat_check_update=$update
  urlstat_update_process=$process
  htd_urls_list "$urlstat_file" | Init_Tags="$*" urlstat_checkall
  rm "$failed"
}

html_entities_unicode ()
{
  sed -f "${US_BIN:-$HOME/bin}/htmlentities.sed" "$@"
}

http_deref () # ~ <URL> [<Last-Modified>] [<ETag>] [<Curl-argv>]
{
  declare lk=${lk:-}:http-deref
  local -r url=${1:?} lm=${2-} etag=${3-}

  test -z "$lm" || {
    test -z "$etag" || {
      ! fnmatch "*/*" "$lm" &&
      ! fnmatch "*/*" "$etag" || {
        http_deref_cache_etagfile "$lm" "$etag" "$url" "${@:4}"
        return
      }
    }
    ! fnmatch "*/*" "$lm" &&
    set -- "${@:1:3}" -H "If-Modified-Since: $lm" "${@:4}" || {
      http_deref_cache "$lm" "$url" "${@:4}"
      return
    }
  }

  test -z "$etag" || set -- "${@:1:3}" -H "If-None-Match: ${etag:?}" "${@:4}"

  : "$(printf " '%s'" "${url:?}" "${@:4}")"
  $LOG notice "$lk" "Contacting web" "curl ${curl_f:--sfL}$_"

  curl ${curl_f:--sfL} "${url:?}" "${@:4}"
}

http_deref_cache_etagfile () # ~ <Cache-file> <Etag-file> <URL-ref> [<Curl-argv>]
{
  test -e "${2:?}" && set -- "$@" --etag-compare "${2:?}"
  http_deref_cache "${1:?}" "${@:3}" --etag-save "${2:?}"
}

http_deref_cache () # ~ <Cache-file> <URL-ref> [<Curl-argv...>]
{
  test -e "${1:?}" && set -- "$@" -z "${1:?}"
  http_deref "${2:?}" "" "" "${@:3}" -o "${1:?}"
  #&& {
  #  test -s "${etagf:?}" ||
  #  rm "$_"
  #}
}


json_list_has_objects()
{
  jsotk -sq path $out '0' --is-obj || return
  # XXX: jq -e '.0' $out >>/dev/null || break
}


# XXX: just sketching up some ideas for types below [4324] see url{,ref}_abs

# NOTE: Initial type for absolute URL references (parts getter) [4324]
url_abs () # ~ <URLID> <Part-switch> ...
{
  local -n __url_abs_url{,id}
  local self urlrefs_copy=false
  urlrefs_byid "${1:?}" __url_abs_url{id,} &&
  [[ ${__url_abs_urlid:?} = "${1:?}" ]] ||
    $LOG error :url-abs "Retrieving URL instance" E$?:$1 $? || return
  self="url_abs $__url_abs_urlid "

  case "${2:-.global}" in
  ( .authority | .auth ) # Authority (without / or // prefix)
      if_ok "$($self.netpath-npv)" &&
      test -n "${_%%/*}" &&
      echo "${_}" ;;
  ( .resourceid ) # XXX:
      : "${__url_abs_url:?URL}"
      test "$_" = "${_//*\/}" ||
      echo "$_" ;;
  ( .resourcename ) # XXX:
      if_ok "$($self.global)" || return
      test "$_" = "${_//*\/}" ||
      echo "$_" ;;
  ( .filename-extension | .name-ext  )
      if_ok "$($self.filename)" || return
      test "$_" = "${_##*.}" ||
      echo "$_" ;;
  ( .filename | .name  )
      if_ok "$($self.noquery)" || return
      test "$_" = "${_##*\/}" ||
      echo "$_" ;;
  ( .fragment ) # Only local fragment id part
      : "${__url_abs_url:?URL}"
      test "${_}" = "${_/*\#}" ||
      echo "${_}" ;;
  ( .global ) # XXX: Entire URL without local fragment
      : "${__url_abs_url:?URL}"
      test -n "${_/\#*}" &&
      echo "${_}" ;;
  ( .noquery ) # XXX: Global without fragment or query
      : "$($self.global)"
      test -n "${_/\?*}" &&
      echo "${_}" ;;
  ( .netpath ) # Only user and host or domain info + path (excluding query and scheme)
      # This retains '//' or '/' prefix. Depending on the scheme and context,
      # '/' could mean the path is absolute and may be netpath is even
      # actually '//localhost/' but such are invalid URLs in the first place.
      # Ie. file:/// is not a standardized URL but a local cludge to GTD, and
      # '//' doesnt actually signify much but its the scheme+protocol that does.
      if_ok "$($self.noquery)" &&
      test -n "${_#*:\/}" &&
      echo "/${_}" ;;
  ( .netpath-npv ) # Like netpath, but check and remove '/' or '//' prefix.
      # Ie. Regard first path element as authority part, dont prefix it.
      local nq
      nq="$($self.noquery)" || return
      test "${nq}" != "${nq#*:\//}" &&
      echo "${_}" || {
        test "${nq}" != "${nq#*:\/}" &&
        echo "${_}"
      } ;;
  ( .path ) # netpath-npv without authority.
      if_ok "$($self.netpath-npv)" &&
      test -n "${_#*\/}" &&
      echo "/${_}" ;;
  ( .scheme ) #
      : "${__url_abs_url:?URL}"
      test -n "${_//:\/*}" &&
      echo "${_}" ;;
  ( .query ) # Only the query part (exluding '?' separator) from global
      : "$($self.global)"
      test "${_}" = "${_/*\?}" ||
      echo "${_}" ;;

  ( * ) $LOG error ":url-abs" "No such part" "$2" 127
  esac
}

urlbase () # ~ <URL>
{
  : "${1:?"$(sys_exc urlbase:urlref)"}"
}

urldecode () # ~ <String>
{
  : "${1:?}"
  # URL encoded spaces
  : "${_//+/ }"
  # Replace other URL encoded chars with something echo -e/printf understands
  printf "${_//%/\\x}\n"
}

urldecode_py () # ~ <String>
{
  python -c "import urllib; print(urllib.unquote_plus(\"$1\"));"
}

urlencode () # ~ <String>
{
  "${ue_plusq:-true}" && set -- "${1// /+}"

  local old_lc_collate=$LC_COLLATE
  LC_COLLATE=C

  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:$i:1}"
    case $c in
      ( [a-zA-Z0-9.~_+-] ) printf '%s' "$c" ;;
      ( * ) printf '%%%02X' "'$c" ;;
    esac
  done

  LC_COLLATE=$old_lc_collate
}

urlencode_py () # ~ <String>
{
  python -c "import urllib; print(urllib.quote_plus(\"$1\"));"
}

urllink () # ~ <Rel> <Rev> <URL>
{
  false
}

# TODO: resolve given string to urlref instance.
urlref () # ~ [<Home-url>] <Reference> [<Part-switch>]
{
  false
}

# XXX: initial (static) helper to deal with URL parts.
# this is written to fail unless exact part is present (nz) and then printed.
urlref_abs () # ~ <URL> [<Part-switch>] ...
{
  local -n __urlref_abs_url{,id}
  local urlrefs_copy=false
  urlrefs "${1:?}" __urlref_abs_url{id,} &&
  [[ ${__urlref_abs_url:?} = "${1:?}" ]] ||
    $LOG error :urlref-abs "Retrieving URL instance" E$?:$1 $? || return

  url_abs "${__urlref_abs_urlid:?}" "${2:-.global}"
}

urlref_rel () # ~ <Home-url> <Relative-part>
{
  false
}

# Return unique instance Id for given reference (no normalization whatsoever,
# just dynamic, literal shell Id for web Id mapping). Default is to use by-name
# references to actual lookup arays, use urlrefs-copy or -value to get a value.
urlrefs () # ~ <URL> [idrefvar] [urlrefvar]
{
  urlrefs_assert "$1" &&
  urlrefs_byurl "$@"
}

urlrefs_assert () # ~ <URL> # Store new id map if none found yet
{
  local __urlref_url=${1:?}
  [[ ${urlref_urlid["${__urlref_url}"]+set} ]] || {
    local newid=$RANDOM
    while [[ ${urlref_id[newid]+set} ]]
    do
      newid=$RANDOM
    done
    urlref_urlid["${__urlref_url}"]=$newid
    urlref_id[$newid]=${__urlref_url}
  }
}

# Get ref or copy by ID index, without other lookup.
urlrefs_byid () # ~ <URLID> [idname] [urlname]
{
  ! "${urlrefs_copy:-false}" && {
    local -n __urlref_url="urlref_id[\"${1:?}\"]"
    eval ${2:-URLID}="urlref_urlid[\"$__urlref_url\"]" &&
    eval ${3:-URL}="urlref_id[\"${1:?}\"]" || return
  } || {
    local -n __urlref_id=${2:-URLID} __urlref_url=${3:-URL}
    __urlref_id=${1:?}
    __urlref_url=${urlref_id["$__urlref_id"]}
  }
}

# Get ref or copy by looking up URL and build ref back using ID index.
urlrefs_byurl () # ~ <URL> [idname] [urlname]
{
  local __urlref_url=${1:?} &&
  ! "${urlrefs_copy:-false}" && {
    local -n __urlref_id=${2:-URLID}
    eval ${2:-URLID}="urlref_urlid[\"$__urlref_url\"]" &&
    eval ${3:-URL}="urlref_id[\"$__urlref_id\"]" || return
  } || {
    local -n __urlref_id=${2:-URLID} __urlref=${3:-URL} || return
    __urlref_id=${urlref_urlid["$__urlref_url"]}
    __urlref=${__urlref_url}
  }
}

urlrefs_value () # ~ <URL> [<idvar] [urlvar]
{
  urlrefs_copy=true urlrefs "$@"
}

urls_clean_meta ()
{
  tr -d ' {}()<>"'"'"
}

urls_grep () # [SRC|-]
{
  grep -io "$url_re" "$@" | tr -d '<>"''"' # Remove angle brackets or double quotes
}

# Scan for URLs in file. This scans both <>-enclosed and bare URL refs. To
# avoid match on simple <q>:<name> pairs the std regex requires (net)path,
# or use <>-delimiters.
urls_list () # <Path>
{
  test $# -eq 1 || return 98
  urls_grep "$1"
  #| while read -r url
  #do
  #  fnmatch "*:*" "$url" && {
  #    echo "$url"
  #  } || {
  #    #test -n "$fn" || fn="$(basename "$url")"
  #    test -e "$url" || warn "No file '$url'"
  #  }
  #done
}

urls_list_clean ()
{
  test $# -eq 1 || return 98
  local format=$(ext_to_format "$(filenamext "$1")")
  func_exists urls_clean_$format || format=meta
  urls_list "$1" | urls_clean_$format
}


# Shortcut to do HTTP HEAD request (or do similar query for given URL, to get a
# listing of protocol headers or comparable metadata).
web_about () # ~ <URL> [<Output=->]
{
  : "${1:?web-about: URL parameter expected}"
  test "${2:--}" = "-" && {
    curl -I "$1" || return
  } ||
    curl -I "$1" >| "${2:?}"
}

web_deref__libs=cache,ck
web_deref () # ~ <URL> [<Alias>]
{
  local -r url=${1:?} urlkey urlalias=${2-}
  TODO
}

web_fetch() # URL [Output=-]
{
  test $# -ge 1 -a $# -le 2 || return
  test $# -eq 2 || set -- "$1" -

  case "$bin_http" in
    curl ) curl -sSf "$1" -o $2 ;;
    wget ) wget -q "$1" -O $2 ;;
  esac
}

web_html2text () # ~ <URL> [<elinks-extra-args...>]
{
  set -- -dump 1 \
	 -dump-width ${html_width:-${COLUMNS:-${COLS:-79}}} \
	 -dump-charset ${html_charset:-ascii} "$@"
	# NOTE: these settings are a bit confusing. ATM seems elinks doesnt put index
	# beneath non-ref dumps, and always cross-refs by num.
  "${html_refnums:-true}" && {
    set -- -eval 'set document.dump.references = 1' "$@"
    "${html_refindex:-true}" &&
      set -- -eval 'set document.dump.numbering = 1' "$@" ||
      set -- -no-numbering "$@"
  } ||
    set -- -no-references "$@"
  elinks "$@"
}

web_instances ()
{
  # XXX: track clients, see bittorrent/transmission
  std_pass "$(pidof -s $bin_http)" || return
  echo "web default $_ $bin_http"
}

web_resolve_paged_json() # URL Num-Query Page-query
{
  test -n "$1" -a "$2" -a "$3" || return 100
  local tmpd=/tmp/json page= page_size=
  mkdir -p $tmpd
  page_size=$(eval echo \$$2)
  page=$(eval echo \$$3)
  case "$1" in
    *'?'* ) ;;
    * ) set -- "$1?" "$2" "$3" ;;
  esac

  test -n "$page" || page=1
  while true
  do
    note "Requesting '$1$2=$page_size&$3=$page'..."
    out=$tmpd/page-$page.json
    curl -sSf "$1$2=$page_size&$3=$page" > $out
    json_list_has_objects "$out" || { rm "$out" ; break; }
    std_info "Fetched $page <$out>"
    page=$(( $page + 1 ))
  done

  note "Finished downloading"
  test -e "$tmpd/page-1.json" || error "Initial page expected" 1
  count="$( echo $tmpd/page-*.json | count_words )"
  test "$count" = "1" && {
    cat $tmpd/page-1.json
  } || {
    jsotk merge --pretty - $tmpd/page-*.json
  }
  rm -rf $tmpd/
}

#
