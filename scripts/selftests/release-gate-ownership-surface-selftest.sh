#!/usr/bin/env bash
# Purpose: lock the release-blocking gate owner matrix so new release stages
# fail closed until they declare an upstream owner or a release-tail-only reason.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK_GATE="$ROOT_DIR/scripts/check-framework-pr-gate.sh"
RELEASE_LANE="$ROOT_DIR/scripts/framework-release-pr-lane.sh"
FRAMEWORK_RELEASE_SKILL="$ROOT_DIR/.claude/skills/framework-release/SKILL.md"

fail() {
  echo "[release-gate-ownership-surface-selftest] FAIL: $*" >&2
  exit 1
}

validate_owner_matrix() {
  local name="$1"
  local matrix_file="$2"
  local expected_count="$3"

  [[ -s "$matrix_file" ]] || fail "$name owner matrix is empty"
  head -1 "$matrix_file" | grep -qx $'stage\tlabel\towner\troute_back\trelease_tail_only_reason' \
    || fail "$name owner matrix header drifted"

  local rows
  rows="$(tail -n +2 "$matrix_file" | sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]')"
  [[ "$rows" == "$expected_count" ]] \
    || fail "$name owner matrix row count mismatch: expected $expected_count got $rows"

  awk -F '\t' '
    NR == 1 { next }
    NF != 5 { printf "bad field count at %s\n", $1; exit 10 }
    $1 == "" || $2 == "" || $3 == "" || $4 == "" {
      printf "missing required owner field at %s\n", $1; exit 11
    }
    seen[$1]++ {
      printf "duplicate stage id %s\n", $1; exit 12
    }
    $3 == "release_tail_only" && $5 == "" {
      printf "release-tail-only stage missing reason at %s\n", $1; exit 13
    }
    $3 != "release_tail_only" && $3 !~ /^upstream:/ {
      printf "invalid owner %s at %s\n", $3, $1; exit 14
    }
  ' "$matrix_file" || fail "$name owner matrix validation failed"
}

tmpdir="$(mktemp -d -t release-gate-owner.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

bash "$CHECK_GATE" --list-stage-owners >"$tmpdir/check-owners.tsv"
bash "$RELEASE_LANE" --list-stage-owners >"$tmpdir/release-owners.tsv"

validate_owner_matrix "check-framework-pr-gate" "$tmpdir/check-owners.tsv" 16
validate_owner_matrix "framework-release-pr-lane" "$tmpdir/release-owners.tsv" 9

bash "$CHECK_GATE" --list-stages | awk '{print $1}' >"$tmpdir/check-stages.txt"
tail -n +2 "$tmpdir/check-owners.tsv" | cut -f1 >"$tmpdir/check-owner-stages.txt"
diff -u "$tmpdir/check-stages.txt" "$tmpdir/check-owner-stages.txt" >/dev/null \
  || fail "check-framework-pr-gate --list-stages and --list-stage-owners drifted"

grep -Fq "## Upstream-Owned Failure Route-Back" "$FRAMEWORK_RELEASE_SKILL" \
  || fail "framework-release skill missing upstream-owned route-back contract"
grep -Fq "append-auto-pass-friction.sh" "$FRAMEWORK_RELEASE_SKILL" \
  || fail "framework-release skill missing friction capture writer reference"
grep -Fq "不得在 release tail 補 code" "$FRAMEWORK_RELEASE_SKILL" \
  || fail "framework-release skill must forbid release-tail implementation repair"
grep -Fq "generic PR publisher" "$FRAMEWORK_RELEASE_SKILL" \
  || fail "framework-release skill must forbid generic PR publisher fallback"

echo "[release-gate-ownership-surface-selftest] PASS"
