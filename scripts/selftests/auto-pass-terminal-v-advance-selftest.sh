#!/usr/bin/env bash
# Purpose: DP-311 T1 + DP-317 T1 selftest — auto-pass-runner Terminal Complete
#          Sequence must advance required V work items (DP-311) AND required
#          implementation T work items (DP-317) through mark-spec-implemented
#          (move → tasks/pr-release/ + status IMPLEMENTED) before declaring
#          terminal=complete, and fail-closed when any required work item is not
#          at its canonical terminal.
# Inputs:  none (hermetic mktemp fixtures; uses repo scripts in-place).
# Outputs: PASS/FAIL lines per case; exit 0 only when all cases pass.
#
# Covered AC (DP-311 V-gate):
#   AC1     — PASS + passed V advanced to canonical terminal before complete.
#   AC2     — V not at canonical terminal → terminal complete blocked
#             (fail-closed; ac-verification marker alone is not enough).
#   AC-NEG1 — FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV V never advanced.
#   AC-NEG2 — T (implementation) task lifecycle untouched by the V sequence.
#   AC-NEG3 — advance goes through existing mark-spec-implemented writer; the
#             canonical terminal contract matches close-parent-spec-if-complete.
#
# Covered AC (DP-317 T-gate — symmetric implementation T assert):
#   AC1     — required implementation T with completion-gate marker PASS at head
#             but still in tasks/ is advanced to pr-release/ + IMPLEMENTED before
#             complete (fresh + resume-complete dual path).
#   AC2     — reuses close-parent canonical reader (pr-release/+IMPLEMENTED) and
#             single mark-spec-implemented writer; no second classifier.
#   AC3     — fresh-complete and resume-complete share the same T-assert gate.
#   AC-NEG1 — task_shape ∈ {audit, confirmation} carve-out neither blocked nor
#             advanced (DP-262 no-PR path).
#   AC-NEG2 — ABANDONED T task left in place, does not block complete.
#   AC-NEG3 — existing V-task Terminal Complete Sequence behaviour unchanged.
#   EC2     — required implementation T with missing / non-PASS completion-gate
#             marker → fail-closed blocked (no advance, no evidence).
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
  # DP-360 T7: T-advance eligibility now reads each task.md's own
  # deliverable.verification block (no shared marker dir to reset); rm -rf
  # "$TASKS_DIR" already makes each case hermetic.
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
task_shape: audit
---

# T3 active fixture — audit carve-out: terminal sequence must not touch it
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

