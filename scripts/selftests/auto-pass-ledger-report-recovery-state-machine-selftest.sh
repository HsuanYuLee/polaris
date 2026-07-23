#!/usr/bin/env bash
# Purpose: DP-417 T3 — consolidated auto-pass ledger/report RECOVERY state-machine
#          selftest. Drives ONE canonical fixture source (LOCKED container +
#          refinement + V task.md deliverable blocks) through EACH recovery
#          transition — blocked_by_gate_failure, resume (session_handoff),
#          continue, revision (engineering_revision_rounds), head-rebind — and
#          asserts the REAL gates:
#            (a) each transition's ledger/report/resume/consume verdict is
#                DETERMINISTIC: same input → same exit code + same next_action /
#                marker (AC3);
#            (b) after review, revision / head-rebind only reach `complete` once
#                the PR-visible delivery evidence (task.md deliverable head_sha +
#                verification.status=PASS, published non-draft PR ownership) is
#                satisfied — a stale/missing/draft binding fails closed (AC6);
#            (c) an ACTIVE source missing a required route-back seed, ledger
#                terminal/pause state, or delivery-evidence marker does NOT pass
#                the report / complete gate — it fails closed (AC-NEG2).
#          Coverage lives in an executable selftest, not reference prose (AC-N1).
#
#          Exercises the canonical validators directly — never reimplements their
#          logic: scripts/validate-auto-pass-ledger.sh,
#          scripts/validate-auto-pass-report.sh,
#          scripts/validate-auto-pass-resume.sh,
#          scripts/auto-pass-consume-resume.sh, and the
#          scripts/auto-pass-runner.sh ledger-resume next_action.
# Inputs:  none (hermetic; fixtures under a mktemp dir).
# Outputs: "PASS: ..." on stdout on success; exit 1 on any assertion failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
REPORT_VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
RESUME_VALIDATOR="$ROOT/scripts/validate-auto-pass-resume.sh"
CONSUME="$ROOT/scripts/auto-pass-consume-resume.sh"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The report validator resolves the V work item's task.md (verification
# cross-check) and the source parent lifecycle (complete cross-check) under a
# hermetic root; POLARIS_SPECS_ROOT keeps the follow_up_dp_seed collision +
# parent lifecycle scan inside the fixture tree, POLARIS_WORKSPACE_ROOT keeps the
# task.md resolver hermetic.
SPECS="$TMP/docs-manager/src/content/docs/specs"
export POLARIS_WORKSPACE_ROOT="$TMP"
export POLARIS_SPECS_ROOT="$SPECS"

# Named delivery heads: OLD is the pre-revision head, NEW the post-rebind head.
OLD_HEAD="0000000000000000000000000000000000000000"
NEW_HEAD="1111111111111111111111111111111111111111"

# ── Canonical LOCKED source container (ledger recovery-state fixtures) ─────────
LOCKED_ID="DP-909"
LOCKED_SRC="$SPECS/design-plans/DP-909-recovery-fixture"
mkdir -p "$LOCKED_SRC"
cat >"$LOCKED_SRC/index.md" <<'MD'
---
title: "DP-909: recovery fixture"
description: "auto-pass recovery state-machine selftest fixture"
status: LOCKED
locked_at: 2026-05-19
---

# DP-909 fixture
MD
cat >"$LOCKED_SRC/refinement.md" <<'MD'
---
title: "DP-909 Refinement"
description: "auto-pass recovery fixture refinement"
---

## Scope

