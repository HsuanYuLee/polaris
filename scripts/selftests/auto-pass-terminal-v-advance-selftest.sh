#!/usr/bin/env bash
# Purpose: DP-311 T1 selftest — auto-pass-runner Terminal Complete Sequence must
#          advance PASS + human_disposition=passed required V work items through
#          mark-spec-implemented (move → tasks/pr-release/ + status IMPLEMENTED)
#          before declaring terminal=complete, and fail-closed when any required
#          V work item is not at the canonical terminal (pr-release/ +
#          IMPLEMENTED + ac_verification PASS).
# Inputs:  none (hermetic mktemp fixtures; uses repo scripts in-place).
# Outputs: PASS/FAIL lines per case; exit 0 only when all cases pass.
#
# Covered AC (DP-311):
#   AC1     — PASS + passed V advanced to canonical terminal before complete.
#   AC2     — V not at canonical terminal → terminal complete blocked
#             (fail-closed; ac-verification marker alone is not enough).
#   AC-NEG1 — FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV V never advanced.
#   AC-NEG2 — T (implementation) task lifecycle untouched by the sequence.
#   AC-NEG3 — advance goes through existing mark-spec-implemented writer; the
#             canonical terminal contract matches close-parent-spec-if-complete.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
TMP="$(mktemp -d -t auto-pass-terminal-v-advance.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
HEAD_SHA="abc1234"
DP_DIR="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-901-fixture"
TASKS_DIR="$DP_DIR/tasks"
EVIDENCE_DIR="$TMP/.polaris/evidence/ac-verification"

fail() {
  echo "FAIL: $1" >&2
  FAILED=1
}

ok() {
  echo "PASS: $1"
}

# Description: write the DP-901 source container fixture (primary doc + refinement pair).
# Args:        none (uses globals)
# Side effects: creates/overwrites files under $DP_DIR
write_container() {
  mkdir -p "$DP_DIR" "$EVIDENCE_DIR"
  cat >"$DP_DIR/index.md" <<'MD'
---
title: "DP-901 fixture"
description: "terminal V advance selftest source fixture"
status: LOCKED
---

# DP-901 fixture
MD
  cat >"$DP_DIR/refinement.md" <<'MD'
---
title: "DP-901 refinement"
description: "terminal V advance selftest refinement"
---

## Scope

fixture
MD
  cat >"$DP_DIR/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-901"},
  "modules": [],
  "acceptance_criteria": []
}
JSON
}

# Description: reset tasks/ to a baseline with pr-release T1 (IMPLEMENTED) and an
#              untouched active T3.md, then write V1 with the given
#              ac_verification status / human_disposition.
# Args:        $1 = ac_verification status (PASS/FAIL/...; "NONE" omits block)
#              $2 = human_disposition (may be empty; only written when non-empty)
# Side effects: recreates $TASKS_DIR content
write_tasks_fixture() {
  local ac_status="$1" disposition="${2:-}"
  rm -rf "$TASKS_DIR"
  mkdir -p "$TASKS_DIR/V1" "$TASKS_DIR/pr-release"
  cat >"$TASKS_DIR/pr-release/T1.md" <<'MD'
---
title: "DP-901 T1"
status: IMPLEMENTED
task_kind: T
---

# T1 done fixture
MD
  cat >"$TASKS_DIR/T3.md" <<'MD'
---
title: "DP-901 T3"
status: IN_PROGRESS
task_kind: T
---

# T3 active fixture — terminal V sequence must not touch T tasks
MD
  {
    printf '%s\n' '---'
    printf '%s\n' 'title: "DP-901 V1: fixture verification task"'
    printf '%s\n' 'description: "terminal V advance selftest V work item"'
    printf '%s\n' 'status: IN_PROGRESS'
    printf '%s\n' 'task_kind: V'
    printf '%s\n' 'depends_on: []'
    if [[ "$ac_status" != "NONE" ]]; then
      printf '%s\n' 'ac_verification:'
      printf '%s\n' "  status: ${ac_status}"
      if [[ -n "$disposition" ]]; then
        printf '%s\n' "  human_disposition: ${disposition}"
      fi
      printf '%s\n' '  last_run_at: 2026-06-11T00:00:00Z'
      printf '%s\n' '  ac_total: 1'
      printf '%s\n' '  ac_pass: 1'
      printf '%s\n' '  ac_fail: 0'
      printf '%s\n' '  ac_manual_required: 0'
      printf '%s\n' '  ac_uncertain: 0'
    fi
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '# V1 fixture'
  } >"$TASKS_DIR/V1/index.md"
}

