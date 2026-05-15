#!/usr/bin/env bash
# Shared helpers for deterministic Polaris script selftests.

set -euo pipefail

script_test_temp_dir() {
  mktemp -d -t polaris-script-test.XXXXXX
}

script_test_restricted_path() {
  printf '%s\n' "/usr/bin:/bin:/usr/sbin:/sbin"
}

script_test_expect_pass() {
  local name="$1"
  shift
  if ! "$@"; then
    echo "FAIL: expected pass for ${name}" >&2
    return 1
  fi
}

script_test_expect_fail() {
  local name="$1"
  shift
  local output="${SCRIPT_TEST_LAST_OUTPUT:-/tmp/polaris-script-test-last.out}"
  if "$@" >"$output" 2>&1; then
    echo "FAIL: expected failure for ${name}" >&2
    cat "$output" >&2
    return 1
  fi
}

script_test_expect_output_contains() {
  local name="$1"
  local pattern="$2"
  local file="$3"
  if ! grep -qE "$pattern" "$file"; then
    echo "FAIL: expected ${name} output to match ${pattern}" >&2
    cat "$file" >&2
    return 1
  fi
}
