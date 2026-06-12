#!/usr/bin/env bash
# Purpose: DP-311 T2 hermetic selftest — auto-pass-finalize-ledger.sh 在 LOCKED 階段把
#          complete-eligible source 的 ledger terminal_status 推進成 complete，並驗證
#          mark-spec-implemented.sh parent / bare-DP callsite 的順序（翻 IMPLEMENTED 之前）。
# Inputs:  無 CLI args；於 mktemp fixture workspace 內執行，不觸碰真實 specs。
# Outputs: 逐 case PASS/FAIL 訊息；exit 0 全 PASS、exit 1 任一 case FAIL。
# Coverage: AC4（fresh / resume finalize）、AC-NF1（deterministic writer + parent-flip 前順序）、
#           AC-NEG4（non-complete terminal / 未解除 pause NOOP）、AC-NEG5（IMPLEMENTED /
#           archived idempotent NOOP、不碰 frozen archived legacy ledger）、EC6（多 ledger
#           只動最新）、EC7（task-level path 不觸發）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FINALIZE="$ROOT/scripts/auto-pass-finalize-ledger.sh"
MARK_SPEC="$ROOT/scripts/mark-spec-implemented.sh"

TMP="$(mktemp -d -t auto-pass-finalize-ledger-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "[selftest] FAIL: $1" >&2
  exit 1
}

# Description: 建立一個最小 source container fixture（index.md anchor + tasks dir）。
# Args:        $1 = container 絕對路徑；$2 = anchor frontmatter status；$3 = source id
# Side effects: 在 $1 下寫 index.md / refinement.md / refinement.json / tasks/
make_container() {
  local dir="$1" status="$2" source_id="$3"
  mkdir -p "$dir/tasks" "$dir/artifacts/auto-pass"
  cat > "$dir/index.md" <<MD
---
title: "$source_id fixture"
status: $status
---

# $source_id
MD
  printf '%s\n' '{"source": {"id": "'"$source_id"'"}}' > "$dir/refinement.json"
  printf '# %s refinement\n' "$source_id" > "$dir/refinement.md"
}

# Description: 寫一份最小 auto-pass ledger fixture。
# Args:        $1 = ledger 絕對路徑；$2 = container 絕對路徑；$3 = source id；
#              $4 = terminal_status JSON 值（null 或 "..."）；$5 = pause JSON 值（null 或 object）；
#              $6 = resumed_at JSON 值（null 或 "..."）
# Side effects: 寫入 $1
make_ledger() {
  local path="$1" container="$2" source_id="$3" terminal="$4" pause="$5" resumed="$6"
  cat > "$path" <<JSON
{
  "schema_version": "1",
  "source": {
    "type": "dp",
    "id": "$source_id",
    "container": "$container",
    "refinement_hash": "sha256:fixture"
  },
  "started_at": "2026-01-01T00:00:00+08:00",
  "resumed_at": $resumed,
  "terminal_status": $terminal,
  "pause": $pause,
  "stage_events": []
}
JSON
}

# Description: 斷言 ledger terminal_status 為指定值（用 python3 讀 JSON，不靠 grep 格式假設）。
# Args:        $1 = ledger path；$2 = 期望值（字串；"null" 表示 None）
# Side effects: 不符時 exit 1
assert_terminal() {
  local path="$1" expected="$2"
  python3 - "$path" "$expected" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1], encoding="utf-8"))
actual = ledger.get("terminal_status")
expected = None if sys.argv[2] == "null" else sys.argv[2]
if actual != expected:
    print(f"terminal_status mismatch: expected {expected!r}, got {actual!r}", file=sys.stderr)
    sys.exit(1)
PY
}

SPECS="$TMP/docs-manager/src/content/docs/specs"

# -----------------------------------------------------------------------------
# Case 1 — AC4 fresh path: LOCKED + null terminal → helper 寫 complete
# -----------------------------------------------------------------------------
C1="$SPECS/design-plans/DP-050-fresh"
make_container "$C1" LOCKED DP-050
L1="$C1/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L1" "$C1" DP-050 null null null
bash "$FINALIZE" --source-container "$C1" --source-id DP-050 \
  || fail "case1: helper exited non-zero on complete-eligible LOCKED source"