# Description: DP-360 T7 — write a TORN-DOWN head-sha ac-verification marker for
#              DP-901-V1. The runner/probe must IGNORE it (the V-task
#              ac_verification frontmatter block is the sole authority). Used only
#              by the stray-marker-ignored cases to prove no marker rescue.
# Args:        $1 = marker status (default PASS)
# Side effects: writes $EVIDENCE_DIR/DP-901-V1-$HEAD_SHA.json
write_stray_marker() {
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

# Description: append an active implementation T work item under tasks/, with the
#              given stem, optional task_shape, and optional DP-360 deliverable
#              verification status. DP-360 T7: the T-advance advance-eligibility
#              now binds to the task.md deliverable.verification.status block (the
#              head-sha completion_gate marker is retired), so the verification
#              status is written into the task.md itself, not a marker file.
# Args:        $1 = T stem (e.g. T5), $2 = status (default IN_PROGRESS),
#              $3 = task_shape (optional; omitted when empty),
#              $4 = deliverable.verification.status (optional; "" omits the block)
# Side effects: writes $TASKS_DIR/{stem}/index.md (folder-native)
write_active_t_task() {
  local stem="$1" status="${2:-IN_PROGRESS}" task_shape="${3:-}" vstatus="${4:-}"
  mkdir -p "$TASKS_DIR/$stem"
  {
    printf '%s\n' '---'
    printf '%s\n' "title: \"DP-901 ${stem}: fixture implementation task\""
    printf '%s\n' 'description: "terminal T advance selftest implementation work item"'
    printf '%s\n' "status: ${status}"
    printf '%s\n' 'task_kind: T'
    if [[ -n "$task_shape" ]]; then
      printf '%s\n' "task_shape: ${task_shape}"
    fi
    if [[ -n "$vstatus" ]]; then
      printf '%s\n' 'deliverable:'
      printf '%s\n' '  head_sha: abc1234'
      printf '%s\n' '  verification:'
      printf '%s\n' "    status: ${vstatus}"
      printf '%s\n' '    ac_counts:'
      printf '%s\n' '      ac_total: 1'
      printf '%s\n' '      ac_pass: 1'
      printf '%s\n' '      ac_fail: 0'
      printf '%s\n' '      ac_manual_required: 0'
      printf '%s\n' '      ac_uncertain: 0'
    fi
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' "# ${stem} fixture"
  } >"$TASKS_DIR/$stem/index.md"
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
# DP-360 T7: no marker — the runner reads the V-task ac_verification block.
write_tasks_fixture PASS passed
out="$TMP/out1.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case1: expected terminal_status=complete, got $(json_field "$out" terminal_status)"
[[ ! -d "$TASKS_DIR/V1" ]] || fail "case1: active tasks/V1 was not advanced"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case1: pr-release/V1/index.md missing"
grep -q '^status: IMPLEMENTED$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: pr-release V1 status not IMPLEMENTED"
grep -q '^  status: PASS$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: ac_verification block not preserved"
grep -q '^  human_disposition: passed$' "$TASKS_DIR/pr-release/V1/index.md" 2>/dev/null || fail "case1: human_disposition not preserved"
[[ "$FAILED" -eq 0 ]] && ok "case1 AC1 PASS+passed V advanced to canonical terminal"

# ── Case 2 (AC-NEG1 carve-out): audit T task lifecycle untouched ─────────────
grep -q '^status: IN_PROGRESS$' "$TASKS_DIR/T3.md" 2>/dev/null || fail "case2: active audit T3.md was mutated"
[[ -f "$TASKS_DIR/T3.md" ]] || fail "case2: active audit T3.md was moved"
grep -q '^status: IMPLEMENTED$' "$TASKS_DIR/pr-release/T1.md" 2>/dev/null || fail "case2: pr-release T1.md was mutated"
[[ "$FAILED" -eq 0 ]] && ok "case2 audit-shape T task carve-out untouched"

# ── Case 3 (resume-complete): rerun after advance stays complete (idempotent) ─
out="$TMP/out3.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case3: resume-complete rerun expected complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case3: pr-release V1 missing after rerun"
[[ "$FAILED" -eq 0 ]] && ok "case3 resume-complete rerun idempotent"

# ── Case 4 (AC2): V not at canonical terminal → fail-closed, marker not enough ─
write_tasks_fixture IN_PROGRESS ""
write_stray_marker PASS   # AC-NEG2: stray marker must not rescue
out="$TMP/out4.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case4: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ "$(json_field "$out" next_action)" == "blocked" ]] || fail "case4: expected next_action=blocked"
[[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case4: V1 must stay in tasks/"
[[ ! -e "$TASKS_DIR/pr-release/V1" ]] || fail "case4: V1 must not be advanced"
[[ "$FAILED" -eq 0 ]] && ok "case4 AC2 fail-closed when V not at canonical terminal"

# ── Case 5 (AC2): missing ac_verification block entirely → fail-closed ───────
write_tasks_fixture NONE ""
write_stray_marker PASS   # AC-NEG2: stray marker must not rescue
out="$TMP/out5.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case5: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case5: V1 must stay in tasks/"
[[ "$FAILED" -eq 0 ]] && ok "case5 AC2 fail-closed when ac_verification block missing"

# ── Case 6 (AC-NEG1): non-PASS verdicts never advanced ───────────────────────
for verdict in FAIL MANUAL_REQUIRED UNCERTAIN BLOCKED_ENV; do
  write_tasks_fixture "$verdict" passed
  write_stray_marker PASS   # AC-NEG2: stray marker must not rescue non-PASS verdicts
  out="$TMP/out6-${verdict}.json"
  run_runner >"$out"
  [[ "$(json_field "$out" terminal_status)" != "complete" ]] || fail "case6/${verdict}: terminal complete must not be declared"
  [[ -f "$TASKS_DIR/V1/index.md" ]] || fail "case6/${verdict}: V1 must stay in tasks/"
  [[ ! -e "$TASKS_DIR/pr-release/V1" ]] || fail "case6/${verdict}: V1 must not be advanced"
done
[[ "$FAILED" -eq 0 ]] && ok "case6 AC-NEG1 non-PASS verdicts not advanced"

# ── Case 7: PASS without human_disposition=passed → not advanced, fail-closed ─
write_tasks_fixture PASS rejected
write_stray_marker PASS   # AC-NEG2: stray marker must not rescue PASS+rejected
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
write_stray_marker PASS   # AC-NEG2: stray marker must not rescue stale pr-release V
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
out="$TMP/out9.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case9: ABANDONED V must not block complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/V2/index.md" ]] || fail "case9: ABANDONED V2 must stay in tasks/"
grep -q '^status: ABANDONED$' "$TASKS_DIR/V2/index.md" 2>/dev/null || fail "case9: ABANDONED V2 status must be preserved"
[[ -f "$TASKS_DIR/pr-release/V1/index.md" ]] || fail "case9: eligible V1 not advanced"
[[ "$FAILED" -eq 0 ]] && ok "case9 ABANDONED V carve-out preserved"

# ── Case 10 (DP-360 T7): verify-AC for a work item with no resolvable V-task →
#    fail-closed blocked. Pre-DP-360 this "no-tasks container" completed via the
#    standalone head-sha ac-verification marker; with that marker torn down there
#    is no ac_verification authority to read (AC3: read the V-task block, no
#    marker; AC-NEG2: no marker dual-write). A stray marker must NOT rescue. ────
rm -rf "$TASKS_DIR"
write_stray_marker PASS   # stray torn-down marker — must be ignored
out="$TMP/out10.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case10: no-V-task verify-AC must fail-closed (stray marker ignored), got $(json_field "$out" terminal_status)"
[[ "$FAILED" -eq 0 ]] && ok "case10 no-V-task verify-AC fail-closed (stray ac-verification marker ignored)"

# ── DP-317 T-gate: symmetric implementation T assert ─────────────────────────

# ── Case 11 (DP-317 AC1 / DP-360 T7): required implementation T with PASS
#    deliverable.verification.status block but still in tasks/ → advanced to
#    pr-release/ + IMPLEMENTED (reads task.md block, no marker) ─────────────────
write_tasks_fixture PASS passed          # V1 eligible (advanced first)
write_active_t_task T5 IN_PROGRESS "" PASS   # implementation T with PASS block
out="$TMP/out11.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case11: expected complete, got $(json_field "$out" terminal_status)"
[[ ! -d "$TASKS_DIR/T5" ]] || fail "case11: active tasks/T5 was not advanced"
[[ -f "$TASKS_DIR/pr-release/T5/index.md" ]] || fail "case11: pr-release/T5/index.md missing"
grep -q '^status: IMPLEMENTED$' "$TASKS_DIR/pr-release/T5/index.md" 2>/dev/null || fail "case11: pr-release T5 status not IMPLEMENTED"
[[ "$FAILED" -eq 0 ]] && ok "case11 DP-317 AC1 PASS-marker implementation T advanced to canonical terminal"

# ── Case 12 (DP-317 AC3 + resume-complete): rerun stays complete (idempotent) ─
out="$TMP/out12.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case12: resume-complete rerun expected complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/pr-release/T5/index.md" ]] || fail "case12: pr-release T5 missing after rerun"
[[ "$FAILED" -eq 0 ]] && ok "case12 DP-317 AC3 fresh + resume-complete share T-assert gate (idempotent)"

