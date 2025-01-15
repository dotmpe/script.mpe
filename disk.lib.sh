#!/bin/sh

## disk device query routines


disk_lib__load ()
{
  : "${OS_UNAME:=$(uname -s)}"
  : "${username:=$(whoami)}"
  #test -n "${username-}" || username="$(whoami | tr -dc 'A-Za-z0-9_-')"
  #test -n "${hostname-}" || hostname="$(hostname -s)"
  : "${hostname:=$(hostname -s | tr '[:upper:]' '[:lower:]')}"

  : "${DISK_CATALOG:=$HOME/.local/diskdoc}"

  : "${USER_DEVS:=${UCONF:?}/user/devices.list}"
  : "${USER_SDUSB:=${UCONF:?}/user/sdusbtab}"
  #DD_DISKDEVS=
  #DD_DISKVIRTDEVS=
  # XXX: may need additional list for partition devices?
  : "${USER_DISKDEVS:=sd fd sr mmc md mdp blkext}"
  : "${USER_VDISKDEVS:=loop ramdisk device-mapper}"

  disk_catalog_sources=lsblk\ parted\ fdisk
  disk_catalog_spec=\
'model	Model description	1	lsblk,parted
vendor	Vendor description	1	lsblk
product	Product description	0
label	Short disk description	1
tags	Tag list	0
prefix	Id for mount paths	1
description	Disk description	0
id	Identifier for diskdoc/catalog	1
serial	Serial Id	1	lsblk
rev	Revision	0	lsblk
size	Disk size	1	lsblk
byte-size	Disk size	1	lsblk
ver	Version	0'

  disk_lsblk_keys=KNAME\ TRAN\ RM\ SIZE\ VENDOR\ MODEL\ REV\ SERIAL\ UUID\ PTTYPE\ STATE
  disk_lsblk_keys_ext=KNAME\ TRAN\ RM\ RA\ RO\ ROTA\ HOTPLUG\ SCHED\ HCTL\ SIZE\ VENDOR\ MODEL\ REV\ SERIAL\ UUID\ WWN\ PTTYPE\ STATE

  disk_partition_lsblk_keys=KNAME\ PARTTYPE\ PARTLABEL\ PARTUUID\ MOUNTPOINT\ FSTYPE\ PTUUID\ PTTYPE\ UUID\ SIZE\ LABEL

  disk_keys_req="id index prefix vendor model serial size byte-size"
  disk_keys=id\ index\ description\ host\ domain\
\ prefix\ vendor\ model\ revision\ serial\ size\ byte-size

#\ volumes__
#  0\ disk_volumes__1\ disk_volumes__2\
#\ disk_volumes__4\ disk_volumes__5\ disk_volumes__6

  disk_keys_map=\
'disk_model MODEL
disk_size SIZE
disk_byte_size BSIZE
disk_vendor VENDOR
disk_revision REV
disk_ptuuid	PTUUID
disk_index DISK_NR
disk_transport TRAN
disk_serial SERIAL'

  disk_partition_keys=disk_partition_type\ volume_uuid\ volume_partuuid\
\ volume_prefix\ volume_partition_index

  disk_partition_keys_map=\
'volume_uuid UUID
volume_partuuid PARTUUID
disk_partition_type PTTYPE
volume_parttype PARTTYPE'

  disk_prefix_defaults='{VENDOR}-{MODEL}-{disk_index}-{disk_size}'
  disk_volume_defaults='{disk_prefix}-{part_index}-{part_size}'
}

disk_lib__init ()
{
  test -z "${disk_lib_init-}" || return $_
  req_init_log || return

  test -d "$DISK_CATALOG" || mkdir -p $DISK_CATALOG
  mkdir -p $DISK_CATALOG/disk
  mkdir -p $DISK_CATALOG/volume

  mnt_pref="sudo " dev_pref=
  case "$(groups)" in
    *" disk "* ) ;;
    * )
      $log warn "" "No disk access, using sudo to read disk device info"
      # FIXME warn "No disk access, using sudo to read disk device info"
      dev_pref="sudo" ;;
  esac

  ! sys_debug -dev -debug -init ||
    $LOG notice "" "Initialized disk.lib" "$(sys_debug_tag)"
}


