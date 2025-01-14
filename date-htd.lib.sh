#!/bin/sh

# TODO /etc/localtime

date_htd_lib__load()
{
  export TODAY=+%y%m%d0000

  # Age in seconds
  export _1MIN=60
  export _2MIN=120
  export _3MIN=180
  export _4MIN=240
  export _5MIN=300
  export _10MIN=600
  export _15MIN=900
  export _20MIN=1200
  export _30MIN=1800
  export _45MIN=2700

  export _1HOUR=3600
  export _3HOUR=10800
  export _6HOUR=64800

  export _1DAY=86400
  export _1WEEK=604800

  # Note: what are the proper lengths for month and year? It does not matter that
  # much if below is only used for fmtdate-relative.
  export _1MONTH=$(( 31 * $_1DAY ))
  export _1YEAR=$(( 365 * $_1DAY ))

  : "${DT_ISO_FULL:=%Y-%m-%dT%H:%M:%S%z}"
  export DT_ISO_FULL
}


date_htd_lib__init()
{
  test -z "${date_htd_lib_init-}" || return $_

  lib_require sys-htd os-htd str || return

  test -n "${gdate-}" || case "${OS_UNAME:?}" in
    Darwin ) gdate="gdate" ;;
    Linux ) gdate="date" ;;
    * ) $INIT_LOG "error" "" "OS_UNAME" "$OS_UNAME" 1 ;;
  esac

  TZ_OFF_1=$($gdate -d '1 Jan' +%z)
  TZ_OFF_7=$($gdate -d '1 Jul' +%z)
  TZ_OFF_NOW=$($gdate +%z)

  test \( $TZ_OFF_NOW -gt $TZ_OFF_1 -a $TZ_OFF_NOW -gt $TZ_OFF_7 \) &&
    IS_DST=1 || IS_DST=0

  export gdate
  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized date-htd.lib" "$(sys_debug_tag)"
}


# newer-than FILE SECONDS, filemtime must be greater-than Now - SECONDS
newer_than() # FILE SECONDS
{
  test -n "${1-}" || error "newer-than expected path" 1
  test -e "$1" || error "newer-than expected existing path" 1
  test -n "${2-}" || error "newer-than expected delta seconds argument" 1
  test -z "${3-}" || error "newer-than surplus arguments" 1
  #us_fail $_E_GAE --\
  #  std_argv eq 2 $# "Newer-than argc expected" --\
  #  assert_ n "${1-}" "Newer-than expected path" --\
  #  assert_ e "${1-}" "Newer-than expected existing path" --\
  #  assert_ n "${2-}" "Newer-than expected delta seconds argument" || return

  fnmatch "@*" "$2" || set -- "$1" "-$2"
  test $(date_epochsec "$2") -lt $(filemtime "$1")
}

newer_than_all () # (REFFILE|@TIMESTAMP) PATHS...
{
  local ref path fm
  fnmatch "@*" "$1" && ref="${1:1}" || { ref=$(filemtime "$1") || return; }
  shift
  for path in $@
  do
    #test -e "$path" || continue
    fm=$(filemtime "$path"); test ${fm:-0} -lt $ref
  done
}

# older-than FILE SECONDS, filemtime must be less-than Now - SECONDS
older_than ()
{
  test -n "${1-}" || error "older-than expected path" 1
  test -e "$1" || error "older-than expected existing path" 1
  test -n "${2-}" || error "older-than expected delta seconds argument" 1
  test -z "${3-}" || error "older-than surplus arguments" 1
  #us_fail $_E_GAE --\
  #  std_argv eq 2 $# "Older-than argc expected" --\
  #  assert_ n "${1-}" "Older-than expected path" --\
  #  assert_ e "${1-}" "Older-than expected existing path" --\
  #  assert_ n "${2-}" "Older-than expected delta seconds argument" || return

  fnmatch "@*" "$2" || set -- "$1" "-$2"
  test $(date_epochsec "$2") -gt $(filemtime "$1")
  #test $(( $(date +%s) - $2 )) -gt $(filemtime "$1")
}

date_ts()
{
  date +%s
}

