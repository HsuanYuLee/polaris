#!/usr/bin/env bash
# validate-mise-dependency-change-selftest.sh — DP-240 T9 / AC11 selftest.
#
# Purpose: exercise three required fixtures:
#   1. with-DP fixture       — mise.toml diff + PR body with DP-NNN → exit 0
#   2. without-DP fixture    — mise.toml diff + PR body without DP-NNN → exit 2
#                              with marker POLARIS_MISE_DEPENDENCY_DP_MISSING:mise.toml
#   3. no-mise-change fixture — diff list excludes mise.toml → exit 0 (skip)
#
# The validator's --diff-files-override flag lets us inject synthetic diff lists
# without committing anything; the PR body is provided via temp files.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate-mise-dependency-change.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: validator missing: $SCRIPT" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

assert_exit() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_stderr_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label (stderr contains '$needle')"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (stderr missing '$needle')" >&2
    cat "$file" >&2
    fail=$((fail + 1))
  fi
}

# ------------------------------------------------------------------
# Case 1 (with-DP fixture): mise.toml changed + PR body references DP-240.
# ------------------------------------------------------------------
case1_body="$tmpdir/case1-pr-body.md"
cat >"$case1_body" <<'BODY'
## Summary

This PR bumps the python3 version in mise.toml per DP-240 dependency-management.md.

Refs: DP-240
BODY

set +e
bash "$SCRIPT" \
  --diff-files-override $'mise.toml\nscripts/foo.sh' \
  --pr-body "$case1_body" \
  --root "$tmpdir" \
  >"$tmpdir/case1.out" 2>"$tmpdir/case1.err"
case1_rc=$?
set -e
assert_exit "case1 with-DP" 0 "$case1_rc"

# ------------------------------------------------------------------
# Case 2 (without-DP fixture): mise.toml changed + PR body lacks DP-NNN.
# ------------------------------------------------------------------
case2_body="$tmpdir/case2-pr-body.md"
cat >"$case2_body" <<'BODY'
## Summary

Quick patch to bump python3. See the Polaris DP for context.

(no canonical DP-NNN reference here on purpose)
BODY

set +e
bash "$SCRIPT" \
  --diff-files-override $'mise.toml' \
  --pr-body "$case2_body" \
  --root "$tmpdir" \
  >"$tmpdir/case2.out" 2>"$tmpdir/case2.err"
case2_rc=$?
set -e
assert_exit "case2 without-DP" 2 "$case2_rc"
assert_stderr_contains "case2 marker present" \
  "POLARIS_MISE_DEPENDENCY_DP_MISSING:mise.toml" \
  "$tmpdir/case2.err"

# ------------------------------------------------------------------
# Case 3 (no-mise-change fixture): mise.toml NOT in diff → skip (exit 0).
# ------------------------------------------------------------------
case3_body="$tmpdir/case3-pr-body.md"
cat >"$case3_body" <<'BODY'
Touching only scripts. No mise.toml diff. No DP reference required.
BODY

set +e
bash "$SCRIPT" \
  --diff-files-override $'scripts/foo.sh\nREADME.md' \
  --pr-body "$case3_body" \
  --root "$tmpdir" \
  >"$tmpdir/case3.out" 2>"$tmpdir/case3.err"
case3_rc=$?
set -e
assert_exit "case3 no-mise-change" 0 "$case3_rc"

# ------------------------------------------------------------------
# AC11 adversarial: PR body contains fuzzy text "DP TBD" / "see Polaris DP"
# but no actual DP-NNN token — must still fail.
# ------------------------------------------------------------------
case4_body="$tmpdir/case4-pr-body.md"
cat >"$case4_body" <<'BODY'
Bumps mise.toml. See Polaris DP for details. (DP TBD)
BODY

set +e
bash "$SCRIPT" \
  --diff-files-override $'mise.toml' \
  --pr-body "$case4_body" \
  --root "$tmpdir" \
  >"$tmpdir/case4.out" 2>"$tmpdir/case4.err"
case4_rc=$?
set -e
assert_exit "case4 fuzzy-text adversarial" 2 "$case4_rc"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "validate-mise-dependency-change selftest: pass=$pass fail=$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
echo "PASS: validate-mise-dependency-change selftest"
