#!/usr/bin/env bash
# tests/run_tests.sh — zero-dependency test runner for harness/lib modules.
#
# Secret owned: how test files are discovered and executed. Test files never
# self-execute; they only define functions and source the module under test.
#
# Discovery: every tests/test_*.sh file is a test suite. Every function in it
# whose name starts with test_ is one test case. Each case runs in its own
# bash process, so tests cannot leak state (variables, traps, cwd) into each
# other. A case passes iff its function returns 0; anything it prints is shown
# only on failure.
#
# Requires only bash + jq — the same floor as the harness itself. No bats or
# other framework: consuming repos inherit harness/ wholesale via install.sh
# and must be able to run these tests with nothing extra installed.
#
# Usage: harness/tests/run_tests.sh
# Exit: 0 if every case passed (and at least one ran), 1 otherwise.

set -u

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

total=0
failed=0

for test_file in "$tests_dir"/test_*.sh; do
  [ -e "$test_file" ] || continue
  suite="$(basename "$test_file")"

  # Enumerate test functions by sourcing the file in a throwaway process.
  # A file that fails to source (syntax error, missing module) is a failure,
  # never a silent skip.
  if ! declared="$(bash -c "source '$test_file' && declare -F" 2>&1)"; then
    total=$((total + 1))
    failed=$((failed + 1))
    printf 'FAIL  %s :: (file failed to source)\n' "$suite"
    [ -n "$declared" ] && printf '%s\n' "$declared" | sed 's/^/      /'
    continue
  fi
  test_fns="$(awk '$3 ~ /^test_/ {print $3}' <<< "$declared")"
  if [ -z "$test_fns" ]; then
    echo "WARN  $suite defines no test_ functions" >&2
    continue
  fi

  while IFS= read -r fn; do
    total=$((total + 1))
    if output="$(bash -c "source '$test_file' && $fn" 2>&1)"; then
      printf 'PASS  %s :: %s\n' "$suite" "$fn"
    else
      failed=$((failed + 1))
      printf 'FAIL  %s :: %s\n' "$suite" "$fn"
      [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
    fi
  done <<< "$test_fns"
done

echo "----"
echo "$((total - failed))/$total passed"

if [ "$total" -eq 0 ]; then
  echo "run_tests.sh: no tests found" >&2
  exit 1
fi
[ "$failed" -eq 0 ]