Fixture for auto-pass ledger recovery states.
MD
python3 - "$LOCKED_SRC/refinement.json" "$LOCKED_SRC" <<'PY'
import json, sys
from pathlib import Path
path, src = sys.argv[1:3]
Path(path).write_text(json.dumps({
    "version": "1",
    "created_at": "2026-05-19T10:00:00+08:00",
    "source": {"type": "dp", "id": "DP-909", "container": src,
               "plan_path": str(Path(src) / "index.md"), "jira_key": None},
    "modules": [{"path": ".claude/skills/auto-pass/SKILL.md", "action": "create"}],
    "acceptance_criteria": [{"id": "AC1", "text": "fixture", "category": "functional",
                             "negative": False,
                             "verification": {"method": "unit_test", "detail": "fixture"}}],
    "dependencies": [], "edge_cases": [], "predecessor_audit": [],
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

# Refinement hash matching validate-auto-pass-ledger.sh's algorithm exactly
# (name\0bytes\0 over refinement.md then refinement.json).
LOCKED_HASH="$(python3 - "$LOCKED_SRC" <<'PY'
import hashlib, sys
from pathlib import Path
src = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    digest.update(name.encode("utf-8")); digest.update(b"\0")
    digest.update((src / name).read_bytes()); digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
)"

# ── IMPLEMENTED source container + V task.md deliverable blocks (report) ───────
# The report `complete` cross-check reads (1) the source parent lifecycle
# (must be IMPLEMENTED to be complete-eligible) and (2) the V work item's task.md
# `deliverable` block as the sole delivery-evidence source (DP-360 T7).
IMPL_ID="DP-910"
IMPL_SRC="$SPECS/design-plans/DP-910-report-fixture"
mkdir -p "$IMPL_SRC"
cat >"$IMPL_SRC/index.md" <<'MD'
---
title: "DP-910: report fixture"
description: "auto-pass report recovery selftest fixture"
status: IMPLEMENTED
---

# DP-910 fixture
MD

# write_v_task <task_no> <head_sha> <verification_status>
# Scaffolds a resolvable V task.md carrying the canonical ac_verification block
# so the report verification cross-check is independently satisfiable /
# falsifiable. The head argument is retained at call sites to make the report
# head-rebind fixture intent explicit; implementation heads live in required_prs.
write_v_task() {
  local task_no="$1" head="$2" vstatus="$3"
  local dir="$IMPL_SRC/tasks/$task_no"
  mkdir -p "$dir"
  python3 - "$dir/index.md" "$task_no" "$head" "$vstatus" <<'PY'
import sys
from pathlib import Path
path, task_no, head, vstatus = sys.argv[1:5]
Path(path).write_text(
    "---\n"
    "task_kind: V\n"
    "ac_verification:\n"
    f"  status: {vstatus}\n"
    "---\n\n"
    f"# {task_no}\n\n"
    f"> Source: DP-910 | Task: DP-910-{task_no} | JIRA: N/A | Repo: polaris-framework\n",
    encoding="utf-8",
)
PY
}
write_v_task V1 "$NEW_HEAD" PASS   # current published delivery (positive)
write_v_task V2 "$OLD_HEAD" PASS   # stale head (head-rebind negative)
write_v_task V3 "$NEW_HEAD" FAIL   # published but verification not PASS (negative)
mkdir -p "$IMPL_SRC/tasks/T1"
cat >"$IMPL_SRC/tasks/T1/index.md" <<MD
---
task_kind: T
deliverable:
  head_sha: ${NEW_HEAD}
---

# T1

> Source: DP-910 | Task: DP-910-T1 | JIRA: N/A | Repo: polaris-framework
MD

# ── Fixture emitters ──────────────────────────────────────────────────────────
# emit_ledger PATH OVERRIDES_JSON — full valid DP-909 ledger + shallow overrides
# (terminal_status / pause / resumed_at / loop_counters merge).
emit_ledger() {
  local path="$1" overrides="$2"
  python3 - "$path" "$LOCKED_SRC" "$LOCKED_HASH" "$overrides" <<'PY'
import json, sys
from pathlib import Path
path, container, ref_hash, overrides = sys.argv[1:5]
led = {
    "schema_version": "1",
    "source": {"type": "dp", "id": "DP-909", "container": container, "refinement_hash": ref_hash},
    "started_at": "2026-05-19T10:00:00+08:00",
    "resumed_at": None,
    "terminal_status": None,
    "consent_policy": {"auto_reestimate": True, "auto_resplit": True, "auto_task_repair": True},
    "consent_excludes": ["base_branch_force_push", "force_push_without_lease", "history_rewrite",
                         "merge", "release", "deploy", "production_write", "jira_child_write",
                         "jira_comment_write", "jira_worklog_write", "task_scope_outside_mutation"],
    "task_snapshot": [], "stage_events": [],
    "loop_counters": {"engineering_to_breakdown": 0, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {}, "pause": None,
}
for key, value in json.loads(overrides).items():
    if key == "loop_counters":
        led["loop_counters"].update(value)
    else:
        led[key] = value
Path(path).write_text(json.dumps(led, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# emit_lightweight_ledger PATH TERMINAL PAUSE_JSON — raw ledger the report loads
# for the terminal cross-check (not run through the ledger validator).
emit_lightweight_ledger() {
  local path="$1" terminal="$2" pause="${3:-null}"
  python3 - "$path" "$terminal" "$pause" <<'PY'
import json, sys
from pathlib import Path
path, terminal, pause = sys.argv[1:4]
Path(path).write_text(json.dumps({
    "schema_version": "1",
    "terminal_status": None if terminal == "null" else terminal,
    "pause": json.loads(pause),
    "friction_log": [],
}) + "\n", encoding="utf-8")
PY
}

# emit_report PATH OVERRIDES_JSON — full valid report + shallow overrides.
emit_report() {
  local path="$1" overrides="$2"
  python3 - "$path" "$overrides" <<'PY'
import json, sys
from pathlib import Path
path, overrides = sys.argv[1:3]
report = {
    "schema_version": 1,
    "source_id": "DP-910",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/placeholder-ledger.json",
    "required_prs": [{"task_id": "DP-910-T1", "pr_url": "https://github.com/org/repo/pull/1", "head_sha": "abc"}],
    "verification": {"status": "PASS", "work_item_id": "DP-910-V1"},
    "issues": [], "blockers": [], "manual_items": [], "follow_ups": [],
    "overlap_disposition": [{"candidate": "converge", "disposition": "keep", "reason": "active"}],
    "follow_up_dp_seed": None,
    "framework_release_tail": {"trigger": "framework-release DP-910", "allowed": True, "reason": "ready"},
}
for key, value in json.loads(overrides).items():
    if key == "verification":
        report["verification"].update(value)
    else:
        report[key] = value
Path(path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# ── Deterministic gate assertions ─────────────────────────────────────────────
# Every gate is invoked TWICE; both runs must produce the same exit code (and, on
# the fail-closed path, the same marker) — this is the "same input → same verdict"
# determinism assertion (AC3).
FAILED=0
_run() { # _run OUTVAR ERRVAR RCVAR -- cmd...; captures stdout/stderr/rc
  local ovar="$1" evar="$2" rvar="$3"; shift 4
  local ofile efile rc
  ofile="$(mktemp)"; efile="$(mktemp)"
  set +e; "$@" >"$ofile" 2>"$efile"; rc=$?; set -e
  printf -v "$ovar" '%s' "$(cat "$ofile")"
  printf -v "$evar" '%s' "$(cat "$efile")"
  printf -v "$rvar" '%s' "$rc"
  rm -f "$ofile" "$efile"
}

assert_pass() { # assert_pass LABEL -- cmd...
  local label="$1"; shift 2
  local o1 e1 r1 o2 e2 r2
  _run o1 e1 r1 -- "$@"
  _run o2 e2 r2 -- "$@"
  if [[ "$r1" != 0 || "$r2" != 0 ]]; then
    echo "FAIL: $label expected exit 0, got rc1=$r1 rc2=$r2" >&2
    printf '%s\n' "$e1" >&2; FAILED=1; return
  fi
  if [[ "$r1" != "$r2" ]]; then
    echo "FAIL: $label non-deterministic exit ($r1 != $r2)" >&2; FAILED=1; return
  fi
  echo "  ok  $label"
}

assert_fail_closed() { # assert_fail_closed LABEL MARKER -- cmd...
  local label="$1" marker="$2"; shift 3
  local o1 e1 r1 o2 e2 r2
  _run o1 e1 r1 -- "$@"
  _run o2 e2 r2 -- "$@"
  if [[ "$r1" == 0 || "$r2" == 0 ]]; then
    echo "FAIL: $label expected fail-closed (non-zero), got rc1=$r1 rc2=$r2" >&2
    printf '%s\n%s\n' "$o1" "$e1" >&2; FAILED=1; return
  fi
  if [[ "$r1" != "$r2" ]]; then
    echo "FAIL: $label non-deterministic exit ($r1 != $r2)" >&2; FAILED=1; return
  fi
  if [[ -n "$marker" && "$e1" != *"$marker"* ]]; then
    echo "FAIL: $label missing marker '$marker'" >&2
    printf '%s\n' "$e1" >&2; FAILED=1; return
  fi
  if [[ "$e1" != "$e2" ]]; then
    echo "FAIL: $label non-deterministic stderr" >&2; FAILED=1; return
  fi
  echo "  ok  $label (fail-closed: ${marker:-nonzero})"
}

# ══════════════════════════════════════════════════════════════════════════════
# AC3 — deterministic recovery transitions
# ══════════════════════════════════════════════════════════════════════════════

# ── blocked_by_gate_failure ───────────────────────────────────────────────────
BLOCKED_LEDGER="$TMP/ledger-blocked.json"
emit_ledger "$BLOCKED_LEDGER" '{"terminal_status": "blocked_by_gate_failure"}'
assert_pass "blocked/ledger-terminal-valid" -- \
  "$LEDGER_VALIDATOR" "$BLOCKED_LEDGER" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"

BLOCKED_LEDGER_LW="$TMP/ledger-blocked-lw.json"
emit_lightweight_ledger "$BLOCKED_LEDGER_LW" blocked_by_gate_failure
BLOCKED_REPORT="$TMP/report-blocked.json"
emit_report "$BLOCKED_REPORT" "$(python3 - "$BLOCKED_LEDGER_LW" <<'PY'
import json, sys
print(json.dumps({
    "source_id": "DP-909", "terminal_status": "blocked_by_gate_failure",
    "ledger_path": sys.argv[1],
    "blockers": [{"kind": "probe_unknown", "reason": "missing marker"}],
    "verification": {"status": "UNCERTAIN", "work_item_id": "DP-909-V1"},
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-998-follow-up/index.md",
        "reason": "blocked_by_gate_failure", "source_report": sys.argv[1], "framework_gap": False},
}))
PY
)"
assert_pass "blocked/report-with-route-back-seed" -- "$REPORT_VALIDATOR" "$BLOCKED_REPORT"

# ── resume (session_handoff) ──────────────────────────────────────────────────
RESUME_ARTIFACT="$TMP/resume.json"
python3 - "$RESUME_ARTIFACT" > /dev/null <<PY
import json
json.dump({
    "schema_version": 1, "source_id": "$LOCKED_ID",
    "ledger_path": "$TMP/ledger-resume.json",
    "pause_kind": "session_handoff", "next_work_item_id": "DP-909-T2",
    "resume_command": "/auto-pass DP-909 resume", "summary": "context pressure handoff",
    "created_at": "2026-05-19T11:05:00+08:00",
}, open("$RESUME_ARTIFACT", "w"), indent=2)
PY
RESUME_LEDGER="$TMP/ledger-resume.json"
emit_ledger "$RESUME_LEDGER" "$(python3 - "$RESUME_ARTIFACT" <<'PY'
import json, sys
print(json.dumps({"pause": {
    "kind": "session_handoff", "reason": "context pressure",
    "created_at": "2026-05-19T11:00:00+08:00",
    "resume_artifact": sys.argv[1], "next_work_item_id": "DP-909-T2"}}))
PY
)"
assert_pass "resume/ledger-session-handoff-valid" -- \
  "$LEDGER_VALIDATOR" "$RESUME_LEDGER" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"
assert_pass "resume/resume-artifact-matches-ledger" -- \
  "$RESUME_VALIDATOR" --ledger "$RESUME_LEDGER" --resume-artifact "$RESUME_ARTIFACT" --source-id "$LOCKED_ID"

# runner next_action=resume determinism (ledger-resume short-circuit).
assert_runner_resume() {
  local label="$1" ledger="$2"
  local o1 e1 r1 o2 e2 r2
  _run o1 e1 r1 -- bash "$RUNNER" --repo "$TMP" --source-id "$LOCKED_ID" --stage source --ledger "$ledger"
  _run o2 e2 r2 -- bash "$RUNNER" --repo "$TMP" --source-id "$LOCKED_ID" --stage source --ledger "$ledger"
  if [[ "$o1" != "$o2" ]]; then
    echo "FAIL: $label non-deterministic runner JSON" >&2; FAILED=1; return
  fi
  python3 - "$label" "$o1" <<'PY' || FAILED=1
import json, sys
label, raw = sys.argv[1:3]
data = json.loads(raw)
errs = []
if data.get("next_action") != "resume":
    errs.append(f"next_action={data.get('next_action')!r} expected 'resume'")
if data.get("terminal_status") is not None:
    errs.append(f"terminal_status={data.get('terminal_status')!r} expected null")
if data.get("next_work_item_id") != "DP-909-T2":
    errs.append(f"next_work_item_id={data.get('next_work_item_id')!r} expected 'DP-909-T2'")
if errs:
    print(f"FAIL: {label}", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    raise SystemExit(1)
PY
  [[ "$FAILED" == 1 ]] || echo "  ok  $label (next_action=resume)"
}
assert_runner_resume "resume/runner-next-action" "$RESUME_LEDGER"

# consume-resume: the sanctioned writer clears pause + stamps resumed_at, then the
# ledger re-validates. Uses a dedicated ledger + resume artifact that reference
# each other (the resume validator checks resume.ledger_path == --ledger).
CONSUME_LEDGER="$TMP/ledger-resume-consume.json"
CONSUME_ARTIFACT="$TMP/resume-consume.json"
python3 - "$CONSUME_ARTIFACT" "$CONSUME_LEDGER" > /dev/null <<PY
import json
json.dump({
    "schema_version": 1, "source_id": "$LOCKED_ID",
    "ledger_path": "$CONSUME_LEDGER",
    "pause_kind": "session_handoff", "next_work_item_id": "DP-909-T2",
    "resume_command": "/auto-pass DP-909 resume", "summary": "context pressure handoff",
    "created_at": "2026-05-19T11:05:00+08:00",
}, open("$CONSUME_ARTIFACT", "w"), indent=2)
PY
emit_ledger "$CONSUME_LEDGER" "$(python3 - "$CONSUME_ARTIFACT" <<'PY'
import json, sys
print(json.dumps({"pause": {
    "kind": "session_handoff", "reason": "context pressure",
    "created_at": "2026-05-19T11:00:00+08:00",
    "resume_artifact": sys.argv[1], "next_work_item_id": "DP-909-T2"}}))
PY
)"
if bash "$CONSUME" --ledger "$CONSUME_LEDGER" --resume-artifact "$CONSUME_ARTIFACT" --source-id "$LOCKED_ID" >"$TMP/consume.out" 2>&1; then
  if ! grep -q '^CONSUMED:' "$TMP/consume.out"; then
    echo "FAIL: resume/consume did not report CONSUMED" >&2; FAILED=1
  else
    python3 - "$CONSUME_LEDGER" <<'PY' || FAILED=1
import json, sys
led = json.load(open(sys.argv[1]))
assert led.get("pause") is None, f"pause not cleared: {led.get('pause')!r}"
assert led.get("resumed_at"), "resumed_at not stamped"
PY
    [[ "$FAILED" == 1 ]] || echo "  ok  resume/consume-clears-pause (single writer)"
  fi
else
  echo "FAIL: resume/consume unexpectedly failed" >&2; cat "$TMP/consume.out" >&2; FAILED=1
fi
# Idempotency: re-consuming the now-pauseless ledger is a NOOP (deterministic).
assert_pass "resume/consume-idempotent-noop" -- \
  bash "$CONSUME" --ledger "$CONSUME_LEDGER" --resume-artifact "$CONSUME_ARTIFACT" --source-id "$LOCKED_ID"

# ── continue (post-resume / clean forward state) ──────────────────────────────
CONTINUE_LEDGER="$TMP/ledger-continue.json"
emit_ledger "$CONTINUE_LEDGER" '{"terminal_status": null, "pause": null}'
assert_pass "continue/ledger-clean-valid" -- \
  "$LEDGER_VALIDATOR" "$CONTINUE_LEDGER" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"
# A complete-eligible ledger (terminal null + no pause) lets a complete report pass
# the terminal cross-check — the "continue → complete" recovery edge.
COMPLETE_LEDGER="$TMP/ledger-complete-eligible.json"
emit_lightweight_ledger "$COMPLETE_LEDGER" null
COMPLETE_REPORT="$TMP/report-complete.json"
emit_report "$COMPLETE_REPORT" "$(python3 - "$COMPLETE_LEDGER" <<'PY'
import json, sys
print(json.dumps({"ledger_path": sys.argv[1], "verification": {"work_item_id": "DP-910-V1"}}))
PY
)"
assert_pass "continue/report-complete-eligible" -- "$REPORT_VALIDATOR" "$COMPLETE_REPORT"

# ── revision (engineering_revision_rounds) ────────────────────────────────────
REVISION_LEDGER="$TMP/ledger-revision.json"
emit_ledger "$REVISION_LEDGER" '{"loop_counters": {"engineering_revision_rounds": {"count": 2, "evidence_ids": ["DP-909:rev:1", "DP-909:rev:2"]}}}'
assert_pass "revision/under-cap-valid" -- \
  "$LEDGER_VALIDATOR" "$REVISION_LEDGER" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"
REVISION_CAP_LEDGER="$TMP/ledger-revision-cap.json"
emit_ledger "$REVISION_CAP_LEDGER" '{"terminal_status": "loop_cap_reached", "loop_counters": {"engineering_revision_rounds": {"count": 4}}}'
assert_pass "revision/over-cap-requires-loop-cap-terminal" -- \
  "$LEDGER_VALIDATOR" "$REVISION_CAP_LEDGER" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"

# ── head-rebind (current delivery head bound) ─────────────────────────────────
REBIND_REPORT="$TMP/report-rebind-current.json"
emit_report "$REBIND_REPORT" "$(python3 - "$COMPLETE_LEDGER" "$NEW_HEAD" <<'PY'
import json, sys
led, head = sys.argv[1:3]
print(json.dumps({"ledger_path": led,
                  "required_prs": [{"task_id": "DP-910-T1",
                                    "pr_url": "https://github.com/org/repo/pull/1",
                                    "head_sha": head}],
                  "verification": {"work_item_id": "DP-910-V1", "head_sha": head}}))
PY
)"
assert_pass "head-rebind/current-head-bound" -- "$REPORT_VALIDATOR" "$REBIND_REPORT"

# ══════════════════════════════════════════════════════════════════════════════
# AC6 / AC-NEG2 — active source missing route-back / ledger / evidence markers
#                 must NOT pass report / complete gates (fail-closed)
# ══════════════════════════════════════════════════════════════════════════════

# AC-NEG2 (missing route-back seed): a non-complete/active report with issues but
# no follow_up_dp_seed fails closed.
MISSING_SEED_REPORT="$TMP/report-missing-seed.json"
emit_report "$MISSING_SEED_REPORT" "$(python3 - "$BLOCKED_LEDGER_LW" <<'PY'
import json, sys
print(json.dumps({
    "source_id": "DP-909", "terminal_status": "blocked_by_gate_failure",
    "ledger_path": sys.argv[1],
    "blockers": [{"kind": "probe_unknown", "reason": "missing marker"}],
    "verification": {"status": "UNCERTAIN", "work_item_id": "DP-909-V1"},
    "follow_up_dp_seed": None,
}))
PY
)"
assert_fail_closed "neg/missing-route-back-seed" "follow_up_dp_seed" -- \
  "$REPORT_VALIDATOR" "$MISSING_SEED_REPORT"

# AC-NEG2 (inconsistent ledger terminal): complete report over a ledger whose
# durable terminal is blocked → mismatch.
NEG_LEDGER_BLOCKED="$TMP/ledger-neg-blocked.json"
emit_lightweight_ledger "$NEG_LEDGER_BLOCKED" blocked_by_gate_failure
NEG_COMPLETE_OVER_BLOCKED="$TMP/report-complete-over-blocked.json"
emit_report "$NEG_COMPLETE_OVER_BLOCKED" "$(python3 - "$NEG_LEDGER_BLOCKED" <<'PY'
import json, sys
print(json.dumps({"ledger_path": sys.argv[1]}))
PY
)"
assert_fail_closed "neg/complete-over-blocked-ledger" "POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH" -- \
  "$REPORT_VALIDATOR" "$NEG_COMPLETE_OVER_BLOCKED"

# AC-NEG2 (unconsumed route-back / active pause): complete report over a ledger
# still carrying an active session_handoff pause → mismatch (route-back not consumed).
NEG_LEDGER_PAUSED="$TMP/ledger-neg-paused.json"
emit_lightweight_ledger "$NEG_LEDGER_PAUSED" null '{"kind": "session_handoff"}'
NEG_COMPLETE_OVER_PAUSED="$TMP/report-complete-over-paused.json"
emit_report "$NEG_COMPLETE_OVER_PAUSED" "$(python3 - "$NEG_LEDGER_PAUSED" <<'PY'
import json, sys
print(json.dumps({"ledger_path": sys.argv[1]}))
PY
)"
assert_fail_closed "neg/complete-over-active-pause" "POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH" -- \
  "$REPORT_VALIDATOR" "$NEG_COMPLETE_OVER_PAUSED"