date_epochsec () # File | -Delta-Seconds | @Timestamp | Time-Fmt
{
  test $# -eq 1 || return 64
  test -e "$1" && {
      filemtime "$1"
      return $?
    } || {

      fnmatch "-*" "$1" && {
        echo "$(date_ts) $1" | bc
        return $?
      }

      fnmatch "@*" "$1" && {
        echo "$1" | cut -c2-
        return $?
      } || {
        date_fmt "$1" "%s"
        return $?
      }
    }
  return 1
}

# See +U-c
# date_fmt() # Date-Ref Str-Time-Fmt


# Compare date, timestamp or mtime and return oldest as epochsec (ie. lowest val)
date_oldest() # ( FILE | DTSTR | @TS ) ( FILE | DTSTR | @TS )
{
  set -- "$(date_epochsec "$1")" "$(date_epochsec "$2")"
  test $1 -gt $2 && echo $2
  test $1 -lt $2 && echo $1
}

# Compare date, timestamp or mtime and return newest as epochsec (ie. highest val)
date_newest() # ( FILE | DTSTR | @TS ) ( FILE | DTSTR | @TS )
{
  set -- "$(date_epochsec "$1")" "$(date_epochsec "$2")"
  test $1 -lt $2 && echo $2
  test $1 -gt $2 && echo $1
}

# Given a timestamp, display a friendly human readable time-delta:
# X sec/min/hr/days/weeks/months/years ago. This is not very precise, as it
# only displays a single unit and no fractions. But it is sufficient for a lot
# of purposes. See fmtdate_relative_f
fmtdate_relative () # ~ [ Previous-Timestamp | ""] [Delta] [suffix=" ago"]
{
  #local spec=$1
  #shift
  # FIXME:
  #set -- "$(time_parse_seconds "$spec")" "$@"

  # Calculate delta based on now
  test -n "${2-}" || set -- "${1:?}" "$(( $(date +%s) - ${1:?} ))" "${@:3}"

  # Set default suffix
  test $# -gt 2 || set -- "${1-}" "$2" " ${datefmt_suffix:-"ago"}"

  if test $2 -gt $_1YEAR
  then

    if test $2 -lt $(( $_1YEAR + $_1YEAR ))
    then
      printf -- "one year$3"
    else
      printf -- "$(( $2 / $_1YEAR )) years$3"
    fi
  else

    if test $2 -gt $_1MONTH
    then

      if test $2 -lt $(( $_1MONTH + $_1MONTH ))
      then
        printf -- "a month$3"
      else
        printf -- "$(( $2 / $_1MONTH )) months$3"
      fi
    else

      if test $2 -gt $_1WEEK
      then

        if test $2 -lt $(( $_1WEEK + $_1WEEK ))
        then
          printf -- "a week$3"
        else
          printf -- "$(( $2 / $_1WEEK )) weeks$3"
        fi
      else

        if test $2 -gt $_1DAY
        then

          if test $2 -lt $(( $_1DAY + $_1DAY ))
          then
            printf -- "a day$3"
          else
            printf -- "$(( $2 / $_1DAY )) days$3"
          fi
        else

          if test $2 -gt $_1HOUR
          then

            if test $2 -lt $(( $_1HOUR + $_1HOUR ))
            then
              printf -- "an hour$3"
            else
              printf -- "$(( $2 / $_1HOUR )) hours$3"
            fi
          else

            if test $2 -gt $_1MIN
            then

              if test $2 -lt $(( $_1MIN + $_1MIN ))
              then
                printf -- "a minute$3"
              else
                printf -- "$(( $2 / $_1MIN )) minutes$3"
              fi
            else

              printf -- "$2 seconds$3"

            fi
          fi
        fi
      fi
    fi
  fi
}

