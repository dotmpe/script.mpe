#!/usr/bin/env bash

### package-init: helper routines for package.lib

# package-load() is a wrapper to start package.lib, package-require() provides
# some verbososity, and also supports the package-require:bool setting like
# package.lib:-set-local does.

package_require ()
{
  package_load || return

  # Evaluate package env, if found or required
  test ! -e "${PACK_SH-}" &&
  ! "${package_require:-false}" || {

    . $PACK_SH || stderr error "local package ($?)" 7
    $LOG debug "" "Found package '$package_id'"
  }
}

# Setup package.lib, and initialize for current directory
package_load () # ~ [<Package-Dir>] [<Package-Id>]
{
  test ${package_lib_init:-1} -eq 0 || {
    test ${package_lib_load:-1} -eq 0 || {
      lib_require package || return
    }
    package_lib_auto=true lib_init package || return
  }
  package_init "$@"
}

#