# AC-NEG2 (missing ledger): complete report pointing at an unreadable ledger.
NEG_COMPLETE_NO_LEDGER="$TMP/report-complete-no-ledger.json"
emit_report "$NEG_COMPLETE_NO_LEDGER" "$(python3 <<'PY'
import json
print(json.dumps({"ledger_path": "/tmp/dp417-nonexistent-ledger.json"}))
PY
)"
assert_fail_closed "neg/complete-missing-ledger" "POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE" -- \
  "$REPORT_VALIDATOR" "$NEG_COMPLETE_NO_LEDGER"

# AC6 (head-rebind stale): report pins the NEW head but required_prs still
# declares the OLD implementation head → mismatch.
NEG_REBIND_STALE="$TMP/report-rebind-stale.json"
emit_report "$NEG_REBIND_STALE" "$(python3 - "$COMPLETE_LEDGER" "$NEW_HEAD" <<'PY'
import json, sys
led, head = sys.argv[1:3]
print(json.dumps({"ledger_path": led,
                  "required_prs": [{"task_id": "DP-910-T1",
                                    "pr_url": "https://github.com/org/repo/pull/1",
                                    "head_sha": "0000000000000000000000000000000000000000"}],
                  "verification": {"work_item_id": "DP-910-V2", "head_sha": head}}))