# Turn spec with float into seconds (time-parse-seconds)
# and give human readable delta
fmtdate_relative_f () # ~ <Time-Spec>
{
  local ms=${1//*./}
  seconds_fmt_relative_f "$(time_parse_seconds "${1//.*/}").$ms"
}

# There has to be something more functional, but this works and requires only
# printf, Bash string-expansions and bc. And covers a reasonable range...
# from nanoseconds to years. But may want generic one to go from yocto to yotta
# describe what ranges to print, be verbose or terse and use abbr. etc.
# (ie. 10E-24 to 10E+24)
# XXX: want more resolution for fmtdate_relative.
# Also printing several orders together. But not a lot of customization.

seconds_fmt_relative_f () # ~ <Timestamp> <Delta>
{
  stderr echo "deprecated: seconds_fmt_relative_f: $(sys_caller)"
  fmttime_relative_f "$@"
}

fmttime_relative_f ()
{
  test -z "${1-}" && shift || {
    test -n "${2:-}" && shift ||
      set -- $(echo "scale=24; $(epoch_microtime) - $1"|bc) "$3"
    test "${1:0:1}" != "-" ||
      stderr_ "! $0: seconds-fmt-relative-f input ts was before epoch" $? || return
  }
  test -n "${1:-}" -a $# -le 2 || return 64
  test -n "${2:-}" || set -- "$1" ""
  test ${1:0:1} != "-" ||
    stderr_ "! $0: seconds-fmt-relative-f takes only positive delta values" $? || return

  test ${1//.*} -gt 0 && {
    # Seconds
    test ${1//.*} -gt 60 && {
      # Minutes / seconds
      test ${1//.*} -gt 3600 && {
        # Hours / minutes / seconds
        test ${1//.*} -gt 86400 && {
          # Days / hours / minutes / seconds
          test ${1//.*} -gt 604800 && {
            # Weeks / days / hours / minutes
            test ${1//.*} -gt 31536000 && {
              # Years / weeks / days / hours
              printf '%.0f years, %.0f weeks, %.0f days, %.0f hours%s' \
                "$(echo "$1 / 31536000"|bc)" \
                  "$(echo "$1 % 31536000 / 604800"|bc)" \
                    "$(echo "$1 % 31536000 % 604800 / 86400"|bc)" \
                      "$(echo "$1 % 31536000 % 604800 % 86400 / 3600"|bc)" "$2"
            } || {
              printf '%.0f weeks, %.0f days, %.0f hours, %.0f minutes%s' \
                "$(echo "$1 / 604800"|bc)" \
                  "$(echo "$1 % 604800 / 86400"|bc)" \
                    "$(echo "$1 % 604800 % 86400 / 3600"|bc)" \
                      "$(echo "$1 % 604800 % 86400 % 3600 / 60"|bc)" "$2"
            }
          } || {
            printf '%.0f days, %.0f hours, %.0f minute, %.0f seconds%s' \
              "$(echo "$1 / 86400"|bc)" \
                "$(echo "$1 % 86400 / 3600"|bc)" \
                  "$(echo "$1 % 86400 % 3600 / 60"|bc)" \
                    "$(echo "$1 % 86400 % 3600 % 60"|bc)" "$2"
          }
        } || {
          printf '%.0f hours, %.0f minutes, %.0f seconds%s' \
            "$(echo "$1 / 3600"|bc)" \
              "$(echo "$1 % 3600 / 60"|bc)" \
                "$(echo "$1 % 3600 % 60"|bc)" "$2"
        }
      } || {
        printf '%.0f minutes, %.0f seconds%s' \
          "$(echo "$1 / 60"|bc)" "$(echo "$1 % 60"|bc)" "$2"
      }
    } || {
      printf '%.3f seconds%s' "$1" "$2"
    }

  } || {
    # Miliseconds (1/1000th second, ie. 10-3)
    set -- "$(echo "$1 * 1000" | bc)" "$2"
    test ${1//.*} -gt 0 && {
      printf '%.3f miliseconds%s' "$1" "$2"
    } || {
      # Microseconds (1/1.000.000th second, ie. 10-6)
      set -- "$(echo "$1 * 1000" | bc)" "$2"
      test ${1//.*} -gt 0 && {
        printf '%.3f microseconds%s' "$1" "$2"
      } || {
        # Nanoseconds (1/1.000.000.000th second, ie. 10-9)
        set -- "$(echo "$1 * 1000" | bc)" "$2"
        test ${1//.*} -gt 0 && {
          printf '%.3f nanoseconds%s' "$1" "$2"
        } || {
          # Picoseconds (1/1.000.000.000.000th second, ie. 10-12)
          set -- "$(echo "$1 * 1000" | bc)" "$2"
          test ${1//.*} -gt 0 && {
            printf '%.3f picoseconds%s' "$1" "$2"
          } || {
            # Femtoseconds (1/1.000.000.000.000th second, ie. 10-15)
            set -- "$(echo "$1 * 1000" | bc)" "$2"
            test ${1//.*} -gt 0 && {
              printf '%.3f femtoseconds%s' "$1" "$2"
            } || {

              # XXX: may want to add terse and verbose format options
              #printf '<1fs%s' "$2"
              printf 'less than 1 femtosecond%s' "$2"
            }
          }
        }
      }
    }
  }
}

time_fmt_abbrev () # (stdin) ~
{
   sed ' s/,//g
          s/ nanoseconds\?/ns/
          s/ microseconds\?/us/
          s/ miliseconds\?/ms/
          s/ seconds\?/s/
          s/ minutes\?/m/
          s/ hours\?/h/
          s/ days\?/d/
          s/ weeks\?/w/
          s/ months\?/mo/
          s/ years\?/y/'
}

# Match abbreviated, human readable time notations
time_grep_abbrev () # (stdin) ~
{
  grep -qE '^([0-9]+(y|mo|w|d|h|m|s|ms|us|ns))+$'
}

# Return true and print seconds if spec matches time (duration) notation
time_parse_seconds () # ~ <Time-Spec>
{
  case "$1" in ( *":"* )
        set -- "$(echo "$1" | time_minsec_human_readable | tr -d ' ')" || return
      ;;
  esac
  echo "$1" | time_grep_abbrev && {
    echo "$1" | time_parse_human_readable_tag
    return $?
  }
  return 1
}

time_minsec_human_readable ()
{
  sed -E '
        s/([0-9]+):([0-9]+):([0-9]+):([0-9]+):([0-9]+)/\1y \2d \3h \4m \5s/
        s/([0-9]+):([0-9]+):([0-9]+):([0-9]+)/\1d \2h \3m \4s/
        s/([0-9]+):([0-9]+):([0-9]+)/\1h \2m \3s/
        s/([0-9]+):([0-9]+)/\1m \2s/
        s/\<0+([dhmoswy])?//g
    '
}

time_parse_human_readable ()
{
  echo "$1" | time_parse_human_readable_tag
  #| sed 's/[0-9]*[0-9][dhmoswy]/& /g'
}

time_parse_human_readable_tag ()
{
  tr -d ' ' | sed -E 's/[0-9]+[dhmoswy]/&\n/g' | awk '
            BEGIN { s=0 }
            /[0-9]+y/  { gsub(/y$/,"",$0);  s += int( $0 ) * '"$_1YEAR"'  }
            /[0-9]+mo/ { gsub(/mo$/,"",$0); s += int( $0 ) * '"$_1MONTH"' }
            /[0-9]+w/  { gsub(/w$/,"",$0);  s += int( $0 ) * '"$_1WEEK"'  }
            /[0-9]+d/  { gsub(/d$/,"",$0);  s += int( $0 ) * '"$_1DAY"'   }
            /[0-9]+h/  { gsub(/h$/,"",$0);  s += int( $0 ) * '"$_1HOUR"'  }
            /[0-9]+m/  { gsub(/m$/,"",$0);  s += int( $0 ) * '"$_1MIN"'   }
            /[0-9]+s/  { gsub(/s$/,"",$0);  s += int( $0 )                }
            END { print s }
        '
}

# Output date at required resolution
date_autores () # ~ <Date-Time-Spec>
{
  fnmatch "@*" "$1" && {
    true ${dateres:="minutes"}
    set -- "$(date_iso "${1:1}" minutes)"
  }
  echo "$1" | sed \
      -e 's/T00:00:00//' \
      -e 's/T00:00//' \
      -e 's/:00$//'
}

# Tag: seconds, minutes, hours, days, years
ts_rel() # Seconds-Delta [Tag]
{
  test -n "$2" || set -- "$1" hours
  case "$2" in
      seconds ) dt=$1 ; dt_rest=0;;
      minutes ) dt=$(( $1 / $_1MIN ))  ; dt_rest=$(( $1 % $_1MIN ));;
      hours )   dt=$(( $1 / $_1HOUR )) ; dt_rest=$(( $1 % $_1HOUR ));;
      days )    dt=$(( $1 / $_1DAY ))  ; dt_rest=$(( $1 % $_1DAY ));;
      weeks )   dt=$(( $1 / $_1WEEK )) ; dt_rest=$(( $1 % $_1WEEK ));;
      years )   dt=$(( $1 / $_1YEAR )) ; dt_rest=$(( $1 % $_1YEAR ));;
  esac
}

