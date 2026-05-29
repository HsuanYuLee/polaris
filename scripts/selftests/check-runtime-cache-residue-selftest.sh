#!/usr/bin/env bash
# Selftest for check-runtime-cache-residue.sh.
#
# Purpose:
#   Verify the runtime cache residue gate over both the legacy
#   workspace-wide flag behavior and the source-scoped filename matching
#   added by DP-261. Covers:
#     - 5 legacy cases: empty / source durable / shared .polaris residue /
#       old .codex external-writes residue / .codex tmp residue (AC-NEG2
#       regression preservation).
#     - Same-source filename flag with --source-container (AC1).
#     - Cross-source PR filename skipped with --source-container (AC2).
#     - Orphan filename (no recognizable source key prefix) still flagged
#       (AC3, EC3).
#     - 5 source-key patterns DP/KB2CW/GT/KQT/PR cross-source skipped (AC4).
#     - .codex/external-writes/ cross-source filename still flagged
#       (forbidden old residue is scope-filter-immune) (AC5).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$SCRIPT_DIR/check-runtime-cache-residue.sh"
TMP="$(mktemp -d -t runtime-cache-residue.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

assert_pass() {
  local label="$1"
  shift
  if ! "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: expected pass: $label" >&2
    cat "$TMP/out" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
}

