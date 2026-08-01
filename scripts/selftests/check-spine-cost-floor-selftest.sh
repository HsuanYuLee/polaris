#!/usr/bin/env bash
# Purpose: Verify the cost floor counts what the flow forces, and only that.
# Inputs: Hermetic inventory fixtures under mktemp.
# Outputs: PASS when a colour-change-sized code work sits at 2 forced files, a
#          docs-only work at 1, chosen artifacts do not count, exceeding the
#          floor fails, and a forced legacy-layer artifact fails even when the
#          count would fit.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-spine-cost-floor.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_inventory() {
  # Description: write an inventory fixture from a JSON literal.
  # Args: $1 = target path, $2 = JSON text
  printf '%s\n' "$2" > "$1"
}

assert_pass() {
  # Description: assert the check accepted the inventory.
  # Args: $1 = case name, $2 = inventory path
  bash "$CHECK" --inventory "$2" >/dev/null \
    || fail "$1 was rejected but should sit at the floor"
  echo "  ok  $1"
}

assert_marker() {
  # Description: assert the check refused with a specific marker.
  # Args: $1 = case name, $2 = marker, $3 = inventory path
  local out status=0
  out="$(bash "$CHECK" --inventory "$3" 2>&1)" || status=$?
  [[ "$status" -ne 0 ]] || fail "$1 was accepted but must be refused"
  grep -Fq "$2" <<<"$out" || fail "$1 did not emit $2; got: $out"
  echo "  ok  $1 -> $2"
}

# --- Case 1: a colour-change-sized code work sits at the floor ---------------
write_inventory "$WORK/colour-change.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/button-colour/living-doc.md", "forced": true,
     "reason": "活文件是 source 的記憶，不產生就沒有東西可以接手"},
    {"path": "src/components/Button.css", "forced": true,
     "reason": "工作本身就是這個 code 變更"}
  ]
}'
assert_pass "code work: living document + code = 2" "$WORK/colour-change.json"

# --- Case 2: a docs-only work sits at 1 -------------------------------------
write_inventory "$WORK/docs-only.json" '{
  "kind": "docs",
  "artifacts": [
    {"path": "specs/spine/wording-fix/living-doc.md", "forced": true,
     "reason": "活文件是 source 的記憶"}
  ]
}'
assert_pass "docs work: living document only = 1" "$WORK/docs-only.json"

# --- Case 3: files produced by choice are not part of the toll --------------
write_inventory "$WORK/chosen-extras.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "工作本身"},
    {"path": "src/thing.test.ts", "forced": false},
    {"path": "docs/adr/0007-why-thing.md", "forced": false},
    {"path": "scratch/notes.md", "forced": false}
  ]
}'
assert_pass "artifacts written by choice do not count" "$WORK/chosen-extras.json"

# --- Case 4: exceeding the floor fails --------------------------------------
write_inventory "$WORK/over-floor.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "工作本身"},
    {"path": "specs/spine/x/handoff.md", "forced": true,
     "reason": "流程要求交接檔才肯往下"}
  ]
}'
assert_marker "code work forced to 3 files" \
  POLARIS_SPINE_COST_FLOOR_EXCEEDED "$WORK/over-floor.json"

write_inventory "$WORK/docs-over-floor.json" '{
  "kind": "docs",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "specs/spine/x/summary.md", "forced": true, "reason": "流程要求摘要檔"}
  ]
}'
assert_marker "docs work forced to 2 files" \
  POLARIS_SPINE_COST_FLOOR_EXCEEDED "$WORK/docs-over-floor.json"

# --- Case 5: a forced legacy artifact fails even inside the count -----------
# The count fits (2), so a pure counter would let this through. The spine exists
# precisely so these layers stop being load-bearing.
for spec in \
  'specs/design-plans/DP-999-x/tasks/T1/index.md|task.md schema chain' \
  '.polaris/evidence/completion-gate/DP-999-T1-abc.json|completion-gate marker layer' \
  '.polaris/evidence/ac-verification/DP-999-V1-abc.json|ac-verification marker layer' \
  '.polaris/evidence/task-snapshot/DP-999-T1.json|task-snapshot marker layer' \
  'specs/design-plans/DP-999-x/artifacts/auto-pass/20260101-000000-ledger.json|ledger layer' \
  'specs/design-plans/DP-999-x/tasks/T1/verify-report.md|closeout chain'
do
  legacy_path="${spec%%|*}"
  python3 - "$WORK/legacy.json" "$legacy_path" <<'PY'
import json
import sys
out, legacy = sys.argv[1:3]
json.dump({
    "kind": "code",
    "artifacts": [
        {"path": legacy, "forced": True, "reason": "流程不產生它就走不完"},
        {"path": "src/thing.ts", "forced": True, "reason": "工作本身"},
    ],
}, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  assert_marker "forced legacy artifact: $legacy_path" \
    POLARIS_SPINE_COST_FLOOR_LEGACY_ARTIFACT_FORCED "$WORK/legacy.json"
done

# The same paths produced by choice are fine — the spine does not ban the old
# layers from existing, only from being required.
write_inventory "$WORK/legacy-optional.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "工作本身"},
    {"path": "specs/design-plans/DP-999-x/tasks/T1/index.md", "forced": false}
  ]
}'
assert_pass "legacy artifacts are allowed to exist, just not to be required" \
  "$WORK/legacy-optional.json"

# --- Case 6: a forced artifact must say why ---------------------------------
write_inventory "$WORK/unjustified.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "   "}
  ]
}'
assert_marker "forced artifact with no reason" \
  POLARIS_SPINE_COST_FLOOR_UNJUSTIFIED "$WORK/unjustified.json"

# --- Case 7: malformed input fails closed -----------------------------------
write_inventory "$WORK/bad-kind.json" '{"kind": "other", "artifacts": []}'
assert_marker "unknown kind" POLARIS_SPINE_COST_FLOOR_BAD_KIND "$WORK/bad-kind.json"

printf 'not json\n' > "$WORK/not-json.json"
assert_marker "unreadable inventory" \
  POLARIS_SPINE_COST_FLOOR_INVENTORY_MISSING "$WORK/not-json.json"

assert_marker "absent inventory" \
  POLARIS_SPINE_COST_FLOOR_INVENTORY_MISSING "$WORK/never-written.json"

echo "PASS: check-spine-cost-floor-selftest.sh"