ts_rel_multi() # Seconds-Delta [Tag [Tag...]]
{
  local dt= dt_maj= dt_rest= dt_min=
  ts_rel "$@" ; dt_maj="$dt" ; shift 2
  while test $# -gt 0
  do
      ts_rel "$dt_rest" "$1" ; shift
      test ${#dt} -gt 1 || dt=0$dt
      dt_min="$dt_min:$dt"
  done
  dt_rel="$dt_maj$dt_min"
}

# Get stat datetime format, given file or datetime-string. Prepend @ for timestamps.
timestamp2touch() # [ FILE | DTSTR ]
{
  test -n "${1-}" || set -- "@$(date_ts)"
  test -e "$1" && {
    ${gdate:?} -r "$1" +"%y%m%d%H%M.%S"
    return
  } || {
    ${gdate:?} -d "$1" +"%y%m%d%H%M.%S"
  }
}

# Copy mtime from file or set to DATESTR or @TIMESTAMP
touch_ts () # ~ ( DATESTR | TIMESTAMP | FILE ) FILE
{
  test -n "$2" || set -- "$1" "$1"
  touch -t "$(timestamp2touch "$1")" "$2"
}

date_iso() # Ts [date|hours|minutes|seconds|ns]
{
  test -n "${2-}" || set -- "${1-}" date
  test -n "$1" && {
    $gdate -d @$1 --iso-8601=$2 || return $?
  } || {
    $gdate --iso-8601=$2 || return $?
  }
}

# NOTE: BSD date -v style TAG-values are used, translated to GNU date -d
date_fmt_darwin() # TAGS DTFMT
{
  test -n "$1" && tags=$(printf -- '-v %s ' $1) || tags=
  date $date_flags $tags +"$2"
}

# Allow some abbrev. from BSD/Darwin date util with GNU date
bsd_date_tag ()
{
  $gsed \
     -e 's/[0-9][0-9]*s\b/&ec/g' \
     -e 's/[0-9][0-9]*M\b/&in/g' \
     -e 's/[0-9][0-9]*[Hh]\b/&our/g' \
     -e 's/[0-9][0-9]*d\b/&ay/g' \
     -e 's/[0-9][0-9]*w\b/&eek/g' \
     -e 's/[0-9][0-9]*m\b/&onth/g' \
     -e 's/[0-9][0-9]*y\b/&ear/g' \
     -e 's/\<7d\>/1week/g'
}

# Format path for date, default pattern: "$1/%Y/%m/%d.ext" for dirs, or
# "$dirname/%Y/%m/%d/$name.ext" for fiels
archive_path() # Y= M= D= . Dir [Date]
{
  test -d "$1" &&
    ARCHIVE_DIR="$1" || {
      NAME="$(basename "$1" $EXT)"
      ARCHIVE_DIR="$(dirname "$1")"
    }
  shift
  fnmatch "*/" "$ARCHIVE_DIR" && ARCHIVE_DIR="$(strip_trail "$ARCHIVE_DIR")"

  test -z "$1" || now=$1
  test -n "$Y" || Y=/%Y
  test -n "$M" || M=/%m
  test -n "$D" || D=/%d

  test -z "$NAME" || NAME=-$NAME
  export archive_path_fmt=$ARCHIVE_DIR$Y$M$D$NAME$EXT
  test -z "$now" &&
      export archive_path=$($gdate "+$archive_path_fmt") ||
      export archive_path=$(date_fmt "$now" "$archive_path_fmt")
}

datelink() # Date Format Target-Path
{
  test -z "$1" && datep=$(date "+$2") || datep=$(date_fmt "$1" "$2")
  target_path=$3
  test -d "$(dirname $3)" || error "Dir $(dirname $3) must exist" 1
  test -L $target_path && {
    test "$(readlink $target_path)" = "$(basename $datep)" && {
        return
    }
    printf "Deleting "
    rm -v $target_path
  }
  mkrlink $datep $target_path
}

# Print ISO-8601 datetime with minutes precision
datet_isomin () { date_iso "${1-}" minutes; }

# Print ISO-8601 datetime with nanosecond precision
datet_isons() { date_iso "$1" ns; }

# Print fractional seconds since Unix epoch
epoch_microtime () # [Date-Ref=now]
{
  $gdate +"%s.%N"
}

date_microtime ()
{
  $gdate +"%Y-%m-%d %H:%M:%S.%N"
}

sec_nomicro ()
{
  fnmatch "*.*" "$1" && {
      echo "$1" | cut -d'.' -f1
  } || echo "$1"
}

# Parse time to seconds
time_get () # ~ <Time-Spec>
{
  local a1 ts; a1="$1"; shift
  case "$a1" in

      ( "@"* ) ts="${a1:1:}" ;;
      ( "[0-9][0-9][0-9][0-9][0-9]*[0-9]" ) ts=@${a1:1:} ;;

      ( *":"* ) ts=$(timespec_parse "$a1") ;;
      ( "" ) ts=$(timespec_parse "$a1") ;;
      ( * )
          ;;
  esac
}

# Parse time to timestamp.
# Any number with more than 5 digits is used as timestamp.
time_get () # ~ <Time-Spec>
{
  local a1 ts; a1="$1"; shift
  case "$a1" in

      ( "@"* ) ts="${a1:1:}" ;;
      ( "[0-9][0-9][0-9][0-9][0-9]*[0-9]" ) ts=@${a1:1:} ;;

      ( *":"* ) ts=$(timespec_parse "$a1") ;;
  esac
  test $# -gt 0 || set -- +'%s'
  date -d @$ts "$@"
}

# Parse datetime spec to std repr.
# Any number with more than 5 digits is used as timestamp.
date_parse() # ~ <Date-Spec>
{
  test -n "${2-}" || set -- "$1" "%s"
  fnmatch "[0-9][0-9][0-9][0-9][0-9]*[0-9]" "$1" && {
    $gdate -d "@$1" +"$2"
    return $?
  } || {
    $gdate -d "$1" +"$2"
    return $?
  }
}

# Make ISO-8601 for given date or ts and remove all non-numeric chars except '-'
date_id () # <Datetime-Str>
{
  s= p= act=date_autores foreach_${foreach-"do"} "$@" | tr -d ':-' | tr 'T' '-'
}

# Parse compressed datetime spec (Y-M-DTHMs.ms+TZ) to ISO format
date_idp () # <Date-Id>
{
  foreach_item "$@" | $gsed -E \
      -e 's/^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})/\1-\2-\3T\4:\5:\6/' \
      -e 's/^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})/\1-\2-\3T\4:\5/' \
      -e 's/^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})/\1-\2-\3T\4/' \
      -e 's/^([0-9]{4})([0-9]{2})([0-9]{2})/\1-\2-\3/' \
      -e 's/T([0-9]{2})([0-9]{2})([0-9]{2})$/T\1:\2:\3/' \
      -e 's/T([0-9]{2})([0-9]{2})/T\1:\2/' \
      -e 's/(-[0-9]{2}-[0-9]{2})([+-][0-9:]{2,5})$/\1T00\2/'
}

# Take compressed date-tstat format and parse to ISO-8601 again, local time
date_pstat ()
{
  test "$1" = "-" && echo "$1" || date_parse "$(date_idp "$1")"
}

# Time for function executions
time_fun()
{
  local ret=
  time_exec_start=$(gdate +"%s.%N")
  "$@" || ret=$?
  time_exec=$({ gdate +"%s.%N" | tr -d '\n' ; echo " - $time_exec_start"; } | bc)
  note "Executing '$*' took $time_exec seconds"
  return $ret
}

# Get first and last day of given week: monday and sunday (ISO)
date_week() # Week Year [Date-Fmt]
{
  test $# -ge 2 -a $# -le 3 || return 2
  test $# -eq 3 || set -- "$@" "+%Y-%m-%d"
  local week=$1 year=$2 date_fmt="$3"
  local week_num_of_Jan_4 week_day_of_Jan_4
  local first_Mon

  # decimal number, range 01 to 53
  week_num_of_Jan_4=$(date -d $year-01-04 +%V | sed 's/^0*//')
  # range 1 to 7, Monday being 1
  week_day_of_Jan_4=$(date -d $year-01-04 +%u)

  # now get the Monday for week 01
  if test $week_day_of_Jan_4 -le 4
  then
    first_Mon=$year-01-$((1 + 4 - week_day_of_Jan_4))
  else
    first_Mon=$((year - 1))-12-$((1 + 31 + 4 - week_day_of_Jan_4))
  fi

  mon=$(date -d "$first_Mon +$((week - 1)) week" "$date_fmt")
  sun=$(date -d "$first_Mon +$((week - 1)) week + 6 day" "$date_fmt")
}

#
