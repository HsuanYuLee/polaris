#!/usr/bin/env bash
# Purpose: Verify the check refuses a flow still load-bearing on a legacy layer,
#          and refuses nothing on the strength of a count.
# Inputs: Hermetic inventory fixtures under mktemp.
# Outputs: PASS when clean inventories are accepted at any forced count, a forced
#          legacy-layer artifact is refused, and a forced artifact with no stated
#          reason is refused.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-spine-legacy-layers.sh"
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
    || fail "$1 was rejected but has no legacy layer in it"
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

# --- Case 4: the count is never the reason for a refusal ---------------------
# 這兩個 fixture 以前是紅的（門檻 2）。它們現在必須是綠的：門檻設在一個由流程自己寫死的
# 常數上，對每一張真單都紅，而且沒有人呼叫它所以沒有人知道。留著改名字等於把那個錯誤
# 換個標記繼續斷言一次。
write_inventory "$WORK/three-forced.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "issues/ns/X/index.md", "forced": true, "reason": "活文件"},
    {"path": "issues/ns/X/.spine/loop-state.json", "forced": true, "reason": "輪次"},
    {"path": "issues/ns/X/.spine/measurement-ledger.json", "forced": true, "reason": "量測登錄"}
  ]
}'
assert_pass "three forced files is not a reason to refuse" "$WORK/three-forced.json"

write_inventory "$WORK/docs-two-forced.json" '{
  "kind": "docs",
  "artifacts": [
    {"path": "issues/ns/X/index.md", "forced": true, "reason": "活文件"},
    {"path": "issues/ns/X/.spine/loop-state.json", "forced": true, "reason": "輪次"}
  ]
}'
assert_pass "docs work above the old floor is not refused" "$WORK/docs-two-forced.json"

# --- Case 5: a forced legacy artifact is refused ----------------------------
# This is the whole job now: which layers are load-bearing, not how many files.
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
    POLARIS_SPINE_LEGACY_ARTIFACT_FORCED "$WORK/legacy.json"
done

# 舊層「自願產生」也要被擋。這個案例以前斷言的是相反的事（forced=false 就放行），而那個
# 版本讓整道檢查不可能變紅：枚舉器只會對 index.md、.spine/*.json 與 .changeset/*.md 標
# forced=true，所以沒有任何一條舊層路徑到得了判定。一道紅不了的檢查比沒有人呼叫的更糟——
# 它會回綠，而那個綠什麼都不代表。
write_inventory "$WORK/legacy-optional.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "工作本身"},
    {"path": "specs/design-plans/DP-999-x/tasks/T1/index.md", "forced": false}
  ]
}'
assert_marker "a legacy artifact produced by choice is still the old machine running" \
  POLARIS_SPINE_LEGACY_ARTIFACT_FORCED "$WORK/legacy-optional.json"

# The spine's own state is not a legacy layer. This case exists because the
# legacy list once caught `.spine/measurement-ledger.json` by name alone, and
# nothing noticed until a real source was measured: every fixture here used the
# old layer's real path, so the check and its tests agreed with each other and
# with nothing else.
write_inventory "$WORK/spine-own-state.json" '{
  "kind": "docs",
  "artifacts": [
    {"path": "issues/DP-999-x/.spine/measurement-ledger.json", "forced": true, "reason": "judge 不承認沒登錄過的量測命令"}
  ]
}'
assert_pass "the spine's own measurement ledger is not a legacy layer" \
  "$WORK/spine-own-state.json"

# --- Case 6: a forced artifact must say why ---------------------------------
write_inventory "$WORK/unjustified.json" '{
  "kind": "code",
  "artifacts": [
    {"path": "specs/spine/x/living-doc.md", "forced": true, "reason": "活文件"},
    {"path": "src/thing.ts", "forced": true, "reason": "   "}
  ]
}'
assert_marker "forced artifact with no reason" \
  POLARIS_SPINE_LEGACY_UNJUSTIFIED "$WORK/unjustified.json"

# --- Case 7: malformed input fails closed -----------------------------------
write_inventory "$WORK/bad-kind.json" '{"kind": "other", "artifacts": []}'
assert_marker "unknown kind" POLARIS_SPINE_LEGACY_BAD_KIND "$WORK/bad-kind.json"

printf 'not json\n' > "$WORK/not-json.json"
assert_marker "unreadable inventory" \
  POLARIS_SPINE_LEGACY_INVENTORY_MISSING "$WORK/not-json.json"

assert_marker "absent inventory" \
  POLARIS_SPINE_LEGACY_INVENTORY_MISSING "$WORK/never-written.json"

echo "PASS: check-spine-legacy-layers-selftest.sh"
