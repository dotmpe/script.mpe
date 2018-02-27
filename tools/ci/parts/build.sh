#!/bin/sh

note "Entry for CI build phase: '$BUILD_STEPS'"

for BUILD_STEP in $BUILD_STEPS
do case "$BUILD_STEP" in

    dev ) lib_load main; main_debug

        note "Pd help:"
        # FIXME: "Something wrong with pd/std__help"
        (
          ./projectdir.sh help || true
        )
        ./projectdir.sh test bats-specs bats || true

        note "box"
        (
           box help || true
        )

        # TODO install again? note "gtasks:"
        #./gtasks || noop

        #note "basename-reg:"
        #./basename-reg ffnnec.py

        note "mimereg:"
        (
           ./mimereg ffnenc.py
        ) || true

        #note "lst names local:"
        #892.2 https://travis-ci.org/dotmpe/script-mpe/jobs/191996789
        #lst names local
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

    test-feature )
      ;;

    test )
        lib_load build

        local failed=/tmp/htd-build-test-$(uuidgen).failed

        ## start with essential tests
        note "Testing required specs '$REQ_SPECS'"
        build_test_init "$REQ_SPECS"
        note "Init done"
        (
          test_shell $(which bats)|| true
          note "Bats shell tests done"
          note "$TEST_FEATURE '$BUSINESS_SUITE'"
          $TEST_FEATURE $BUSINESS_SUITE || true
          note "Feature tests done"
          python $PY_SUITE || true
          note "Python unittests done"
        ) # || touch $failed

        test -e "$TEST_RESULTS" || error "Test results expected" 1
        grep -qv '^not ok' $TEST_RESULTS || touch $failed
        not_falseish "$SHIPPABLE" && {

          perl $(which tap-to-junit-xml) --input $TEST_RESULTS \
            --output $(basepath $TEST_RESULTS .tap .xml)
          wc -l $TEST_RESULTS $(basepath $TEST_RESULTS .tap .xml)
        } || {
          wc -l $TEST_RESULTS
        }

        ## Other tests (TODO: complement?)
        #note "Testing all specs '$TEST_SPECS'"
        #build_test_init "$REQ_SPECS"
        #(
        #  test_shell $(which bats)
        #) || true

        test -z "$failed" -o ! -e "$failed" && r=0 || {
          r=1
          test ! -s "$failed" || {
            echo "Failed: $(echo $(cat $failed))"
          }
          rm $failed
          unset failed
        }
        exit $r
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

# Id: script-mpe/0.0.4-dev tools/ci/parts/build.sh
