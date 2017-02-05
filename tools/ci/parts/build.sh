#!/bin/sh

note "Entry for CI build phase: '$BUILD_STEPS'"

for BUILD_STEP in $BUILD_STEPS
do case "$BUILD_STEP" in

    dev ) lib_load main; main_debug

        note "Pd version:"
        # FIXME: pd alias
        # TODO: Pd requires user-conf.
        (
          pd version || noop
          projectdir.sh version || noop
          ./projectdir.sh version || noop
        )
        #note "Pd help:"
        # FIXME: "Something wrong with pd/std__help"
        #(
        #  ./projectdir.sh help || noop
        #)
        #./projectdir.sh test bats-specs bats

        # TODO install again? note "gtasks:"
        #./gtasks || noop

        note "Htd script:"
        (
          htd script
        ) && note "ok" || noop

        note "basename-reg:"
        (
          ./basename-reg ffnnec.py
        ) || noop
        note "mimereg:"
        (
          ./mimereg ffnenc.py
        ) || noop

        note "lst names local:"
        #892.2 https://travis-ci.org/dotmpe/script-mpe/jobs/191996789
        (
          lst names local
        ) || noop
        # [lst.bash:names] Warning: No 'watch' backend
        # [lst.bash:names] Resolved ignores to '.bzrignore etc:droppable.globs
        # etc:purgeable.globs .gitignore .git/info/exclude'
        #/home/travis/bin/lst: 1: exec: 10: not found
      ;;

    jekyll )
        bundle exec jekyll build
      ;;

    test-vbox )
      ;;

    test )
        lib_load build

        ## start with essential tests
        note "Testing '$REQ_SPECS'"

        failed=build/test-results-failed.list

        test -n "$TEST_RESULTS" || TEST_RESULTS=build/test-results-specs.tap
        (
          #SUITE="$REQ_SPECS" test_shell $TEST_SHELL $(which bats)
          SUITE="$REQ_SPECS" test_shell > $TEST_RESULTS
        ) || noop

        trueish "$SHIPPABLE" && {
          perl $(which tap-to-junit-xml) --input $TEST_RESULTS \
            --output $(basepath $TEST_RESULTS .tap .xml)
          wc -l $TEST_RESULTS $(basepath $TEST_RESULTS .tap .xml)
        } || {
          wc -l $TEST_RESULTS
        }

        ## Other tests
        note "Testing '$TEST_SPECS'"
        (
          SUITE="$TEST_SPECS" test_shell
        ) || noop

        # TODO: integrate feature testing
        (
          test_features
        ) || noop

        test -z "$failed" -o ! -e "$failed" && {
          r=0
          test ! -s "$failed" || {
            echo "Failed: $(echo $(cat $failed))"
            rm $failed
            r=1
          }
          unset failed
        } || noop

      ;;

    noop )
        # TODO: make sure nothing, or as little as possible has been installed
        note "Empty step ($BUILD_STEP)" 0
      ;;

    * )
        error "Unknown step '$BUILD_STEP'" 1
      ;;

  esac

  note "Step '$BUILD_STEP' done"
done

note "Done"

