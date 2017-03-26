#!/bin/sh


# Functions to deal with script or function arguments.
# (for argv processing)
# nb. functions cannot access/change arguments of calling shell.


# Verbose test + return status

test_exists()
{
  test -e "$1" || {
    error "No such file or path: $1"
    return 1
  }
}

test_dir()
{
  test -d "$1" || {
    error "No such dir: $1"
    return 1
  }
}

test_file()
{
  test -f "$1" || {
    error "No such file: $1"
    return 1
  }
}

test_glob()
{
  for x in $1
  do
    test -e "$x" || return 1
  done
}


# arg-vars VARNAMES VALUES...
# Echo arguments as sh vars (use with local, export, etc)
arg_vars()
{
  local vars=$1
  shift
  for varname in $vars
  do
    test -z "$1" || {
      fnmatch "* *" "$1" && {
        printf " $varname=\"$1\""
      } || {
        printf " $varname=$1"
      }
    }
    shift
  done
  test -z "$1" || {
    error "surplus arguments: '$1'"
    return 1
  }
}


# Same as arg_vars but with usage, and debug verbosity
argv_vars()
{
  arg_vars "$@" || {
    echo "Usage: $0  $1" >&2
  }

  local vars=$1
  shift
  info "Parameters: $(
      for varname in $vars
      do
        printf " $varname=$1"
        shift
      done
    )"
}


# Exit on error


# Abort on surplus arguments
check_argc()
{
  local argi=$(( $1 + 1 ))
  local value="$(eval echo \$$argi)"
  test -z "$value" || error "surplus arguments (expected $1): '$value'" 1
}


# Find an executable script on path. Try with and without extension, in that
# order. Default extension: .phar
req_bin()
{
  test -n "$2" || set -- "$1" ".phar"
  test -x "$(which $1$2)" && {
    export $1_bin=$1$2
  } || {
    test -x "$(which $1)" && {
      export $1_bin=$1
    } || {
      error "Executable $1 required" 1
    }
  }
}


req_path_arg()
{
	test -n "$1" -a -e "$1" || error "path or file argument expected: '$1'" 1
}


req_file_arg()
{
	test -n "$1" -a -f "$1" || error "file argument expected: '$1'" 1
}


req_dir_arg()
{
  test -n "$1" -a -d "$1" || error "directory argument expected: '$1'" 1
}


# same as req-dir-arg but set argument to var 'path' also
req_cdir_arg()
{
  test -n "$1"  && path="$1"  || path=.
  req_dir_arg "$1"
}


req_file_env()
{
  while test $# -gt 0
  do
    value="$(eval echo "\$$1")"
    test -n "$value" || {
      error "file env '$1' expected but missing or empty ($?)" 1
    }
    test -f "$value" || {
      error "no such file for env '$1': $value" 1
    }
    shift
  done
}


req_dir_env()
{
  while test $# -gt 0
  do
    value="$(eval echo "\$$1")"
    test -n "$value" || {
      error "directory env '$1' expected but missing or empty ($?)" 1
    }
    test -d "$value" || {
      error "no such directory for env '$1': $value" 1
    }
    shift
  done
}

# opt-args: helper to filter options for arguments
opt_args()
{
  for arg in $@
  do fnmatch "-*" "$arg" && echo "$arg" >>$options || echo $arg >>$arguments
  done
}