# ── Case 13 (DP-317 EC2 / DP-360 T7): required implementation T with NO
#    deliverable.verification block → fail-closed blocked (no advance) ──────────
write_tasks_fixture PASS passed
write_active_t_task T5 IN_PROGRESS "" ""    # no deliverable.verification block
out="$TMP/out13.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case13: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ "$(json_field "$out" next_action)" == "blocked" ]] || fail "case13: expected next_action=blocked"
[[ -f "$TASKS_DIR/T5/index.md" ]] || fail "case13: T5 must stay in tasks/ when blocked"
[[ ! -e "$TASKS_DIR/pr-release/T5" ]] || fail "case13: T5 must not be advanced without PASS block"
[[ "$FAILED" -eq 0 ]] && ok "case13 DP-317 EC2 missing deliverable.verification block fail-closed"

# ── Case 14 (DP-317 AC1 adversarial / DP-360 T7): deliverable.verification.status
#    non-PASS → no advance, fail-closed ─────────────────────────────────────────
write_tasks_fixture PASS passed
write_active_t_task T5 IN_PROGRESS "" FAIL    # FAIL deliverable.verification block
out="$TMP/out14.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "blocked_by_gate_failure" ]] || fail "case14: expected blocked_by_gate_failure, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/T5/index.md" ]] || fail "case14: T5 must stay in tasks/ for non-PASS block"
[[ ! -e "$TASKS_DIR/pr-release/T5" ]] || fail "case14: T5 must not be advanced for non-PASS block"
[[ "$FAILED" -eq 0 ]] && ok "case14 DP-317 non-PASS deliverable.verification block not advanced"