PY
)"
assert_fail_closed "neg/head-rebind-stale-evidence" "POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH" -- \
  "$REPORT_VALIDATOR" "$NEG_REBIND_STALE"

# AC6 (evidence status not PASS): verification claims PASS but the V task.md
# canonical ac_verification.status is FAIL → mismatch.
NEG_STATUS_FAIL="$TMP/report-status-fail.json"
emit_report "$NEG_STATUS_FAIL" "$(python3 - "$COMPLETE_LEDGER" <<'PY'
import json, sys
print(json.dumps({"ledger_path": sys.argv[1],
                  "verification": {"work_item_id": "DP-910-V3"}}))
PY
)"
assert_fail_closed "neg/evidence-status-not-pass" "POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH" -- \
  "$REPORT_VALIDATOR" "$NEG_STATUS_FAIL"

# AC-NEG2 (missing evidence marker): verification PASS but no resolvable delivery
# evidence for the work item → missing.
NEG_MARKER_MISSING="$TMP/report-marker-missing.json"
emit_report "$NEG_MARKER_MISSING" "$(python3 - "$COMPLETE_LEDGER" <<'PY'
import json, sys
print(json.dumps({"ledger_path": sys.argv[1],
                  "verification": {"work_item_id": "DP-910-V9"}}))