assert_fail_contains() {
  local label="$1"
  local expected="$2"
  shift 2
  if "$@" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: expected failure: $label" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! rg -q --fixed-strings "$expected" "$TMP/err"; then
    echo "FAIL: expected '$expected' in stderr for $label" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Legacy 5-case fixture (AC-NEG2 regression: preserve pre-DP-261 behavior).
# ---------------------------------------------------------------------------

repo="$TMP/repo"
source_container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-demo"
mkdir -p "$source_container/artifacts/external-writes" "$source_container/artifacts/research" "$source_container/jira-comments"

assert_pass "empty runtime cache" "$CHECKER" --repo "$repo" --source-container "$source_container"

printf 'durable\n' >"$source_container/artifacts/external-writes/20260516-body.md"
printf 'research\n' >"$source_container/artifacts/research/2026-05-16-note.md"
assert_pass "source container durable artifacts are allowed" "$CHECKER" --repo "$repo" --source-container "$source_container"

mkdir -p "$repo/.polaris/runtime/external-writes"
# body.md has no recognizable source key prefix → orphan → flag.
printf 'body\n' >"$repo/.polaris/runtime/external-writes/body.md"
assert_fail_contains "shared runtime cache residue" ".polaris/runtime/external-writes/body.md" "$CHECKER" --repo "$repo" --source-container "$source_container"
rm -f "$repo/.polaris/runtime/external-writes/body.md"

mkdir -p "$repo/.codex/external-writes"
printf 'old body\n' >"$repo/.codex/external-writes/body.md"
assert_fail_contains "old codex external write residue" ".codex/external-writes/body.md" "$CHECKER" --repo "$repo" --source-container "$source_container"
rm -f "$repo/.codex/external-writes/body.md"

mkdir -p "$repo/.codex/tmp"
printf 'scratch\n' >"$repo/.codex/tmp/scratch.log"
assert_fail_contains "codex tmp residue" ".codex/tmp/scratch.log" "$CHECKER" --repo "$repo" --source-container "$source_container"
assert_fail_contains "source destination hint" "artifacts/external-writes" "$CHECKER" --repo "$repo" --source-container "$source_container"
rm -f "$repo/.codex/tmp/scratch.log"

# ---------------------------------------------------------------------------
# DP-261 new cases: source-scoped filename matching.
# Use a fresh repo + DP-261 source container so the source key derivation
# is unambiguous and prior fixtures cannot pollute the test.
# ---------------------------------------------------------------------------

repo2="$TMP/repo2"
src_dp261="$repo2/docs-manager/src/content/docs/specs/design-plans/DP-261-demo"
mkdir -p "$src_dp261/artifacts/external-writes" "$src_dp261/artifacts/research" "$src_dp261/jira-comments"
mkdir -p "$repo2/.polaris/runtime/external-writes" "$repo2/.codex/external-writes" "$repo2/.codex/tmp"

# AC1: same-source filename match (dp-261-test.md + source=DP-261 → fail).
printf 'same source\n' >"$repo2/.polaris/runtime/external-writes/dp-261-test.md"
assert_fail_contains "AC1 same-source filename match" ".polaris/runtime/external-writes/dp-261-test.md" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/dp-261-test.md"

# AC2: cross-source PR filename skipped (pr-2431-smartbanner-test.md + source=DP-261 → pass).
printf 'cross source pr\n' >"$repo2/.polaris/runtime/external-writes/pr-2431-smartbanner-test.md"
assert_pass "AC2 cross-source PR filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/pr-2431-smartbanner-test.md"

# AC3 + EC3: orphan filename (no recognizable source key prefix) + source=DP-261 → fail.
printf 'orphan\n' >"$repo2/.polaris/runtime/external-writes/scratch.md"
assert_fail_contains "AC3 orphan filename flagged" ".polaris/runtime/external-writes/scratch.md" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/scratch.md"

# AC4: source-key patterns — cross-source DP / KB2CW / GT / KQT / PR all skipped.
printf 'cross dp\n' >"$repo2/.polaris/runtime/external-writes/dp-260-other.md"
assert_pass "AC4 cross-source DP-260 filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/dp-260-other.md"

printf 'cross kb2cw\n' >"$repo2/.polaris/runtime/external-writes/kb2cw-1-task.md"
assert_pass "AC4 cross-source kb2cw filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/kb2cw-1-task.md"

printf 'cross gt\n' >"$repo2/.polaris/runtime/external-writes/gt-1-epic.md"
assert_pass "AC4 cross-source gt filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/gt-1-epic.md"

printf 'cross kqt\n' >"$repo2/.polaris/runtime/external-writes/kqt-1-other.md"
assert_pass "AC4 cross-source kqt filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/kqt-1-other.md"

printf 'cross pr\n' >"$repo2/.polaris/runtime/external-writes/pr-9999-other.md"
assert_pass "AC4 cross-source PR-9999 filename skipped" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/pr-9999-other.md"

# R2 word-boundary: DP-26 source key must not match dp-261-x.md filename.
src_dp26="$repo2/docs-manager/src/content/docs/specs/design-plans/DP-26-demo"
mkdir -p "$src_dp26"
printf 'dp-261 file under dp-26 source\n' >"$repo2/.polaris/runtime/external-writes/dp-261-x.md"
assert_pass "R2 word-boundary: DP-26 source does not match dp-261-x.md" "$CHECKER" --repo "$repo2" --source-container "$src_dp26"
rm -f "$repo2/.polaris/runtime/external-writes/dp-261-x.md"

# AC5: cross-source filename inside .codex/external-writes/ is still flagged
# (forbidden old residue is scope-filter-immune).
printf 'codex cross\n' >"$repo2/.codex/external-writes/pr-2431-smartbanner.md"
assert_fail_contains "AC5 .codex cross-source residue still flagged" ".codex/external-writes/pr-2431-smartbanner.md" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.codex/external-writes/pr-2431-smartbanner.md"

# EC5: when --source-container is omitted, gate falls back to workspace-wide.
printf 'cross source pr\n' >"$repo2/.polaris/runtime/external-writes/pr-2431-smartbanner-test.md"
assert_fail_contains "EC5 fallback: no --source-container flags everything" ".polaris/runtime/external-writes/pr-2431-smartbanner-test.md" "$CHECKER" --repo "$repo2"
rm -f "$repo2/.polaris/runtime/external-writes/pr-2431-smartbanner-test.md"

# EC2: case-insensitive same-source match (uppercase filename + DP-261 key).
printf 'upper case\n' >"$repo2/.polaris/runtime/external-writes/DP-261-uppercase.md"
assert_fail_contains "EC2 case-insensitive same-source match" ".polaris/runtime/external-writes/DP-261-uppercase.md" "$CHECKER" --repo "$repo2" --source-container "$src_dp261"
rm -f "$repo2/.polaris/runtime/external-writes/DP-261-uppercase.md"

echo "check-runtime-cache-residue selftest: PASS"
