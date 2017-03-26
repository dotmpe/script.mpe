#!/bin/sh

set -e


# Insert into file using `ed`. Accepts literal content as argument.
# file-insert-at 1:file-name[:line-number] 2:content
# file-insert-at 1:file-name 2:line-number 3:content
file_insert_at_spc=" ( FILE:LINE | ( FILE LINE ) ) INSERT "
file_insert_at()
{
  test -x "$(which ed)" || error "'ed' required" 1

  test -n "$*" || error "arguments required" 1

  local file_name= line_number=
  fnmatch *:[0-9]* "$1" && {
    file_name=$(echo $1 | cut -f 1 -d :)
    line_number=$(echo $1 | cut -f 2 -d :)
    shift 1
  } || {
    file_name=$1; shift 1
    line_number=$1; shift 1
  }

  test -e "$file_name" || error "no file $file_name" 1
  test -n "$1" || error "content expected" 1
  test -n "$*" || error "nothing to insert" 1

  # use ed-script to insert second file into first at line
  note "Inserting at $file_name:$line_number"
  echo "${line_number}a
$1
.
w" | ed $file_name
# XXX: $tmpf
}

# Replace entire line using Sed
file_replace_at_spc=" ( FILE:LINE | ( FILE LINE ) ) INSERT "
# file-replace-at 1:file-name[:line-number] 2:content
# file-replace-at 1:file-name 2:line-number 3:content
file_replace_at()
{
  test -n "$*" || error "arguments required" 1
  test -z "$4" || error "too many arguments" 1

  local file_name= line_number=

  fnmatch *:[0-9]* "$1" && {
    file_name=$(echo $1 | cut -f 1 -d :)
    line_number=$(echo $1 | cut -f 2 -d :)
    shift 1
  } || {
    file_name=$1; shift 1
    line_number=$1; shift 1
  }

  test -e "$file_name" || error "no file $file_name" 1
  test -n "$line_number" || error "no line_number" 1
  test -n "$1" || error "nothing to insert" 1

  sed $line_number's/.*/'$1'/' $file_name
}

# 1:where-grep 2:file-path
file_where_grep()
{
  test -n "$1" || error "where-grep arg required" 1
  test -e "$2" -o "$2" = "-" || error "file-path or input arg required" 1
  #test -e "$2" || set -- "$1"
  where_line=$(grep -n "$@")
  line_number=$(echo "$where_line" | sed 's/^\([0-9]*\):\(.*\)$/\1/')
  test -n "$2" || echo $line_number
}

file_where_before()
{
  file_where_grep "$@"
  line_number=$(( $line_number - 1 ))
}

# 1:where-grep 2:file-path 3:content
file_insert_where_before()
{
  local where_line= line_number=
  test -e "$2" || error "no file $2" 1
  test -n "$3" || error "contents required" 1
  file_where_before "$1" "$2"
  test -n "$where_line" || {
    error "missing or invalid file-insert sentinel for where-grep:$1 (in $2)" 1
  }
  file_insert_at $2:$line_number "$3"
}

# Truncate whole, trailing or middle lines of file.
# file-truncate-lines 1:file [2:start_line=0 [3:end_line=]]
file_truncate_lines()
{
  test -f "$1" || error "file-truncate-lines FILE '$1'" 1
  test -n "$2" && {
    cp $1 $1.tmp
    test -n "$3" && {
      {
        head -n $2 $1.tmp
        tail -n +$(( $3 + 1 )) $1.tmp
      } > $1
    } || {
      head -n $2 $1.tmp > $1
    }
    rm $1.tmp
  } || {
    printf -- "" > $1
  }
}

# Remove leading lines, so that total lines matches LINES
# TODO: rename to truncate-leading-lines
truncate_trailing_lines()
{
  test -n "$1" || error "truncate-trailing-lines FILE expected" 1
  test -n "$2" || error "truncate-trailing-lines LINES expected" 1
  test $2 -gt 0 || error "truncate-trailing-lines LINES > 0 expected" 1
  local lines=$(line_count "$1")
  test $lines > $2 || {
    error "File contains less than $2 lines"
    return
  }
  cp $1 $1.tmp
  tail -n $2 $1.tmp
  head -n +$(( $lines - $2 )) $1.tmp > $1
  rm $1.tmp
}