PY
)"
assert_fail_closed "neg/delivery-evidence-marker-missing" "POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISSING" -- \
  "$REPORT_VALIDATOR" "$NEG_MARKER_MISSING"

# AC6 (draft PR not published): revision/head-rebind must wait until the PR is a
# non-draft published deliverable; a draft required_prs row fails closed.
NEG_DRAFT_PR="$TMP/report-draft-pr.json"
emit_report "$NEG_DRAFT_PR" "$(python3 - "$COMPLETE_LEDGER" "$NEW_HEAD" <<'PY'
import json, sys
led, head = sys.argv[1:3]
print(json.dumps({"ledger_path": led,
                  "verification": {"work_item_id": "DP-910-V1", "head_sha": head},
                  "required_prs": [{"task_id": "DP-910-T1",
                                    "pr_url": "https://github.com/org/repo/pull/1",
                                    "head_sha": head, "isDraft": True,
                                    "publisher": "engineering",
                                    "engineering_completion_marker": {"status": "PASS"},
                                    "base_freshness": "current"}]}))
PY
)"
assert_fail_closed "neg/draft-pr-not-published" "POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED" -- \
  "$REPORT_VALIDATOR" "$NEG_DRAFT_PR"

# AC-NEG2 (ledger session_handoff missing resume_artifact): fail closed.
NEG_RESUME_MISSING_ARTIFACT="$TMP/ledger-resume-missing-artifact.json"
emit_ledger "$NEG_RESUME_MISSING_ARTIFACT" '{"pause": {"kind": "session_handoff", "reason": "ctx", "created_at": "2026-05-19T11:00:00+08:00", "next_work_item_id": "DP-909-T2"}}'
assert_fail_closed "neg/resume-missing-resume-artifact" "resume_artifact" -- \
  "$LEDGER_VALIDATOR" "$NEG_RESUME_MISSING_ARTIFACT" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"