req_fdisk()
{
  #test -n "${fdisk-}" -a -x "$($dev_pref which fdisk)" || {
  #  error "$1: missing fdisk" 1
  #}
  fdisk="$dev_pref $($dev_pref which fdisk)"
}

req_parted()
{
  #test -n "${parted-}" -a -x "$($dev_pref which parted)" || {
  #  error "$1: missing parted" 1
  #}
  parted="$dev_pref $($dev_pref which parted)"
}

req_blkid()
{
  #test -n "${blkid-}" -a -x "$($dev_pref which blkid)" || {
  #  error "$1: missing blkid" 1
  #}
  blkid="$dev_pref $($dev_pref which blkid)"
}


disk_bootnumber () # # @DEV
{
  note "TODO: Getting disk0 boot count-crash count..."
  eval local $(disk_smartctl_attrs $1)
  test -z "${Power_Cycle_Count-}" ||
      echo "$Power_Cycle_Count-$Power_Cycle_Count_Raw"
  test -z "${Power_Off_Retract_Count-}" ||
      echo "$Power_Off_Retract_Count-$Power_Off_Retract_Count_Raw"
}

disk_device_numbers () # () ~
{
  disk_devices_filter "$@" | cut -d' ' -f1
}

disk_devices_filter () # ~ ( <Include-devnames...> | ! <Exclude-devnames...> )
{
  local g_o=${grep_opts:-}
  test $# -eq 0 || {
    test "$1" != "!" || { g_o=${g_o}v; shift; }
  }
  test $# -gt 0 || {
    case "$g_o" in
      ( *v* ) set -- $USER_VDISKDEVS ;;
      ( * ) set -- $USER_DISKDEVS ;; esac
  }

  #shellcheck disable=2048
  set -- " $(grep_or_exact $*)$"
  disk_devices_numbers | grep ${g_o:+-}${g_o-} "$1"
}

# Get Kernels major number and driver for block type devices
# from /proc/devices
disk_devices_numbers () # ~ # List major number and driver for block devices
{
  local IFS=$'\n' blockdevs
  for line in $(cat /proc/devices)
  do
    test ${blockdevs:-0} -eq 1 && {
      test "$line" = "" && break;
      IFS=$' \t\n' # Restore IFS to remove spaces on echo
      echo $line
    }
    test "$line" = "Block devices:" || continue
    blockdevs=1
  done
}

disk_fdisk_id () # ~ <Disk-dev>
{
  test $# -gt 0 -a -b "${1:?}" || return ${_E_GAE:-3}
  case "${OS_UNAME:?}" in

      Linux )
            { # List partition table
              ${fdisk:?} -l $1 || {
                error "disk-fdisk-id at '$1'"
                return $?
              }
            } | grep Disk.identifier | sed 's/^Disk.identifier: //'
          ;;

      Darwin )
            # Dump partition table
              ${fdisk:?} -d $1 || return $?
          ;;

    * ) error "Disk-fdisk-Id: ${OS_UNAME:?}" 1 ;;
  esac
}

disk_id () # ~ <Device>  # XXX: Prints serial-id
{
  disk_serial_id "$@"
  #disk_fdisk_id "$@" # XXX: Old
}

disk_id_for_dev ()
{
  test -b "${1:?}" || return $_E_GAE
  local disk_id="$(disk_id "$1")" || error "disk-id: '$1'" 1
  test -z "$disk_id" && error "No disk Id for device '$1'" 1
  std_info "Using Disk-ID '$disk_id' for '$1'"
  echo "$disk_id"
}

disk_ignore_numbers () # ~ <Exclude-devnames...>
{
  disk_devices_filter $USER_VDISKDEVS | cut -d' ' -f1
}

disk_info ()
{
  test $# -gt 2 || return $_E_GAE
  local disk_dev=${1:?} act="${2:-names}"; shift 2
  while test $# -gt 0
  do case "$act" in

    ( names )
      ;;

      num ) disk_catalog_field "$disk_dev" disk_index || echo -1 ;;
      dev ) printf -- "$disk_dev " ;;
      disk_id ) disk_id "$disk_dev" ;;
      disk_model ) disk_model $disk_dev | tr ' ' '-';;
      size ) disk_size $disk_dev || return $?;;
      table_type ) disk_tabletype $disk_dev || return $?;;
      mnt_c ) disk_mountpoint $disk_dev | count_words ;;
    ( * ) error "inner $1?" 1 ;;
  esac || return && shift
  done
}