assert_terminal "$L1" complete || fail "case1: terminal_status not advanced to complete"

# Case 1b — idempotent rerun：已 complete → NOOP，byte-identical
cp "$L1" "$TMP/case1b.before"
bash "$FINALIZE" --source-container "$C1" --source-id DP-050 \
  || fail "case1b: idempotent rerun exited non-zero"
cmp -s "$L1" "$TMP/case1b.before" || fail "case1b: rerun mutated an already-complete ledger"

# -----------------------------------------------------------------------------
# Case 2 — AC4 resume path: resumed_at 非 null（paused→resume→complete）仍 finalize
# -----------------------------------------------------------------------------
C2="$SPECS/design-plans/DP-051-resume"
make_container "$C2" LOCKED DP-051
L2="$C2/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L2" "$C2" DP-051 null null '"2026-01-02T00:00:00+08:00"'
bash "$FINALIZE" --source-container "$C2" --source-id DP-051 \
  || fail "case2: helper exited non-zero on resume-complete path"
assert_terminal "$L2" complete || fail "case2: resume-path ledger not finalized"

# -----------------------------------------------------------------------------
# Case 3 — AC-NEG4: non-complete terminal 一律 NOOP 不改寫
# -----------------------------------------------------------------------------
idx=0
for terminal in loop_cap_reached blocked_by_gate_failure user_aborted paused_for_user_external_write; do
  idx=$((idx + 1))
  C3="$SPECS/design-plans/DP-06${idx}-noncomplete-${terminal}"
  make_container "$C3" LOCKED "DP-06${idx}"
  L3="$C3/artifacts/auto-pass/20260101-000000-ledger.json"
  make_ledger "$L3" "$C3" "DP-06${idx}" "\"$terminal\"" null null
  cp "$L3" "$TMP/case3-${terminal}.before"
  bash "$FINALIZE" --source-container "$C3" --source-id "DP-06${idx}" \
    || fail "case3(${terminal}): NOOP path exited non-zero"
  cmp -s "$L3" "$TMP/case3-${terminal}.before" \
    || fail "case3(${terminal}): non-complete terminal was rewritten (AC-NEG4 violation)"
done

# Case 3b — AC-NEG4: 未解除 pause（terminal null + pause set）→ NOOP
C3B="$SPECS/design-plans/DP-065-paused"
make_container "$C3B" LOCKED DP-065
L3B="$C3B/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L3B" "$C3B" DP-065 null \
  '{"kind": "session_handoff", "reason": "fixture", "created_at": "2026-01-01T00:00:00+08:00"}' null
cp "$L3B" "$TMP/case3b.before"
bash "$FINALIZE" --source-container "$C3B" --source-id DP-065 \
  || fail "case3b: unresolved-pause NOOP path exited non-zero"
cmp -s "$L3B" "$TMP/case3b.before" || fail "case3b: unresolved-pause ledger was rewritten"

# -----------------------------------------------------------------------------
# Case 4 — AC-NEG5: anchor 已 IMPLEMENTED（重跑 closeout）→ idempotent NOOP
# -----------------------------------------------------------------------------
C4="$SPECS/design-plans/DP-070-implemented"
make_container "$C4" IMPLEMENTED DP-070
L4="$C4/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L4" "$C4" DP-070 null null null
cp "$L4" "$TMP/case4.before"
bash "$FINALIZE" --source-container "$C4" --source-id DP-070 \
  || fail "case4: IMPLEMENTED rerun exited non-zero"
cmp -s "$L4" "$TMP/case4.before" || fail "case4: non-LOCKED anchor ledger was rewritten"

