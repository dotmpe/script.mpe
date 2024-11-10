#!/usr/bin/env bash

ctags-debug ()
{
  [[ $# -gt 0 ]] || {
    [[ -s .tags ]] && set -- .tags || {
      [[ -s tags ]] && set -- tags
    }
  }
  [[ -s "${1:?}" ]] ||
    $LOG error : "Empty or missing tags file" "$*" 127 || return
  du -hs "${1:?}" &&
  wc "${1:?}" &&
  if_ok "$(ctags-scanned-file-count "$1")" &&
  stderr echo "Files scanned: $_"
}

alias ctags-scanned-file-count="awk '{
  if (!a[\$2]++) b+=1
} END { print b; } '"
# This can print all the unique files scanned by ctags, useful for debugging
alias ctags-scanned-files="awk '{
  if (!a[\$2]++) print \$2
} '"

#