# Use lsblk to list properties for attached devices (without subnode trees)
disk_lsblk_field () # ~ <Device> <Field-spec>
{
  test -b "${1:?}" -a $# -eq 2  || return $_E_GAE
  local lsblk_opts="${lsblk_opts:-dn}"
  lsblk -o "${2:-PATH}" ${lsblk_opts:+-}${lsblk_opts:-} "$1"
}

disk_lsblk_list () # ~ [<lsblk-argv...>]
{
  local lsblk_opts="${lsblk_opts:-dn}" diskdev_vnums excluded_devs
  diskdev_vnums=$(disk_ignore_numbers)
  excluded_devs=$(echo $diskdev_vnums | tr ' ' ',')
  lsblk -o "PATH" -e$excluded_devs ${lsblk_opts:+-}${lsblk_opts:-} "$@"
}

# Load into env properties from lsblk for disk devices
disk_lsblk_load () # ~ <Disk-dev> <Columns...>
{
  test $# -gt 0 -a -b "${1:?}" || return ${_E_GAE:-3}
  local dev=$1 ; shift
  test $# -gt 0 || set -- $disk_lsblk_keys
  disk_lsblk_type_load "$dev" disk "$@"
}

disk_lsblk_partnr () # ~ <Device>
{
  test -b "${1:?}" || return $_E_GAE
  disk_lsblk_field "$1" MAJ:MIN | cut -d':' -f2
}

# Print properties from lsblk for disk devices
disk_lsblk_show () # ~ <Disk-dev> <Columns...>
{
  dry_run=1 disk_lsblk_load "$@"
}

disk_model () # ~ <Device>
{
  test -b "${1:?}" || return $_E_GAE
  case "${OS_UNAME:?}" in

    Linux ) req_parted disk-model || return

        req_parted disk-model || return
        {
          $parted -s $1 print 2>/dev/null || {
            error "disk-model at '$1'"
            return $?
          }
        } | grep Model: | sed 's/^Model: //'
      ;;

    Darwin )
        # FIXME: this only works with one disk, would need to parse XML plist
        system_profiler SPSerialATADataType | grep -qv disk1 || {
          error "Parse SPSerialATADataType plist" 1
        }
        echo $(system_profiler SPSerialATADataType | head -n 15  | grep Model \
          | cut -d ':' -f 2)
      ;;

    * ) error "Disk-Model: ${OS_UNAME:?}" 1 ;;
  esac
}

# List disks with mountpoint and type
disk_mounts() # [TYPES]
{
  test $# -gt 0 || set -- vfat ntfs ext2 ext3 ext4
  case "${OS_UNAME:?}" in

    Darwin | Linux )
        mount | {
          test $# -eq 0 && {
            grep '\ on\ ' || return
          } ||
            grep '\ on\ .*\ type\ \('"$(printf "%s\|" "$@")"'nosuchtype\)'
        } | cut -d' ' -f1,3,5
      ;;

    * ) error "Disk-Mounts not supported on: ${OS_UNAME:?}" 1 ;;
  esac
}