# Case 4b — AC-NEG5: archived container → NOOP，不碰 frozen archived legacy ledger
C4B="$SPECS/design-plans/archive/DP-308-frozen"
make_container "$C4B" IMPLEMENTED DP-308
L4B="$C4B/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L4B" "$C4B" DP-308 null \
  '{"kind": "paused_for_user_external_write", "reason": "legacy", "created_at": "2026-01-01T00:00:00+08:00"}' null
cp "$L4B" "$TMP/case4b.before"
bash "$FINALIZE" --source-container "$C4B" --source-id DP-308 \
  || fail "case4b: archived container path exited non-zero"
cmp -s "$L4B" "$TMP/case4b.before" || fail "case4b: frozen archived legacy ledger was touched"

# -----------------------------------------------------------------------------
# Case 5 — EC6: 同 container 多份 ledger → 只 finalize 最新，不誤改歷史 ledger
# -----------------------------------------------------------------------------
C5="$SPECS/design-plans/DP-080-multi"
make_container "$C5" LOCKED DP-080
L5_OLD="$C5/artifacts/auto-pass/20260101-000000-ledger.json"
L5_NEW="$C5/artifacts/auto-pass/20260202-000000-ledger.json"
make_ledger "$L5_OLD" "$C5" DP-080 '"user_aborted"' null null
make_ledger "$L5_NEW" "$C5" DP-080 null null null
cp "$L5_OLD" "$TMP/case5-old.before"
bash "$FINALIZE" --source-container "$C5" --source-id DP-080 \
  || fail "case5: multi-ledger finalize exited non-zero"
assert_terminal "$L5_NEW" complete || fail "case5: newest ledger not finalized"
cmp -s "$L5_OLD" "$TMP/case5-old.before" || fail "case5: historical ledger was mutated (EC6 violation)"

# -----------------------------------------------------------------------------
# Case 6 — fail-closed: 指定 --ledger 與 container 不符 → exit 2 + 結構化 marker
# -----------------------------------------------------------------------------
C6="$SPECS/design-plans/DP-090-mismatch"
make_container "$C6" LOCKED DP-090
L6="$C6/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L6" "$SPECS/design-plans/DP-050-fresh" DP-090 null null null
rc=0
bash "$FINALIZE" --source-container "$C6" --source-id DP-090 \
  >"$TMP/case6.out" 2>"$TMP/case6.err" || rc=$?
[ "$rc" -eq 2 ] || fail "case6: container mismatch did not exit 2 (rc=$rc)"
grep -q 'POLARIS_LEDGER_FINALIZE_CONTAINER_MISMATCH' "$TMP/case6.err" \
  || fail "case6: missing POLARIS_LEDGER_FINALIZE_CONTAINER_MISMATCH marker"

# Case 6b — fail-closed: ledger 非合法 JSON → exit 2 + 結構化 marker
C6B="$SPECS/design-plans/DP-091-corrupt"
make_container "$C6B" LOCKED DP-091
printf 'not-json\n' > "$C6B/artifacts/auto-pass/20260101-000000-ledger.json"
rc=0
bash "$FINALIZE" --source-container "$C6B" --source-id DP-091 \
  >"$TMP/case6b.out" 2>"$TMP/case6b.err" || rc=$?
[ "$rc" -eq 2 ] || fail "case6b: corrupt ledger did not exit 2 (rc=$rc)"
grep -q 'POLARIS_LEDGER_FINALIZE_INVALID_JSON' "$TMP/case6b.err" \
  || fail "case6b: missing POLARIS_LEDGER_FINALIZE_INVALID_JSON marker"

# Case 6c — 無 ledger（非 auto-pass source）→ NOOP exit 0，closeout 不被卡
C6C="$SPECS/design-plans/DP-092-no-ledger"
make_container "$C6C" LOCKED DP-092
rm -rf "$C6C/artifacts"
bash "$FINALIZE" --source-container "$C6C" --source-id DP-092 \
  || fail "case6c: missing-ledger NOOP path exited non-zero"