# find '<func>()' line and see if its preceeded by a comment. Return comment text.
func_comment()
{
  test -n "$1" || error "function name expected" 1
  test -n "$2" -a -e "$2" || error "file expected: '$2'" 1
  test -z "$3" || error "surplus arguments: '$3'" 1
  # find function line number, or return 0
  grep_line="$(grep -n "^$1()" "$2" | cut -d ':' -f 1)"
  case "$grep_line" in [0-9]* ) ;; * ) return 0;; esac
  lines=$(echo "$grep_line" | count_words)
  test $lines -gt 1 && {
    error "Multiple lines for function '$1'"
    return 1
  }
  # get line before function line
  func_leading_line="$(head -n +$(( $grep_line - 1 )) "$2" | tail -n 1)"
  # return if exact line is a comment
  echo "$func_leading_line" | grep -q '^\s*#\ ' && {
    echo "$func_leading_line" | sed 's/^\s*#\ //'
  } || noop
}

header_comment()
{
  read_file_lines_while "$1" 'echo "$line" | grep -qE "^\s*#.*$"' || return $?
  export last_comment_line=$line_number
}

# Echo exact contents of the #-commented file header, or return 1
# backup-header-comment file [suffix-or-abs-path]
backup_header_comment()
{
  test -n "$2" || set -- "$1" ".header"
  fnmatch "/*" "$2" \
    && backup_file="$2" \
    || backup_file="$1$2"
  # find last line of header, add output to backup
  header_comment "$1" > "$backup_file" || return $?
}

list_functions()
{
  test -n "$1" || set -- $0
  for file in $*
  do
    test_out list_functions_head
    trueish "$list_functions_scriptname" && {
      grep '^[A-Za-z0-9_\/-]*()$' $file | sed "s#^#$file: #"
    } ||
      grep '^[A-Za-z0-9_\/-]*()$' $file
    test_out list_functions_tail
  done
}

source_lines()
{
  test -f "$1"
  test -n "$2" && start_line=$2 || start_line=0
  test -z "$3" || end_line=$3
  test -z "$4" || span_lines=$4
  test -n "$end_line" || end_line=$(count_lines $1)
  test -n "$span_lines" || span_lines=$(( $end_line - $start_line ))
  note "Source-lines: $start_line-$end_line ($span_lines lines)"
  tail -n +$start_line $1 | head -n $span_lines
}

expand_source_line()
{
  test -f "$1" || error "expand_source_line file '$1'" 1
  test -n "$2" || error "expand_source_line line" 1
  srcfile="$(source_lines "$1" "$2" "" 1 | awk '{print $2}')"
  test -f "$srcfile" || error "src-file $*: '$srcfile'" 1
  file_truncate_lines "$1" "$(( $2 - 1 ))" "$(( $2 ))"
  file_insert_at $1:$(( $2 - 1 )) "$(cat $srcfile )"
  note "Replaced line with resolved src of '$srcfile'"
}

function_linenumber() {
  test -n "$1" -a -e "$2" || error "function-linenumber FUNC FILE" 1
  file_where_grep "^$1()\(\ {\)\?$" "$2"
}

function_linerange()
{
  test -n "$1" -a -e "$2" || error "function-linerange FUNC FILE" 1
  function_linenumber "$@"
  start_line=$line_number
  span_lines=$(
      tail -n +$start_line "$2" | grep -n '^}' | head -n 1 | sed 's/^\([0-9]*\):\(.*\)$/\1/'
    )
  end_line=$(( $start_line + $span_lines ))
}

insert_function()
{
  test -n "$1" -a -e "$2" -a -n "$3" || error "insert-function FUNC FILE FCODE" 1
  file_insert_at $2 "$(cat <<-EOF
$1()
{
$3
}

EOF
  ) "
}

cut_function()
{
  test -n "$1" -a -f "$2" || error "cut-function FUNC FILE" 1
  function_linerange "$@"
  test -n "$span_lines" || span_lines=$(( $end_line - $start_line ))
  note "cut-func $2 $start_line $end_line ($span_lines)"
  tail -n +$start_line $2 | head -n $span_lines
  file_truncate_lines "$2" "$(( $start_line - 1 ))" "$(( $end_line - 1 ))"
}

setup_temp_src()
{
  test -n "$UCONFDIR" || error "metaf UCONFDIR" 1
  setup_tmpf "$@" "$UCONFDIR/temp-src"
}

# Isolate function into separate, temporary file. But keep source-script
# working.
copy_paste_function()
{
  test -n "$1" -a -f "$2" || return
  test -n "$cp_board" || cp_board="$(get_uuid)"
  cp=$(setup_temp_src .copy-paste $cp_board)
  function_linenumber "$@"
  at_line=$(( $line_number - 1 ))
  cut_function $1 $2 > $cp
  file_insert_at $2:$at_line "$(cat <<-EOF
. $cp
EOF
  ) "
}