# XXX: should rewrite this to pipeline pieces
# List (local) disks (indicated major-type block devices from /dev, mounted or not)
disk_list_by_nr () # [List-Partitions] [Major-Types]
{
  local partitions=${1:-0}
  test $# -gt 0 && shift
  test $# -gt 0 || set -- $(disk_device_numbers)

  local dev numbrs
  eval 'disk_list_filter ()
  {
    case "$1" in
      '"$(  test $partitions -ge 1 &&
                printf '%i:[1-9]* ) true ;; ' $@
            test $partitions -eq 0 -o $partitions -eq 2 &&
                printf '%i:0 ) true ;; ' $@ )"'
        * ) false ;;
    esac
  }'

  for dev in /dev/*
  do
    test -b "$dev" || continue
    numbrs=$(mountpoint -x "$dev")
    disk_list_filter "$numbrs" || continue
    case "${out_fmt:-fields}" in

      fields ) echo "$dev $numbrs" | tr ':' ' ' ;;
      devs ) echo "$dev" ;;
    esac
  done
}

# List (local) disks (from /dev, mounted or not) using glob expansion
# XXX: this need knowledge of underlying adapters
# however its main property should be that it lists locally attached disks only
# also this does not handle patterns in minor and will miss actual disks
disk_list ()
{
  case "${OS_UNAME:?}" in [a-z]* ) uname=${uname^} ;; esac

  case "${OS_UNAME:?}" in

    Linux )
        test $# -gt 0 || set -- "sd*[a-z]"
        glob=/dev/$1
        fnmatch "*{*" "$1" && {
          test "$(eval "echo $glob")" = "$glob" || {
            eval "echo $glob" | tr ' ' '\n'
          }
        } || {
          test "$(echo $glob)" = "$glob" || {
            echo $glob | tr ' ' '\n'
          }
        }
      ;;

    Darwin )
        test $# -gt 0 || set -- 'disk[0-9]*'
        echo /dev/$1 |
            tr ' ' '\n' |
            grep -v '[0-9]s[0-9]*$'
      ;;

    * ) error "Disk-List: ${OS_UNAME:?}" 1 ;;
  esac
}

# List all local disk partitions using glob expansion
disk_list_part_local () # ~ # List partition devices
{
  local glob=
  test $# -gt 0 -a -n "${1-}" || error "Device or disk-id required" 1
  test $# -eq 1 || return 64
  case "${OS_UNAME:?}" in
    Linux )
        test -z "$1" && glob=/dev/sd*[a-z]*[0-9] \
          || glob=$1[0-9]
      ;;
    Darwin )
        # FIXME: deal with system_profiler plist datatypes
        # This only uses first disk to avoid complexity
        test -z "$1" && glob=/dev/disk0s*[0-9] \
          || glob=$1[0-9]
      ;;
    * ) error "Disk-List-Part-Local: ${OS_UNAME:?}" 1 ;;
  esac

  test "$(echo $glob)" = "$glob" || {
    echo $glob | tr ' ' '\n'
  }
}

disk_partition_type () # (dev) ~ [<Device>]
{
  req_blkid disk-partition-type || return
  test -z "$1" || local dev=$1
  $blkid -o value -s TYPE $dev || return $?
  # Or parse sudo file -Ls $dev
}

disk_partition_usage () # ~ <Device>
{
  dftabline=$(df -P $1 | tail -1);
  echo $(echo $dftabline | cut -f5 -d\  | sed -e 's/\%//g')
}

disk_partition_size () # ~ <Device>
{
  dftabline=$(df -hP $1 | tail -1);
  echo $(echo $dftabline | cut -f2 -d\  | sed -e 's/\%//g')
}

disk_serial_id ()
{
  test -b "${1:?}" || return $_E_GAE
  case "${OS_UNAME:?}" in

    Linux )
        udevadm info --query=all --name=$1 | grep ID_SERIAL_SHORT \
          | cut -d '=' -f 2
      ;;

    Darwin )
        local bsd_name=$(basename $1) xml=
        #diskutil info "$1" | grep 'UUID' >&2 || warn "No grep $dev"

        xml=$(darwin_profile_xml "SPSerialATADataType")
        device_serial="$(Darwin.py spserialata-disk $xml $bsd_name device_serial)" || true
        test -z "$device_serial" || {
          debug "SPSerialATADataType $bsd_name device serial '$device_serial'"
          echo $device_serial; return
        }

        xml=$(darwin_profile_xml "SPUSBDataType")
        serial_num="$(Darwin.py spusb-disk $xml $bsd_name serial_num)" || true
        test -z "$serial_num" || {
          debug "SPUSBDataType $bsd_name serial number '$serial_num'"
          echo $serial_num; return
        }

        xml=$(darwin_profile_xml "SPStorageDataType")
        serial_num="$(Darwin.py spstorage-disk $xml $bsd_name serial_num)" || true
        test -z "$serial_num" || {
          debug "SPStorageDataType $bsd_name serial number '$serial_num'"
          echo $serial_num; return
        }

        # Unfortunately need to dig trough volume group/mapping setup here.
        # Rather going to skip device ID and move to volumes directly.

        error "unkown disk $bsd_name" 1
      ;;

    * ) error "Disk-fdisk-Id: ${OS_UNAME:?}" 1 ;;
  esac
}

# TODO: Get mount point for dev/disk-id
# Get mount point for device path
disk_mountpoint ()
{
  test $# -gt 0 -a -n "${1-}" || error "Device or disk-id required" 1
  test $# -eq 1 || return 64
  {
    # NOTE: docker adds a mount for the same device already mounted, first line ..
    mount | grep '^'$1 | sed 's/\ on\ \(.*\)\ type\ .*$/ \1/'
  } || return $?
}

# Get device for mount point
get_device()
{
  test $# -eq 1 -a -n "${1-}" || stderr_ "Mount point argument expected" 1
  mountpoint -q "$1" || error "Mount point expected" 1
  {
    mount | grep 'on\ '"$1"' ' | cut -d ' ' -f 1
  } || return $?
}

disk_copy_fs ()
{
  test -n "$1" || error "Device or disk-id required" 1
  test -n "$2" || error "Filename required" 1
  test -n "$3" || set -- "$1" "$2" "/tmp"
  test -z "$4" || error "surplus arguments '$4'" 1

  mount_tmp $1 || set -- "$@" 11
  test -e $tmp_mnt/$2 $3 || set -- "$@" 12
  cp $tmp_mnt/$2 $3 || set -- "$@" 13
  umount $tmp_mnt || set -- "$@" 14
  rm -rf $tmp_mnt
  unset tmp_mnt

  test -n "$4" || set -- "$@" 0
  return $4
}

disk_find_mountpoint() # PATH
{
	local p="$1"
	while test "$p" != "/"
	do
		mountpoint -q "$p" && break
		p="$(dirname "$p")"
	done
	echo "$p"
}

disk_doc ()
{
  { cat <<EOM
host: $hostname

EOM
  } | jsotk yaml2json -
}

disk_report()
{
  # leave disk_report_result to "highest" set value (where 1 is highest)
  disk_report_result=0

  while test $# -gt 0
  do
    case "$1" in

      unknown )     test $unknown_count -eq 0     || stderr warn "            Unkown: ${bdefault}$unknown_count${grey}  ($unknown_abbrev)" ;;
      uncataloged ) test $uncataloged_count -eq 0 || stderr warn "       Uncataloged: ${bdefault}$uncataloged_count${grey}  ($uncataloged_abbrev)" ;;

      ext )         test $ext_count -eq 0         || stderr info "         Extended tables: ${bdefault}$ext_count${grey}  ($ext_abbrev)" ;;
      swap )        test $swap_count -eq 0        || stderr info "                    Swap: ${bdefault}$swap_count${grey}  ($swap_abbrev)" ;;
      volume )      test $volume_count -eq 0      || stderr note "                 ${grn}Volumes: ${bdefault}$volume_count${grey}  ($volume_abbrev)" ;;
      disk )        test $disk_count -eq 0        || stderr note "             Disks total: ${bdefault}$disk_count${grey}  ($disk_abbrev)" ;;

      list )        test $list_count -eq 0        || stderr note "           Entries total: ${bdefault}$list_count${grey}"

        ;;

      * )
          error "Unknown disk report '$1'" 1
        ;;

    esac
    shift
  done

  return $disk_report_result
}

# Getting disk0 runtime (days)
disk_runtime () # DEV
{
  local Power_On_Hours_Raw
  if_ok "$(disk_smartctl_attrs "${1:?}")" &&
  eval local $_ &&
  [[ ${Power_On_Hours_Raw:+set} ]] &&
  #python -c "print $Power_On_Hours_Raw / 24.0"
  echo "$Power_On_Hours_Raw hours" &&
  echo "$(echo "$Power_On_Hours_Raw / 24" | bc) days"
  #echo "$Power_On_Hours"
}

disk_smartctl_attrs ()
{
  ${smartctl_pref:-} smartctl -A "${1:?Device path required}" -f old | tail -n +8 | {
    local IFS=$' \t\n'
    while \
      read id attr flag value worst thresh type updated when_failed raw_value
    do
        [[ ${attr:+set} ]] || continue
        printf "%s " "$(printf "$attr" | tr -cs 'A-Za-z_' '_')_Raw=${raw_value@Q}"
        printf "%s " "$(printf "$attr" | tr -cs 'A-Za-z_' '_')=${value@Q}"
    done
  }
}

# Load into env or print on dry-run properties from lsblk output line
disk_lsblk_type_load () # ~ <Device> <Type> <Columns...>
{
  test -b "${1:?}" -a $# -ge 2  || return $_E_GAE
  local dev=$1 type=${2:?} data; shift 2
  # Looks like PTUUID is set to PTUUID of first partition. PARTUUID is empty.
  local lsblk_opts=${lsblk_opts:-d}
  data="$( lsblk \
       ${lsblk_opts:+-}${lsblk_opts:-} -P -o TYPE,$(echo $* | tr ' ' ',') $dev \
         | grep -m 1 '^TYPE="'"$type"'"'
       )" || return
  trueish "${dry_run-}" && {
      echo "$data"
      return
  } || eval "$data"
}

disk_partition_list () # ~ <Disk-dev>
{
  lsblk_opts=n disk_lsblk_field "$1" PATH,TYPE | grep ' part' | cut -d' ' -f1
}

# Load into env properties from lsblk for partition devices
disk_partition_lsblk_load () # ~ <Part-dev> <Columns...>
{
  test $# -gt 0 -a -b "${1:?}" || return ${_E_GAE:-3}
  local dev=$1 ; shift
  test $# -gt 0 || set -- $disk_partition_lsblk_keys
  disk_lsblk_type_load "$dev" part "$@"
}

# Read partition UUIDs (given disk dev or part dev) without sudo
disk_partition_uuids ()
{
  local uuid dev
  for uuid in /dev/disk/by-uuid/*
  do dev="$(realpath "$uuid")"
    case "$dev" in "$1"* ) basename $uuid
    esac
  done
}

disk_size () # ~ <Disk-dev>
{
  test $# -gt 0 -a -b "${1:?}" || return ${_E_GAE:-3}
  case "${OS_UNAME:?}" in

    Linux ) req_parted disk-size || return
        req_parted disk-size || return
        {
          $parted -s $1 print || {
            error "disk-size at '$1'"
            return $?
          }
        } | grep Disk.*: | sed 's/^Disk[^:]*: //'
      ;;

    Darwin )
        echo $(system_profiler SPSerialATADataType | head -n 15 | grep Capacity \
          | cut -d ':' -f 2 | cut -d ' ' -f 2 )GB
      ;;

    * ) error "Disk-Size: ${OS_UNAME:?}" 1 ;;
  esac
}

disk_tabletype () # ~ <Disk-dev>
{
  test $# -gt 0 -a -b "${1:?}" || return ${_E_GAE:-3}
  case "${OS_UNAME:?}" in

    Linux ) req_parted disk-tabletype || return
        req_parted disk-tabletype || return
        {
          $parted -s $1 print || {
            error "disk-tabletype at '$1'"
            return $?
          }
        } | grep Partition.Table: | sed 's/^Partition.Table: //'
      ;;

    Darwin )
        system_profiler SPSerialATADataType | grep -qv GPT || {
          error "Parse SPSerialATADataType plist" 1
        }
        echo gpt
      ;;

    * ) error "Disk-Tabletype: ${OS_UNAME:?}" 1 ;;
  esac
}

# volume id is "{disk-id}-{partition-index}"
disk_vol_info()
{
  test -d "$DISK_CATALOG" || error "Missing catalog env" 1
  test -n "$2" || set -- "$1" "id"
  #test -e "$DISK_CATALOG/volume/$1.sh" || {
  #  # Find ID for device if given iso. ID
  #  set -- $(disk_vol_id $1) $2
  #}
  test -e "$DISK_CATALOG/volume/$1.sh" \
    || error "No such known volume $1" 1
  . $DISK_CATALOG/volume/$1.sh
  eval echo \$volumes_main_$2
}


### Disk Catalog functions

disk_catalog_check_disk ()
{
  #echo "$disk_catalog_spec" | while IFS=$'\t\n' read -r media_var var_descr var_sources
  req_names=$disk_keys_req key=disk_ check_key_vars $disk_keys
}

disk_catalog_field ()
{
  test -n "${1-}" || error "disk-info disk-device" 1
  test -n "${2-}" || set -- "$1" "prefix"
  test -d "$DISK_CATALOG" || error "Invalid catalog env ($DISK_CATALOG)" 1

  test -e "$DISK_CATALOG/disk/$1.sh" || { {
      set -- "$(disk_id_for_dev "$1")" "$2" &&
      test -e "$DISK_CATALOG/disk/$1.sh"
    } || { error "No such known disk '$1'"; return 1; }; }

  . $DISK_CATALOG/disk/$1.sh
  eval echo \$$2
}

# evaluate, and use update env to copy file
disk_catalog_import()
{
  test -e "$1" || {
    error "No metafile $1"
    return 1
  }
  test -d "$DISK_CATALOG" || error "Missing catalog env" 1
  (
    disk_catalog_update "$1" || return $?
    disk_catalog_update_volume "$1" || return $?
  )
  std_info "Imported '$1'"
}

disk_catalog_clrenv_disk () # ~
{
  unset $disk_lsblk_keys_ext $(echo "$disk_catalog_spec"|cut -d$'\t' -f1)
}

disk_catalog_init_disk () # ~
{
  eval "$(disk_catalog_initenv_disk)"
}

disk_catalog_initenv_disk ()
{
  echo "$disk_catalog_spec" | {
    local var src_var f_key f_descr f_req f_src
    while IFS=$'\t\n' read -r f_key f_descr f_req f_src
    do
      var=disk_${f_key//-/_}
      src_var=
      if test -z "${!var:-}"
      then
        case ",$f_src," in
          ( *",lsblk,"* )
              lsblk_var=$(echo "$disk_keys_map" | grep "^$var " | cut -d' ' -f2)
              test -n "$lsblk_var" && {
                src_var=$lsblk_var
              } || {
                trueish "$f_req" || continue
                $LOG error "" "Required" "$f_key"
              }
            ;;
        esac
      fi
      test -n "${src_var:-}" || continue
      echo "$var=\"${!src_var:-}\""
    done
  }
}

disk_catalog_load_disk () # ~ <Disk-id>
{
  . $DISK_CATALOG/disk/${1:?}.sh
}

disk_catalog_load_partition () # ~ <Disk-id> <Part-nr>
{
  . $DISK_CATALOG/volume/${1:?}-${2:?}.sh
}

disk_catalog_put_disk () # (dc) ~
{
  local outf=${DISK_CATALOG:?}/disk/${disk_id:?}.sh
  {
    echo disk_host=\"$disk_host\"
    echo disk_id=$volumes_main_disk_id
    echo disk_index=$volumes_main_disk_index
    test -n "$volumes" \
      && echo volumes=\"$volumes $volumes_main_id\" \
      || echo volumes=\"$volumes_main_id\"

  } > "$outf"
}

disk_catalog_update_disk()
{
  test "$disk_id" = "$volumes_main_disk_id" || {
    note "$disk_id != $volumes_main_disk_id"
    error "disk-id mismatch '$1'" 1
  }

  test "$disk_index" = "$volumes_main_disk_index" \
    || error "disk-index mismatch '$1'" 1

  std_info "Current host: '$disk_host'"
  std_info "Existing volumes: '$disk_volumes'"

  local update=
  fnmatch *"$volumes_main_id"* "$disk_volumes" || update=1
  test "$(hostname)" = "$disk_host" || update=1

  test -z "$update" ||  {
    disk_catalog_put_disk || return $?
  }
}

disk_catalog_update()
{
  test -d "$DISK_CATALOG" || error "Missing catalog env" 1
  test -n "$1" || error "disk-catalog-update volumes-sh expected" 1
  #eval $(sed 's/volumes_main_//g' $1)
  #test -n "$id" || error "Volumes doc '$1' missing id" 1
  host="$(hostname)"
  volumes_main_id= volumes_main_part_id= volumes_main_part_index=

  eval $(cat $1)
  disk_catalog_volumes_check "$1"

  test "$disk_id" = "$volumes_main_disk_id" || {
    warn "Please fix ID $disk_id != $volumes_main_disk_id ($1)" 1
    return
  }

  # Extract disk ID parts from volumes doc
  test -e "$DISK_CATALOG/disk/$disk_id.sh" \
    && {

      . "$DISK_CATALOG/disk/$disk_id.sh"
      disk_catalog_update_disk "$1"

    } || {

      test "$disk_id" = "$volumes_main_disk_id" \
        || error "disk-id mismatch '$1'" 1

      disk_catalog_put_disk
    }

}

disk_catalog_update_volume()
{
  test -d "$DISK_CATALOG" || error "Missing catalog env" 1
  test -e "$DISK_CATALOG/volume/$disk_id-$volumes_main_part_index.sh" \
    && {
      part_id="$volumes_main_part_id"
      . $DISK_CATALOG/volume/$disk_id-$volumes_main_part_index.sh
      test "$volumes_main_part_id" = "$part_id" || {
        warn "Partition changed: $volumes_main_part_id"
      }
    } || {
      cp $1 $DISK_CATALOG/volume/$disk_id-$volumes_main_part_index.sh
    }
}

# Check .volumes.sh schema for disk
disk_catalog_volumes_check ()
{
  test -n "$volumes_main_id" || error "Volumes doc '$1' missing id" 1
  test -n "$volumes_main_part_id" \
    || error "Volumes doc '$1' missing part_id" 1
  test -n "$volumes_main_part_index" \
    || error "Volumes doc '$1' missing part_index" 1
  test -n "$volumes_main_disk_id" \
    || error "Volumes doc '$1' missing disk_id" 1
  test -n "$volumes_main_disk_index" \
    || error "Volumes doc '$1' missing disk_index" 1
}

disk_catalog_try_volume () # ~ <Part-dev> [<Expect-mounted>]
{
  test -b "${1:?}" || return $_E_GAE
  local expected=$(trueish "${2:-}" && echo true || echo false)
  disk_partition_lsblk_load "${1:?}" MOUNTPOINT \
    && test -n "${MOUNTPOINT:-}" || {
      $expected && return || return
    }
  test -d "${MOUNTPOINT:?"Cannot get MOUNTPOINT for $1"}/" || {
    $LOG warn "" "No mountpoint" "$1"
    return 1
  }
  test -s "$MOUNTPOINT/.volumes.sh" || {
    $LOG warn "" "No .volumes.sh" "$1"
    return 1
  }
  vol_sh="$MOUNTPOINT/.volumes.sh"
}


## Util

check_vars () # ~ <Var-names...>
{
  local var v
  for var in "$@"
  do
    v=${!var:-}
    test -n "$v" || {
      $LOG error "" "Missing or empty value" "$var:$v"
      return
    }
  done
}

check_key_vars () # [key,req_names] ~ <Name-parts...>
{
  local var name val
  for name in "$@"
  do
    var=${key}${name//-/_}
    val=${!var:-}
    test -n "$val" || {
      test -z "${req_names:-}" ||
        case " $req_names " in ( *" $name "* ) ;; ( * ) continue ;; esac;
      $LOG error "" "Missing or empty value" "$var:"
      return
    }
  done
}

find_partition_ids ()
{
  find /dev/disk/by-uuid -type l | while read path
  do
    test "$(basename $(readlink $path))" != "$(basename $1)" || {
      echo UUID:$(basename $path)
    }
  done

  if test -e /dev/disk/by-partuuid
  then
    find /dev/disk/by-partuuid -type l | while read path
    do
      test "$(basename $(readlink $path))" != "$(basename $1)" || {
        echo PART-UUID:$(basename $path)
      }
    done
  fi
}

# TODO handle disk-ids too

mount_tmp()
{
  test -n "$1" || error "Device or disk-id required" 1
  test -n "$2" || set -- "$1" 1
  tmpd=$(setup_tmpd disk/$2)
  warn "Mounting temporary disk $1"
  $mnt_pref mount $1 $tmpd || return $?
  note "Mounted $1 at $tmpd"
  tmp_mnt=$tmpd
}

is_mounted()
{
  test -n "$1" || error "Device or disk-id required" 1
  test -z "$2" || error "surplus arguments '$2'" 1
  {
    mount | grep -q '^'$1
  } || return $?
}


#