# -----------------------------------------------------------------------------
# Case 7 — callsite（bare-DP 分支，fresh path）：mark-spec-implemented 翻 parent 前 finalize
# -----------------------------------------------------------------------------
WS7="$TMP/ws7"
C7="$WS7/docs-manager/src/content/docs/specs/design-plans/DP-100-callsite"
make_container "$C7" LOCKED DP-100
cat > "$C7/tasks/T1.md" <<'MD'
---
status: IN_PROGRESS
---
# T1: fixture task (1 pt)

> Source: DP-100 | Task: DP-100-T1 | JIRA: N/A | Repo: polaris-framework
MD
L7="$C7/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L7" "$C7" DP-100 null null null
bash "$MARK_SPEC" DP-100 --workspace "$WS7" --no-auto-archive >/dev/null \
  || fail "case7: mark-spec-implemented bare-DP run failed"
assert_terminal "$L7" complete || fail "case7: bare-DP callsite did not finalize ledger"
grep -q '^status: IMPLEMENTED$' "$C7/index.md" || fail "case7: parent was not flipped IMPLEMENTED"

# -----------------------------------------------------------------------------
# Case 8 — AC-NF1 順序：finalize fail-closed 時 parent 不得翻 IMPLEMENTED
# -----------------------------------------------------------------------------
WS8="$TMP/ws8"
C8="$WS8/docs-manager/src/content/docs/specs/design-plans/DP-101-order"
make_container "$C8" LOCKED DP-101
printf 'not-json\n' > "$C8/artifacts/auto-pass/20260101-000000-ledger.json"
rc=0
bash "$MARK_SPEC" DP-101 --workspace "$WS8" --no-auto-archive \
  >"$TMP/case8.out" 2>"$TMP/case8.err" || rc=$?
[ "$rc" -ne 0 ] || fail "case8: mark-spec-implemented succeeded despite finalize fail-closed"
grep -q '^status: LOCKED$' "$C8/index.md" \
  || fail "case8: parent was flipped before finalize gate (ordering violation, AC-NF1)"

# -----------------------------------------------------------------------------
# Case 9 — EC7: task-level path 不觸發 finalize
# -----------------------------------------------------------------------------
WS9="$TMP/ws9"
C9="$WS9/docs-manager/src/content/docs/specs/design-plans/DP-102-tasklevel"
make_container "$C9" LOCKED DP-102
cat > "$C9/tasks/T1.md" <<'MD'
---
status: IN_PROGRESS
---
# T1: fixture task (1 pt)

> Source: DP-102 | Task: DP-102-T1 | JIRA: N/A | Repo: polaris-framework
MD
L9="$C9/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L9" "$C9" DP-102 null null null
cp "$L9" "$TMP/case9.before"
bash "$MARK_SPEC" DP-102-T1 --workspace "$WS9" --no-auto-archive >/dev/null \
  || fail "case9: task-level mark-spec-implemented run failed"
cmp -s "$L9" "$TMP/case9.before" \
  || fail "case9: task-level path triggered ledger finalize (EC7 violation)"
[ -f "$C9/tasks/pr-release/T1.md" ] || fail "case9: task-level move-first regression"

# -----------------------------------------------------------------------------
# Case 10 — callsite（epic / parent 分支）：JIRA Epic-backed source 同樣 finalize
# -----------------------------------------------------------------------------
WS10="$TMP/ws10"
C10="$WS10/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001"
mkdir -p "$C10/artifacts/auto-pass"
cat > "$C10/refinement.md" <<'MD'
---
title: "EPIC-001"
status: LOCKED
---

# EPIC-001
MD
L10="$C10/artifacts/auto-pass/20260101-000000-ledger.json"
make_ledger "$L10" "$C10" EPIC-001 null null null
bash "$MARK_SPEC" EPIC-001 --workspace "$WS10" --no-auto-archive >/dev/null \
  || fail "case10: epic-branch mark-spec-implemented run failed"
assert_terminal "$L10" complete || fail "case10: epic-branch callsite did not finalize ledger"
grep -q '^status: IMPLEMENTED$' "$C10/refinement.md" || fail "case10: epic parent not flipped"

echo "PASS: auto-pass finalize ledger selftest"
