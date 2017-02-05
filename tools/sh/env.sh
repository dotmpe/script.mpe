#!/bin/sh

# Keep current shell settings and mute while preparing env, restore at the end
shopts=$-
set +x
set -e

# Restore shell -e opt
case "$shopts"

  in *e* )
    test "$EXIT_ON_ERROR" = "false" -o "$EXIT_ON_ERROR" = "0" && {
      # undo Jenkins opt, unless EXIT_ON_ERROR is on
      echo "[$0] Important: Shell will NOT exit on error (EXIT_ON_ERROR=$EXIT_ON_ERROR)"
      set +e
    } || {
      echo "[$0] Note: Shell will exit on error (EXIT_ON_ERROR=$EXIT_ON_ERROR)"
      set -e
    }
    ;;

  * )
    # Turn off again
    set +e
    ;;

esac


req_vars scriptdir || error "scriptdir = $scriptdir" 1
req_vars SCRIPTPATH || error "SCRIPTPATH" 1
req_vars LIB || error "LIB" 1


### Start of build job parameterisation

req_vars DEBUG || export DEBUG=
req_vars ENV || export ENV=development

req_vars Build_Deps_Default_Paths || export Build_Deps_Default_Paths=1
req_vars sudo || export sudo=sudo

req_vars RUN_INIT || export RUN_INIT=
req_vars RUN_FLOW || export RUN_FLOW=
req_vars RUN_OPTIONS || export RUN_OPTIONS=

req_vars TEST_COMPONENTS || export TEST_COMPONENTS=
req_vars TEST_FEATURES || export TEST_FEATURES=
req_vars TEST_OPTIONS || export TEST_OPTIONS=

req_vars TEST_SPECS || export TEST_SPECS="helper util-lib str std os match vc-lib vc main box-lib box-cmd box"
  
req_vars APT_PACKAGES || export APT_PACKAGES=

#    	nodejs npm \
#      	python-dev \
#        realpath uuid-runtime moreutils curl php5-cli


### Env of build job parameterisation


# Restore shell -x opt
case "$shopts" in
  *x* )
    case "$DEBUG" in
      [Ff]alse|0|off|'' )
        # undo verbosity by Jenkins, unless DEBUG is explicitly on
        set +x ;;
      * )
        echo "[$0] Shell debug on (DEBUG=$DEBUG)"
        set -x ;;
    esac
  ;;
esac

# Id: script-mpe/0.0.3-dev tools/sh/env.sh
