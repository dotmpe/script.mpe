#!/usr/bin/env bash

ctx_urls_lib_load()
{
  to_trees_base=$HOME/Downloads
  to_trees_spec=tree-exported-*.tree

  ls -la $to_trees_base/$to_trees_spec
  to_trees to_read_tree

  to_chrome_ext_id=eggkanocgddhmamlbiijnphhppkpkmkl

  # https://groups.google.com/forum/#!topic/tabs-outliner-support-group/eKubL9Iw230
  #tree "/Users/berend/Library//Application Support/Google/Chrome/Default/Sync Extension Settings/$chrome_ext_instance"
  #tree ~/Library/Application\ Support/Google/Chrome/Default/Extensions/$chrome_ext_instance/1.4.134_0/backup
  #ls -la "/Users/berend/Library//Application Support/Google/Chrome/Default/Extensions/$chrome_ext_instance/1.4.134_0"

  case "$uname" in
      darwin ) to_leveldb="$HOME/Library/Application Support/Google/Chrome/Default/IndexedDB/chrome-extension_${chrome_ext_id}_0.indexeddb.leveldb" ;;
      linux ) to_leveldb=$HOME/.config/google-chrome/Default/IndexedDB/chrome-extension_${chrome_ext_id}_0.indexeddb.leveldb ;;
  esac
  #run $bin leveldb stream "$to_leveldb"
}

ctx_urls_lib_init()
{
  lib_require match-htd todotxt || return
  trueish "$global" && {
    urlstab=$(statusdir.sh root index urlstat.list)
  } || {
    urlstab=$(statusdir.sh index urlstat.list)
  }
}

@URLs.list()
{
  test $# -gt 0 || set -- $CTX
  test -n "${1-}" || return
  at_URLs__list "$@" | {
    test -t 1 && {
      vimpager --force-passthrough -c "set ft=todo" || true
    } || cat -
  }
}

at_URLs__list()
{
  todotxt_tagged "$urlstab" "$@"
}

at_URLs__rules_sh() # ~ Dest-Cmd Tags
{
  true
}

# Tab-outliner

to_trees()
{
  for x in $to_trees_base/$to_trees_spec
  do
    $1 $x
  done
}

to_read_tree()
{
  date="$( basename $1 .tree | cut -d '-' -f 3- | tr '-' ' ')"
  echo "$date <$(htd prefix name "$1")>"
  jsotk json2yaml "$1"
  echo
}

#
