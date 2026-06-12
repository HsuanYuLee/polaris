#!/usr/bin/env bash
# Purpose: Selftest for scripts/lib/approval-staleness.sh — the canonical
#          commit_id-based approval-staleness atom (DP-315 T1, AC2/AC-NEG3).
# Inputs:  none (sources the helper and exercises it directly).
# Outputs: stdout PASS/FAIL lines; exit 0 = all pass, exit 1 = any failure.
#
# Contract under test (DP-315 AC2/AC-NEG3):
#   approval_staleness <review_commit_id> <head_sha> echoes:
#     - "valid"  when commit_id == head_sha (both non-empty)
#     - "stale"  when commit_id != head_sha
#     - "stale"  when commit_id is empty/null OR head_sha is empty/null
#                (fail-closed; must not crash, must not silently judge valid)
set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"

# shellcheck source=../lib/approval-staleness.sh
source "$ROOT_DIR/scripts/lib/approval-staleness.sh"

FAIL=0

assert_eq() {
  # Args: <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: %s (got %s)\n' "$label" "$actual"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    FAIL=1
  fi
}

# --- Three-state contract -----------------------------------------------------

# 1. commit_id == head.sha → valid
out="$(approval_staleness "abc123" "abc123")"
assert_eq "equal commit_id and head.sha => valid" "valid" "$out"

# 2. commit_id != head.sha → stale (force-push / rebase / new commit)
out="$(approval_staleness "abc123" "def456")"
assert_eq "different commit_id and head.sha => stale" "stale" "$out"

# --- Fail-closed null / empty cases (AC-NEG3) ---------------------------------

# 3. empty review.commit_id → stale (not valid even if head.sha empty too)
out="$(approval_staleness "" "def456")"
assert_eq "empty commit_id => stale" "stale" "$out"

# 4. literal "null" review.commit_id (gh --jq emits null as the string) → stale
out="$(approval_staleness "null" "def456")"
assert_eq "null commit_id => stale" "stale" "$out"

# 5. empty head.sha → stale (head resolution failed)
out="$(approval_staleness "abc123" "")"
assert_eq "empty head.sha => stale" "stale" "$out"

# 6. literal "null" head.sha → stale
out="$(approval_staleness "abc123" "null")"
assert_eq "null head.sha => stale" "stale" "$out"

# 7. both empty → stale (must NOT treat ""=="" as valid — adversarial pass AC2)
out="$(approval_staleness "" "")"
assert_eq "both empty => stale (no empty-string false valid)" "stale" "$out"

# 8. both literal "null" → stale
out="$(approval_staleness "null" "null")"
assert_eq "both null => stale" "stale" "$out"

# 9. missing args (no crash under set -euo pipefail) → stale, exit 0
out="$(approval_staleness)"
assert_eq "no args => stale (fail-closed, no crash)" "stale" "$out"

# --- AC1: canonical definition rewritten to commit_id basis -------------------

DEF_FILE="$ROOT_DIR/.claude/skills/references/stale-approval-detection.md"

if grep -q 'commit_id' "$DEF_FILE"; then
  printf 'PASS: stale-approval-detection.md references commit_id rule\n'
else
  printf 'FAIL: stale-approval-detection.md missing commit_id rule\n' >&2
  FAIL=1
fi

# The old timestamp rule (submitted_at vs pushed_at) must be gone from the
# canonical definition (AC1; adversarial pass: no stale leftover timestamp rule).
if grep -Eq 'submitted_at[^a-zA-Z]*[<>][^a-zA-Z]*pushed_at|pushed_at[^a-zA-Z]*[<>][^a-zA-Z]*submitted_at' "$DEF_FILE"; then
  printf 'FAIL: stale-approval-detection.md still contains submitted_at/pushed_at timestamp rule\n' >&2
  FAIL=1
else
  printf 'PASS: stale-approval-detection.md no longer uses submitted_at/pushed_at timestamp rule\n'
fi

if [[ "$FAIL" -eq 0 ]]; then
  printf '\nAll approval-staleness selftests PASSED.\n'
  exit 0
fi

printf '\napproval-staleness selftest FAILED.\n' >&2
exit 1