# Description: write the head-bound ac-verification PASS marker for DP-901-V1 so
#              the probe maps verify-AC to terminal complete.
# Args:        $1 = marker status (default PASS)
# Side effects: writes $EVIDENCE_DIR/DP-901-V1-$HEAD_SHA.json
write_pass_marker() {
  local status="${1:-PASS}"
  python3 - "$EVIDENCE_DIR/DP-901-V1-${HEAD_SHA}.json" "$status" <<'PY'
import json, sys
from pathlib import Path
path, status = sys.argv[1:3]
Path(path).write_text(json.dumps({
    "schema_version": 1,
    "marker_kind": "ac_verification",
    "writer": "selftest",
    "owning_skill": "selftest",
    "source_id": "DP-901",
    "work_item_id": "DP-901-V1",
    "status": status,
    "freshness": {"head_sha": "abc1234"},
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

run_runner() {
  bash "$RUNNER" --repo "$TMP" --stage verify-AC --source-id DP-901 \
    --work-item-id DP-901-V1 --head-sha "$HEAD_SHA" "$@"
}

# Description: extract one field from runner JSON on stdin file.
# Args:        $1 = output file, $2 = field name
# Side effects: none
json_field() {
  python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print('null' if v is None else v)" "$1" "$2"
}

write_container

# ── Case 1 (AC1): PASS + passed V advanced, terminal complete declared ───────
write_tasks_fixture PASS passed
write_pass_marker PASS
out="$TMP/out1.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case1: expected terminal_status=complete, got $(json_field "$out" terminal_status)"
[[ ! -d "$TASKS_DIR/V1" ]] || fail "case1: active tasks/V1 was not advanced"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case1: pr-release/V1/index.md missing"
grep -q '^status: IMPLEMENTED$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: pr-release V1 status not IMPLEMENTED"
grep -q '^  status: PASS$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: ac_verification block not preserved"
grep -q '^  human_disposition: passed$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: human_disposition not preserved"
[[ "$FAILED" -eq 0 ]] && ok "case1 AC1 PASS+passed V advanced to canonical terminal"

# ── Case 2 (AC-NEG2): T task lifecycle untouched by the sequence ─────────────
grep -q '^status: IN_PROGRESS$' "$TASKS_DIR/T3.md" 2>/dev/null || fail "case2: active T3.md was mutated"
[[ -f "$TASKS_DIR/T3.md" ]] || fail "case2: active T3.md was moved"
grep -q '^status: IMPLEMENTED$' "$TASKS_DIR/pr-release/T1.md" 2>/dev/null || fail "case2: pr-release T1.md was mutated"
[[ "$FAILED" -eq 0 ]] && ok "case2 AC-NEG2 T task lifecycle untouched"

# ── Case 3 (resume-complete): rerun after advance stays complete (idempotent) ─
out="$TMP/out3.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case3: resume-complete rerun expected complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case3: pr-release V1 missing after rerun"
[[ "$FAILED" -eq 0 ]] && ok "case3 resume-complete rerun idempotent"

# ── Case 4 (AC2): V not at canonical terminal → fail-closed, marker not enough ─
write_tasks_fixture IN_PROGRESS ""
write_pass_marker PASS
out="$TMP/out4.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case4: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ "$(json_field "$out" next_action)" == "blocked" ]] || fail "case4: expected next_action=blocked"
[[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case4: V1 must stay in tasks/"
[[ ! -e "$TASKS_DIR/pr-release/V1" ]] || fail "case4: V1 must not be advanced"
[[ "$FAILED" -eq 0 ]] && ok "case4 AC2 fail-closed when V not at canonical terminal"

# ── Case 5 (AC2): missing ac_verification block entirely → fail-closed ───────
write_tasks_fixture NONE ""
write_pass_marker PASS
out="$TMP/out5.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case5: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case5: V1 must stay in tasks/"
[[ "$FAILED" -eq 0 ]] && ok "case5 AC2 fail-closed when ac_verification block missing"

# ── Case 6 (AC-NEG1): non-PASS verdicts never advanced ───────────────────────
for verdict in FAIL MANUAL_REQUIRED UNCERTAIN BLOCKED_ENV; do
  write_tasks_fixture "$verdict" passed
  write_pass_marker PASS
  out="$TMP/out6-${verdict}.json"
  run_runner >"$out"
  [[ "$(json_field "$out" terminal_status)" != "complete" ]] || fail "case6/${verdict}: terminal complete must not be declared"
  [[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case6/${verdict}: V1 must stay in tasks/"
  [[ ! -e "$TASKS_DIR/pr-release/V1" ]] || fail "case6/${verdict}: V1 must not be advanced"
done
[[ "$FAILED" -eq 0 ]] && ok "case6 AC-NEG1 non-PASS verdicts not advanced"

# ── Case 7: PASS without human_disposition=passed → not advanced, fail-closed ─
write_tasks_fixture PASS rejected
write_pass_marker PASS
out="$TMP/out7.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case7: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case7: V1 must stay in tasks/"
[[ "$FAILED" -eq 0 ]] && ok "case7 PASS+rejected not auto-advanced"

# ── Case 8: stale pr-release V (ac_verification not PASS) → fail-closed ──────
write_tasks_fixture PASS passed
rm -rf "$TASKS_DIR/V1"
mkdir -p "$TASKS_DIR/pr-release/V1"
cat >"$TASKS_DIR/pr-release/V1/index.md" <<'MD'
---
title: "DP-901 V1: stale pr-release fixture"
status: IMPLEMENTED
task_kind: V
ac_verification:
  status: FAIL
---

# V1 stale fixture
MD
write_pass_marker PASS
out="$TMP/out8.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case8: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ "$FAILED" -eq 0 ]] && ok "case8 stale pr-release V (ac_verification FAIL) fail-closed"

# ── Case 9: ABANDONED V carve-out does not block, eligible sibling advances ──
write_tasks_fixture PASS passed
mkdir -p "$TASKS_DIR/V2"
cat >"$TASKS_DIR/V2/index.md" <<'MD'
---
title: "DP-901 V2: abandoned fixture"
status: ABANDONED
task_kind: V
---

# V2 abandoned fixture
MD
write_pass_marker PASS
out="$TMP/out9.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case9: ABANDONED V must not block complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/V2/index.md" ]] || fail "case9: ABANDONED V2 must stay in tasks/"
grep -q '^status: ABANDONED$' "$TASKS_DIR/V2/index.md" 2>/dev/null || fail "case9: ABANDONED V2 status must be preserved"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case9: eligible V1 not advanced"
[[ "$FAILED" -eq 0 ]] && ok "case9 ABANDONED V carve-out preserved"

# ── Case 10: container without tasks/ keeps existing complete behavior ───────
rm -rf "$TASKS_DIR"
write_pass_marker PASS
out="$TMP/out10.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case10: no-tasks container regression, got $(json_field "$out" terminal_status)"
[[ "$FAILED" -eq 0 ]] && ok "case10 no-tasks container keeps terminal complete (regression)"

if [[ "$FAILED" -ne 0 ]]; then
  echo "[selftest] FAIL: auto-pass-terminal-v-advance" >&2
  exit 1
fi
echo "[selftest] PASS: auto-pass-terminal-v-advance"
