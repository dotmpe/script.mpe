# Examples using instances of url and related api

lib_require web
lib_init web

do_echo ()
{
  local -n url urlid
  urlrefs_byurl "${_url:?}" url{id,} || return
  stderr echo "url<$urlid> := \"$url\""
}

do_inspect_byurl0 ()
{
  local -n url urlid
  urlrefs_byurl "${_url:?}" url{id,} || return
  stderr echo declare -n url=${!url}
  stderr echo declare -n urlid=${!urlid}
}

do_inspect_byurl ()
{
  local id
  id=${urlref_urlid["${_url:?}"]}
  stderr echo "url<${id}> := \"$_url\""
  # XXX: test url-abs $id" separately
  for g in scheme auth netpath{,-npv} name name-ext noquery path query fragment \
    resource{name,id}
  do
    if_ok ".$g: $(urlref_abs "${_url:?}" .$g)" && echo "$_" || echo no $g
  done
}

do_inspect_byurlid ()
{
  local -n url urlid
  urlrefs_byurl "${_url:?}" url{id,} || return
  stderr echo "url<$urlid> := \"$url\""
  for g in scheme auth netpath{,-npv} name name-ext noquery path query fragment \
    resource{name,id}
  do
    if_ok "$(url_abs "$urlid" .$g)" && echo ".$g: $_" || echo no $g
  done
}

# Is '//' useful or not?
urls=(
  "http://example.net/name"
  "https://dotmpe.com/path.d;param/name.f?query=value&keys#id"
  "https://user:pass@host:123/path;param/file?query=value&keys#id"
  "ns:/auth/path"
)
for _url in "${urls[@]}"
do
  urlrefs_assert "${_url:?}"
  do_echo
  #do_inspect_byurl0
  #do_inspect_byurlid
  #do_inspect1
  #do_inspect2
  echo
done
