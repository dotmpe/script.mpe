
## Shell/decl: track shell declarations for more optimal type handling

# Benchmarking methods to check if array is defined (but may be empty)
#

# A. process opts from `declare -p` output, or
# B. 1. store opts in one assoc arr, or
# B. 2. one array for each opt, or
# C. use standard simple variables using variable name keying

# Numbers below. Observations:
# Surprised the `declare -p` subshell has this large an impact compared to
# case/esac. And clearly caching improves runtime more than one order
# of magnitude. Associative arrays showing a tiny but noticable improvement
# over regular variables (most or all of the times).

# Did not do test B.2 because it seems like it would be worse than either B
# or C anyway, as case/esac has little impact and B.2. would double 'access
# time' to get rid of just the opts matching...

# See also other previous benchmarks:
#
# - tools/bookmark/bm-sh-type.sh
#   how declare -F is a superior check for types (0.1us on t460s vs. 450 microseconds for type -t plus str cmp).
#
# - tools/benchmark/bm-sh-regex-case.sh
#   compare regex vs. case/esac string matching (1.7 vs 1.2 ms @t460s)
#   Even test is (a bit) slower (1.5ms).
#
# - tools/benchmark/bm-sh-test.sh (test -n "str" runs in 9us @t460s)

# Conclusion: some of these numbers need review because I'm not sure all adds
# up. But probably want to review more automatic profiling method, etc.

# Regardless, numbers are very favorable towards:
#
# 1. as little subshells as needed (what else is new...)
# 2. better arrays than classical variables with magic names, but either is not
#    bad. At least because here the symbols are already variable names
#    so they need no further encoding to use as 'key'.
# 3. case/esac wins for simple str match, same as other string expansions.
#
# And I think regex (don't forget BASH_REMATCH) easily outperforms any
# external program but that is just an semi-informed opinion atm. Need to do
# some testing of regex builtin vs. grep/awk/sed/perl/ag/rg/... some day
# but regex'ing is not too important right away.

# Update: added ${var@A} expansion, only performs slightly worse than var/arr
# caching.
# But so littering env with chached opts may be sub optimal.
# Of course, nothing is said yet about large arrays.

source "${CWD:?}"/tool/benchmark/_lib.sh

sh_mode strict

# A. 10000x ~<8s
# B. 10000x 0.4s
# C. 10000x >0.4s
# D.1,2 (other test)
# E. 10000x 0.4s
runs=10000

myTestVariable=2e39486d4b881953965441509f9dd13bd0ccab5c62078339abc7ee41db2494d0

read_decl ()
{
  read -r dname dopts decl <<< "$(declare -p "${1:?}")"
}

is_assoc_arr ()
{
  case "${1:1}" in ( *A* ) true ;; ( * ) false ;; esac
}

is_index_arr ()
{
  case "${1:1}" in ( *a* ) true ;; ( * ) false ;; esac
}

is_arr ()
{
  is_assoc_arr "$dopts" || is_index_arr "$dopts"
}

test_A_raw () # ~ <Array>
{
  read_decl "$1" &&
  is_arr "$dopts"
}

declare -A my_b_cache

test_B_cache_arr ()
{
  test "${my_b_cache["$1"]-unset}" = "unset" && {
    read_decl "$1"
    my_b_cache["$1"]=$dopts
  } || {
    dopts=${my_b_cache["$1"]}
  }
  is_arr "$dopts"
}

test_C_cache_vars ()
{
  declare var="${1:?}_opts"
  test "${!var-unset}" = "unset" && {
    read_decl "$1"
    declare -g "${1:?}_opts=$dopts"
  } || {
    dopts=${!var}
  }
  is_arr "$dopts"
}

test_C_is_working ()
{
  test_C_cache_vars myTestVariable
  echo n:$dname $dopts d:$decl
  unset dname dopts decl
  test_C_cache_vars myTestVariable
  echo n:${dname:-unset} ${dopts:-unset} d:${decl:-unset}
}


declare -A my_d_cache

test_D_caching_declare_F ()
{
  declare val
  true "${val:=${my_d_cache["$1"]-unset}}"
  test "$val" = unset && {
    declare -F "${1:?}" >/dev/null 2>&1 && {
        exists=true
    } || {
        exists=false
    }
    my_d_cache["$1"]=$exists
  } || {
    exists="${my_d_cache["$1"]:?}"
  }
  ${exists:?}
}

test_E_str_expansion ()
{
  declare var=${1:?} dopts
  dopts="${!var@A}"
  is_arr
}

echo "Run raw declare -p read (no cache)"
time run_test $runs -- test_A_raw myTestVariable
echo
echo "Run from cached declare -p (assoc arr)"
time run_test $runs -- test_B_cache_arr myTestVariable
echo
echo "Run from cached declare -p (plain var)"
time run_test $runs -- test_C_cache_vars myTestVariable
echo
echo "D. Test raw call vs array key lookup (no opts caching, only keying)"
# When caching result of built-in call only (no str I/O), array caching gives
# negative speed optimization: ~0.2 vs ~0.3 seconds / 10000x.
# declare -p has similar execution time to raw (declare -F)
time run_test_q $runs -- declare -F run_test
time run_test $runs -- test_D_caching_declare_F run_test
time run_test_q $runs -- declare -p myTestVariable
echo
echo "E. Run raw str expansion (no cache)"
time run_test $runs -- test_E_str_expansion myTestVariable

#
