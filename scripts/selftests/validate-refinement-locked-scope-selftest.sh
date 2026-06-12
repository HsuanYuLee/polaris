#!/usr/bin/env bash
# Purpose: DP-311 T5 selftest — locked-scope guard per-field granularity for
#          acceptance_criteria: only acceptance_criteria[].verification.detail
#          is amendable after LOCK; id / text / category / verification.method
#          and AC add/remove stay locked, and goal / background / decisions /
#          scope remain whole-field locked.
# Inputs:  none (builds throwaway git fixture repos under mktemp).
# Outputs: PASS line on stdout, exit 0; FAIL diagnostics on stderr, exit 1.
#
# Cases:
#   1. (AC7a)    detail-only amendment on one AC                     → exit 0.
#   2. (AC7c)    DP-252 AC-NEG1 regression: detail 增列 changeset path → exit 0.
#   3. (AC7b)    text change                                          → exit 2.
#   4. (AC7b)    verification.method change                           → exit 2.
#   5. (AC7b)    category change                                      → exit 2.
#   6. (AC7b)    id rename (id 集合變動)                              → exit 2.
#   7. (AC7b)    AC add                                               → exit 2.
#   8. (AC7b)    AC remove                                            → exit 2.
#   9. (EC8)     detail + text changed in the same AC                 → exit 2.
#  10. (AC-NEG6) goal / background / decisions / scope 整欄鎖定迴歸    → exit 2 each.
#  11. (sanity)  non-LOCKED field (technical_approach) amendment      → exit 0.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-refinement-locked-scope.sh"

TMP="$(mktemp -d -t validate-refinement-locked-scope-XXXX)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "selftest@polaris.dev"
git -C "$REPO" config user.name "selftest"

CONTAINER_REL="docs-manager/src/content/docs/specs/design-plans/DP-998-per-field-fixture"
CONTAINER="$REPO/$CONTAINER_REL"
mkdir -p "$CONTAINER"

cat >"$CONTAINER/refinement.json" <<'JSON'
{
  "version": "1",
  "goal": "original goal",
  "background": "original background",
  "decisions": ["D1"],
  "scope": ["thing A"],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "original AC1 text",
      "category": "functional",
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/fixture-selftest.sh original detail"
      }
    },
    {
      "id": "AC-NEG1",
      "text": "implementation commits 改動 path 全部在 allowed list 內",
      "category": "negative",
      "negative": true,
      "verification": {
        "method": "unit_test",
        "detail": "git diff --name-only assert 改動 path 全部在 allowed list（rule file + DP container）內"
      }
    }
  ],
  "technical_approach": "original approach",
  "tasks": [{"id": "DP-998-T1", "title": "original task title"}]
}
JSON

git -C "$REPO" add .
git -C "$REPO" commit -q -m "initial LOCKED snapshot"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

# mutate_json: reset fixture to LOCKED snapshot, apply python mutation, commit.
# Args: $1 = python statement(s) operating on `data` (parsed refinement.json)
mutate_json() {
  local mutation="$1"
  git -C "$REPO" reset --hard "$BASE_SHA" -q
  python3 - "$CONTAINER/refinement.json" "$mutation" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
exec(sys.argv[2])
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m "amendment fixture"
}

# expect_pass: run validator, fail the selftest if it rejects the amendment.
# Args: $1 = case label
expect_pass() {
  local label="$1"
  if ! "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/out" 2>&1; then
    echo "FAIL: $label was incorrectly rejected" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
}

# expect_violation: run validator, fail unless exit 2 + violation signal.
# Args: $1 = case label
expect_violation() {
  local label="$1"
  local rc=0
  "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: $label expected exit 2, got $rc" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! grep -q "POLARIS_LOCKED_SCOPE_VIOLATION" "$TMP/out"; then
    echo "FAIL: $label missing POLARIS_LOCKED_SCOPE_VIOLATION stderr signal" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
}

# === Case 1 (AC7a): detail-only amendment → PASS ===
mutate_json 'data["acceptance_criteria"][0]["verification"]["detail"] = "bash scripts/selftests/fixture-selftest.sh amended detail with extra fixture case"'
expect_pass "case 1 (detail-only amendment)"

# === Case 2 (AC7c): DP-252 AC-NEG1 regression — detail 增列 changeset path → PASS ===
mutate_json 'data["acceptance_criteria"][1]["verification"]["detail"] += "；allowed list 增列 .changeset/dp-252-t1-*.md（task changeset；gate-changeset 強制的 delivery artifact）"'
expect_pass "case 2 (DP-252 AC-NEG1 detail 增列 changeset path)"

# === Case 3 (AC7b): text change → exit 2 ===
mutate_json 'data["acceptance_criteria"][0]["text"] = "rewritten AC1 text (violation)"'
expect_violation "case 3 (text change)"

# === Case 4 (AC7b): verification.method change → exit 2 ===
mutate_json 'data["acceptance_criteria"][0]["verification"]["method"] = "manual"'
expect_violation "case 4 (verification.method change)"

# === Case 5 (AC7b): category change → exit 2 ===
mutate_json 'data["acceptance_criteria"][0]["category"] = "negative"'
expect_violation "case 5 (category change)"

# === Case 6 (AC7b): id rename → exit 2 (id 集合變動) ===
mutate_json 'data["acceptance_criteria"][0]["id"] = "AC1-renamed"'
expect_violation "case 6 (id rename)"

# === Case 7 (AC7b): AC add → exit 2 ===
mutate_json 'data["acceptance_criteria"].append({"id": "AC2", "text": "new AC (violation)", "category": "functional", "verification": {"method": "unit_test", "detail": "new"}})'
expect_violation "case 7 (AC add)"

# === Case 8 (AC7b): AC remove → exit 2 ===
mutate_json 'data["acceptance_criteria"].pop()'
expect_violation "case 8 (AC remove)"

# === Case 9 (EC8): detail + text changed in the same AC → exit 2 ===
mutate_json 'data["acceptance_criteria"][0]["verification"]["detail"] = "amended detail"; data["acceptance_criteria"][0]["text"] = "also rewritten text (violation)"'
expect_violation "case 9 (detail + text combined change)"

# === Case 10 (AC-NEG6): goal / background / decisions / scope 整欄鎖定迴歸 ===
WHOLE_FIELD_MUTATIONS=(
  'data["goal"] = "rewritten goal (violation)"'
  'data["background"] = "rewritten background (violation)"'
  'data["decisions"] = ["D1", "D2 (violation)"]'
  'data["scope"] = ["thing A", "thing B (violation)"]'
)
for mutation in "${WHOLE_FIELD_MUTATIONS[@]}"; do
  mutate_json "$mutation"
  expect_violation "case 10 (whole-field LOCKED regression: $mutation)"
done

# === Case 11 (sanity): non-LOCKED field amendment → PASS ===
mutate_json 'data["technical_approach"] = "updated approach"'
expect_pass "case 11 (non-LOCKED technical_approach amendment)"

echo "PASS: DP-311 T5 locked-scope per-field granularity selftest (11 cases)"
