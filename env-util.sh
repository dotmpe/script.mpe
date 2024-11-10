#!/bin/sh

# Quickly get at some env settings.
# Should be sourcing/grepping some compiled ~/.conf/etc/profile.d parts here
# but could also further and establish our own.

scriptenv_t460s ()
{
  echo export UCONF=/srv/conf-25-5
  echo export U_S=/srv/project-25-5/user-scripts
  echo export U_C=/srv/project-25-5/user-conf-dev
  echo export LOG=\$U_S/tools/sh/log.sh
}

scriptenv ()
{
  : "${hostname:=$(hostname -s)}"
  echo export hostname=$hostname
  scriptenv_$hostname
}

dbus () # ~ <Wm>
{
  </proc/${1:?}/environ tr \\0 \\n |
      grep -E '^DBUS_SESSION_BUS_ADDRESS=' | sed 's/^/export /'
}

cron ()
{
  scriptenv
  echo export v=4 # log level to error

  set -- i3
  wm_pid=$(ps -C ${1:?} -o pid:1=)
  #echo "export WM=$1"
  #echo "export WM_${1^^}_PID=$wm_pid"
  dbus $wm_pid
}


test $# -gt 0 || set -- u_s

test -n "${BUILD_ID:-}" || "$@"