# ── Case 15 (DP-317 AC-NEG1): audit / confirmation carve-out neither blocked
#    nor advanced, even without a completion-gate marker ───────────────────────
for shape in audit confirmation; do
  write_tasks_fixture PASS passed
  write_active_t_task T6 IN_PROGRESS "$shape"   # carve-out: no PR / no pr-release
  out="$TMP/out15-${shape}.json"
  run_runner >"$out"
  [[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case15/${shape}: carve-out must not block complete, got $(json_field "$out" terminal_status)"
  [[ -f "$TASKS_DIR/T6/index.md" ]] || fail "case15/${shape}: carve-out T6 must stay in tasks/"
  [[ ! -e "$TASKS_DIR/pr-release/T6" ]] || fail "case15/${shape}: carve-out T6 must not be advanced"
done
[[ "$FAILED" -eq 0 ]] && ok "case15 DP-317 AC-NEG1 audit/confirmation carve-out neither blocked nor advanced"

# ── Case 16 (DP-317 AC-NEG2): ABANDONED T task left in place, does not block ──
write_tasks_fixture PASS passed
write_active_t_task T7 ABANDONED ""
out="$TMP/out16.json"
run_runner >"$out"
[[ "$(json_field "$out" terminal_status)" == "complete" ]] || fail "case16: ABANDONED T must not block complete, got $(json_field "$out" terminal_status)"
[[ -f "$TASKS_DIR/T7/index.md" ]] || fail "case16: ABANDONED T7 must stay in tasks/"
grep -q '^status: ABANDONED$' "$TASKS_DIR/T7/index.md" 2>/dev/null || fail "case16: ABANDONED T7 status must be preserved"
[[ ! -e "$TASKS_DIR/pr-release/T7" ]] || fail "case16: ABANDONED T7 must not be advanced"
[[ "$FAILED" -eq 0 ]] && ok "case16 DP-317 AC-NEG2 ABANDONED T carve-out preserved"

if [[ "$FAILED" -ne 0 ]]; then
  echo "[selftest] FAIL: auto-pass-terminal-v-advance" >&2
  exit 1
fi
echo "[selftest] PASS: auto-pass-terminal-v-advance"