# AC-NEG2 (revision over cap without loop_cap_reached terminal): fail closed.
NEG_REVISION_OVER_CAP="$TMP/ledger-revision-over-cap.json"
emit_ledger "$NEG_REVISION_OVER_CAP" '{"terminal_status": null, "loop_counters": {"engineering_revision_rounds": {"count": 4}}}'
assert_fail_closed "neg/revision-over-cap-no-terminal" "engineering_revision_rounds" -- \
  "$LEDGER_VALIDATOR" "$NEG_REVISION_OVER_CAP" --source-container "$LOCKED_SRC" --source-id "$LOCKED_ID"

# AC-NEG2 (resume artifact does not match ledger pause): fail closed.
NEG_RESUME_MISMATCH_ARTIFACT="$TMP/resume-mismatch.json"
python3 - "$NEG_RESUME_MISMATCH_ARTIFACT" "$RESUME_LEDGER" > /dev/null <<'PY'
import json, sys
path, ledger = sys.argv[1:3]
json.dump({
    "schema_version": 1, "source_id": "DP-909", "ledger_path": ledger,
    "pause_kind": "session_handoff", "next_work_item_id": "DP-909-T9",  # mismatch
    "resume_command": "/auto-pass DP-909 resume", "summary": "handoff",
    "created_at": "2026-05-19T11:05:00+08:00",
}, open(path, "w"), indent=2)
PY
assert_fail_closed "neg/resume-artifact-mismatch" "" -- \
  "$RESUME_VALIDATOR" --ledger "$RESUME_LEDGER" --resume-artifact "$NEG_RESUME_MISMATCH_ARTIFACT" --source-id "$LOCKED_ID"

# AC-NEG2 (consume wrong pause kind): consuming a non-session_handoff pause as a
# session_handoff is rejected — the single writer will not touch the wrong state.
NEG_WRONG_PAUSE="$TMP/ledger-wrong-pause.json"
emit_ledger "$NEG_WRONG_PAUSE" '{"terminal_status": "paused_for_user_external_write", "pause": {"kind": "paused_for_user_external_write", "reason": "manual", "created_at": "2026-05-19T11:00:00+08:00"}}'
assert_fail_closed "neg/consume-wrong-pause-kind" "POLARIS_AUTO_PASS_CONSUME_RESUME_NOT_SESSION_HANDOFF" -- \
  bash "$CONSUME" --ledger "$NEG_WRONG_PAUSE" --resume-artifact "$RESUME_ARTIFACT" --source-id "$LOCKED_ID"

if [[ "$FAILED" != 0 ]]; then
  echo "FAIL: auto-pass-ledger-report-recovery-state-machine selftest" >&2
  exit 1
fi
echo "PASS: auto-pass-ledger-report-recovery-state-machine selftest"
