#!/usr/bin/env bash
test -z "${sh_util_:-}" && sh_util_=1 || return 198 # Recursion


# XXX: need to integrate setup, build-up using arrays.
#sh_require os || sh_include os

#sh_require
#stderr echo us-bin:tool/sh/util.sh

# TODO: move some of below to CI util.sh

. $HOME/bin/tool/sh/init-include.sh # Initialize sh_include

sh_include \
  str-bool str-id read exec \
  unique-paths hd-offsets suite-from-table suite-source suite-run


# Sync: X-CI-0.1:
# Sync: U-S:
