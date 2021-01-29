#!/usr/bin/env bash

ctx_statusdir_lib_load ()
{
  : "${ctx_class_types:="${ctx_class_types-}${ctx_class_types+" "}Statusdir"}"
}
ctx_statusdir_depends=@Shell

ctx_statusdir_lib_init ()
{
  lib_require date &&
  class.Statusdir.init
}

at_Statusdir__init ()
{
  true "${INIT_LOG:="$LOG"}" && lib_init statusdir ctx-statusdir
}

# XXX: at_Statusdir__include=statusdir.lib.sh

# Store result of command in statusdir
at_Statusdir__report_var () # Format [Record-Type [Record-Name]] [@Tags...] -- Command...
{
  local format type name tags c index log_key=$scriptname:report-var@Statusdir/$$
  ctx_shell_report_var_args "$@" || return
  test -z "${c-}" || shift $c
  test -n "${sd_be:-}" || local sd_be=fsdir

  sd_be=fsdir statusdir_start
  # fsd_rtype=$type sd_be=fsdir statusdir_start "$name"
  log_key=$log_key $LOG "info" "" "Started SD for" "$type:$name"

  echo name=$name >&2
  return

  # sd load: set variables for entry in backend
  local outfile
  outfile="$(fsd_rtype=$type sd_be=fsdir statusdir_run load $name -- $type)"
  test -n "$outfile" ||
      error "Expected output file for <$type $name>" 1

  local ttl ttlvar
  ttl=$( func_exists=0 first_only=1 context_cmd_seq time_period seconds -- $tags )
  test -n "$ttl" || {
    ttlvar=${name}_ttl
    ttl=${!ttlvar-"$STATUSDIR_EXPIRY_AGE"}
  }

  # Update or create file if needed
  test -e "$outfile" ||
      log_key=$log_key $LOG warn "" "No such file" "$outfile"

  local statvar=${name}_ret
  { test -s "${outfile}" &&
      newer_than $outfile $ttl &&
      test ${!statvar-0} -eq 0
  } || {
    eval "$@" >> ${outfile}
  }
    #fsd_rtype=$type sd_be=fsdir statusdir_run exec "$name" -- "$@" \;

  # Echo as requested
  case "$format" in
      summary ) echo "$type:$(basename "${outfile}"):$(count_lines $outfile)" ;;
      count ) count_lines $outfile ;;
      index | log ) cat $outfile ;;
      names ) echo "$type:$(basename "${outfile}")" ;;
      paths ) echo "${outfile}" ;;

      * ) echo "@Shell:report-var:format:${format}?" >&2; return 1
          ;;
  esac
}

class.Statusdir.init ()
{
  declare -g -A Statusdir__params=()
  declare -g -A Statusdir__backends=()
  declare -g -A Statusdir__backend_types=()
}

class.Statusdir () # Instance-Id Message-Name Arguments...
{
  test $# -gt 0 || return
  test $# -gt 1 || set -- $1 .default
  local self="class.Statusdir $1 " id=$1 m=$2
  shift 2

  case "$m" in
    .Statusdir )
        test $# -gt 0 || set -- fsdir
        $self.set_backend "$@"
      ;;

    .set_backend )
        local backend=$1 && lib_require statusdir-$backend && shift &&
        set -- $($self.get_backend_type "$backend") "$@" &&
        create "Statusdir__backends[$id]" "$@"
      ;;

    .get_backend )
        echo ${Statusdir__backends[$id]}
      ;;

    .get_backend_type )
        echo "Statusdir.${Statusdir__backend_types[${1,,}]}"
      ;;

    .default | \
    .info )
        echo "class.Statusdir <#$id> $($self.be.info)"
      ;;

    .be.* | \
    .* )
        fnmatch ".be.*" "$m" && m=${m:3}
        ${Statusdir__backends[$id]}$m "$@"
      ;;

    * )
        $LOG error "" "No such endpoint '$m' on" "$($self.info)" 1
      ;;
  esac
}

#