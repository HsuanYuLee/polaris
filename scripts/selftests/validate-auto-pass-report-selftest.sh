#!/usr/bin/env bash
# Purpose: selftest for scripts/validate-auto-pass-report.sh — DP-237 report
#          schema contract + DP-311 T3 fail-closed cross-checks:
#          (a) report.terminal_status=complete ↔ referenced ledger terminal
#              (AC5: paused / non-complete terminal / unreadable ledger →
#              exit 2 + 結構化 marker；complete 與 complete-eligible 放行)
#          (b) report.verification.status=PASS ↔ the V work item's task.md
#              `deliverable` block (deliverable.head_sha + verification.status
#              =PASS). DP-360 T7: the head-sha-keyed ac_verification marker is
#              retired; the task.md block is the sole delivery-evidence source
#              (AC6: no resolvable task.md / no head → MISSING; status≠PASS or
#              pinned-head mismatch → MISMATCH; never reads a marker file or a
#              branch ref).
# Inputs:  none (hermetic; fixtures in mktemp dir, scan root pinned via
#          POLARIS_WORKSPACE_ROOT override)
# Outputs: "PASS: ..." on success; non-zero exit with diagnostics on failure.
#
# Covers the report validator's contract for each terminal_status the report
# schema accepts: complete / loop_cap_reached / blocked_by_gate_failure /
# paused_for_user_external_write.
#
# Note: paused_for_session_handoff is a *ledger* pause.kind (DP-237 brief
# mentions it), but is NOT a report terminal_status — the report validator's
# TERMINAL set excludes it by design (the ledger is the source of truth for
# session_handoff resume; the report does not terminalize on it). This
# selftest asserts the validator rejects paused_for_session_handoff as a
# report terminal_status.
#
# Also covers friction_log_summary contract: writer-declared summary must
# match ledger aggregation exactly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
# DP-330 T2: a real workspace-root-bound source file for framework_gap
# contract_evidence (the validator resolves it under WORKSPACE_ROOT=$ROOT,
# which is independent of the hermetic POLARIS_WORKSPACE_ROOT marker override).
CONTRACT_EVIDENCE="scripts/validate-auto-pass-report.sh:1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# DP-360 T7: hermetic scan root — the validator resolves the V work item's
# task.md `deliverable` block via resolve-task-md.sh --scan-root $TMP (the
# head-sha-keyed ac_verification marker is retired).
export POLARIS_WORKSPACE_ROOT="$TMP"
SPECS_DESIGN_PLANS="$TMP/docs-manager/src/content/docs/specs/design-plans"
mkdir -p "$SPECS_DESIGN_PLANS"

# Description: record a V work item's delivery in its task.md `deliverable` block
#              (DP-360 T7 replacement for the retired ac_verification marker).
#              Creates the DP container + V task.md resolvable by work_item_id.
# Args:        $1 = work_item_id (DP-NNN-V{n}); $2 = head sha; $3 = status
# Side effects: writes $SPECS_DESIGN_PLANS/{DP}-selftest/tasks/{stem}/index.md
write_marker() {
  local work_item="$1" head="$2" status="$3"
  python3 - "$SPECS_DESIGN_PLANS" "$work_item" "$head" "$status" <<'PY'
import re
import sys
from pathlib import Path

base, work_item, head, status = sys.argv[1:5]
m = re.match(r"^(DP-\d+)-([A-Za-z]+\d+)$", work_item)
assert m, f"unexpected work_item shape: {work_item}"
dp, stem = m.group(1), m.group(2)
task_dir = Path(base) / f"{dp}-selftest" / "tasks" / stem
task_dir.mkdir(parents=True, exist_ok=True)
(task_dir / "index.md").write_text(
    "---\n"
    f'title: "{stem}"\n'
    "status: IN_PROGRESS\n"
    "task_kind: V\n"
    f"work_item_id: {work_item}\n"
    "deliverable:\n"
    f"  head_sha: {head}\n"
    "  pr_url: https://github.com/example-org/example/pull/1\n"
    "  pr_state: MERGED\n"
    "  verification:\n"
    f"    status: {status}\n"
    "    ac_counts:\n"
    "      ac_total: 1\n"
    f"      ac_pass: {'1' if status == 'PASS' else '0'}\n"
    "---\n\n"
    f"# {stem}\n",
    encoding="utf-8",
)
PY
}

# Description: write a minimal auto-pass ledger fixture.
# Args:        $1 = path; $2 = terminal_status JSON value (null or "...");
#              $3 = pause JSON value (null or object)
# Side effects: creates the ledger file
write_ledger() {
  local path="$1" terminal="$2" pause="$3"
  python3 - "$path" "$terminal" "$pause" <<'PY'
import json, sys
from pathlib import Path
path, terminal, pause = sys.argv[1:4]
Path(path).write_text(json.dumps({
    "schema_version": "1",
    "terminal_status": json.loads(terminal),
    "pause": json.loads(pause),
    "friction_log": [],
}) + "\n", encoding="utf-8")
PY
}

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
write_marker "DP-237-V1" "$HEAD_SHA" "PASS"

COMPLETE_LEDGER="$TMP/ledger-complete.json"
write_ledger "$COMPLETE_LEDGER" '"complete"' 'null'
ELIGIBLE_LEDGER="$TMP/ledger-eligible.json"
write_ledger "$ELIGIBLE_LEDGER" 'null' 'null'
PAUSED_LEDGER="$TMP/ledger-paused.json"
write_ledger "$PAUSED_LEDGER" 'null' '{"kind": "session_handoff", "reason": "context pressure"}'
BLOCKED_LEDGER="$TMP/ledger-blocked.json"
write_ledger "$BLOCKED_LEDGER" '"blocked_by_gate_failure"' 'null'

write_report() {
  local path="$1" terminal="$2" mode="$3" source_id="${4:-DP-237}" ledger_path="${5:-}"
  python3 - "$path" "$terminal" "$mode" "$source_id" "$ledger_path" <<'PY'
import json, sys
from pathlib import Path
path, terminal, mode, source_id, ledger_path = sys.argv[1:6]
payload = {
    "schema_version": 1,
    "source_id": source_id,
    "terminal_status": terminal,
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path or "/tmp/nope.json",
    "required_prs": [{"task_id": f"{source_id}-T1", "pr_url": "https://github.com/org/repo/pull/1", "head_sha": "abc"}],
    "verification": {"status": "PASS", "work_item_id": f"{source_id}-V1"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}
if mode == "blocked":
    payload["blockers"].append({"kind": "missing_marker", "reason": "no completion gate marker"})
    payload["verification"]["status"] = "UNCERTAIN"
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": False,
    }
elif mode == "loop_cap":
    payload["blockers"].append({"kind": "loop_cap", "reason": "planning loop > 3"})
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": False,
    }
elif mode == "paused_user":
    payload["manual_items"].append({"kind": "manual_review", "reason": "needs user external write"})
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": False,
    }
elif mode == "complete":
    pass
elif mode == "missing_required":
    # Drop a required field to force fail.
    del payload["created_at"]
elif mode == "bad_terminal":
    pass  # caller already set an invalid terminal
elif mode == "friction_match" or mode == "friction_mismatch":
    pass
elif mode == "bad_seed":
    payload["follow_up_dp_seed"] = "not-a-dict"
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

assert_pass() {
  local label="$1"; shift
  if ! "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label expected PASS" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}
assert_fail() {
  local label="$1"; shift
  if "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label expected FAIL but validator passed" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}
# Description: assert the command fails with exit code 2 (fail-closed cross-check).
# Args:        $1 = label; $@ = command
# Side effects: writes $TMP/$label.out
assert_fail2() {
  local label="$1"; shift
  local rc=0
  "$@" >"$TMP/$label.out" 2>&1 || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: $label expected exit 2 (fail-closed cross-check), got $rc" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

# ─── 1. complete terminal (happy path: ledger complete + head-bound marker) ──
COMPLETE="$TMP/complete.json"
write_report "$COMPLETE" complete complete DP-237 "$COMPLETE_LEDGER"
assert_pass "complete" "$VALIDATOR" "$COMPLETE"

# ─── 2. loop_cap_reached terminal ────────────────────────────────────────────
LOOP="$TMP/loop-cap.json"
write_report "$LOOP" loop_cap_reached loop_cap
assert_pass "loop_cap_reached" "$VALIDATOR" "$LOOP"

# ─── 3. blocked_by_gate_failure terminal ─────────────────────────────────────
BLOCKED="$TMP/blocked.json"
write_report "$BLOCKED" blocked_by_gate_failure blocked
assert_pass "blocked_by_gate_failure" "$VALIDATOR" "$BLOCKED"

# ─── 4. paused_for_user_external_write terminal ──────────────────────────────
# (DP-237 brief mentions paused_for_session_handoff — but the report
# schema's pause terminal is paused_for_user_external_write. session_handoff
# is owned by the ledger pause.kind, not the report.)
PAUSED="$TMP/paused.json"
write_report "$PAUSED" paused_for_user_external_write paused_user
assert_pass "paused_for_user_external_write" "$VALIDATOR" "$PAUSED"

# ─── 5. NEG: paused_for_session_handoff is NOT a report terminal_status ──────
HANDOFF_BAD="$TMP/session-handoff-bad.json"
write_report "$HANDOFF_BAD" paused_for_session_handoff bad_terminal
assert_fail "session-handoff-bad" "$VALIDATOR" "$HANDOFF_BAD"
grep -q 'invalid terminal_status' "$TMP/session-handoff-bad.out" \
  || { echo "FAIL: paused_for_session_handoff rejection should mention invalid terminal_status"; cat "$TMP/session-handoff-bad.out" >&2; exit 1; }

# ─── 6. NEG: missing required field (created_at) ─────────────────────────────
BAD_REQUIRED="$TMP/missing-required.json"
write_report "$BAD_REQUIRED" complete missing_required
assert_fail "missing-required" "$VALIDATOR" "$BAD_REQUIRED"

# ─── 7. NEG: malformed source_id (lowercase) ─────────────────────────────────
BAD_SOURCE="$TMP/bad-source.json"
write_report "$BAD_SOURCE" complete complete dp-237
assert_fail "bad-source-id" "$VALIDATOR" "$BAD_SOURCE"

# ─── 8. NEG: follow_up_dp_seed wrong type ────────────────────────────────────
BAD_SEED="$TMP/bad-seed.json"
write_report "$BAD_SEED" blocked_by_gate_failure bad_seed
assert_fail "bad-seed-type" "$VALIDATOR" "$BAD_SEED"

# ─── 9. NEG: blocked terminal without follow_up_dp_seed ─────────────────────
NO_SEED="$TMP/no-seed.json"
python3 - "$NO_SEED" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}) + "\n", encoding="utf-8")
PY
assert_fail "no-seed" "$VALIDATOR" "$NO_SEED"
grep -q "follow_up_dp_seed is required" "$TMP/no-seed.out"

# ─── 10. follow_up_dp_seed framework_gap contract (DP-330 T2: AC3/AC4/AC-NEG2) ─
# AC3: framework_gap=true with valid contract_evidence → PASS.
FRAMEWORK_GAP_OK="$TMP/framework-gap-ok.json"
python3 - "$FRAMEWORK_GAP_OK" "$CONTRACT_EVIDENCE" <<'PY'
import json, sys
from pathlib import Path
report_path, evidence = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
        "framework_gap": True,
        "contract_evidence": [evidence],
    },
}) + "\n", encoding="utf-8")
PY
assert_pass "framework-gap-ok" "$VALIDATOR" "$FRAMEWORK_GAP_OK"

# AC3: framework_gap=true but contract_evidence absent → FAIL (required).
FRAMEWORK_GAP_MISSING_EVIDENCE="$TMP/framework-gap-missing-evidence.json"
python3 - "$FRAMEWORK_GAP_MISSING_EVIDENCE" <<'PY'
import json, sys
from pathlib import Path
report_path = sys.argv[1]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
        "framework_gap": True,
    },
}) + "\n", encoding="utf-8")
PY
assert_fail "framework-gap-missing-evidence" "$VALIDATOR" "$FRAMEWORK_GAP_MISSING_EVIDENCE"
grep -q "contract_evidence is required" "$TMP/framework-gap-missing-evidence.out"

# AC-NEG2: seed present but framework_gap field absent → FAIL (must be boolean).
FRAMEWORK_GAP_MISSING_BOOL="$TMP/framework-gap-missing-bool.json"
python3 - "$FRAMEWORK_GAP_MISSING_BOOL" <<'PY'
import json, sys
from pathlib import Path
report_path = sys.argv[1]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
    },
}) + "\n", encoding="utf-8")
PY
assert_fail "framework-gap-missing-bool" "$VALIDATOR" "$FRAMEWORK_GAP_MISSING_BOOL"
grep -q "framework_gap must be a boolean" "$TMP/framework-gap-missing-bool.out"

# AC-NEG2: framework_gap=true but contract_evidence points outside workspace root → FAIL.
FRAMEWORK_GAP_BAD_EVIDENCE="$TMP/framework-gap-bad-evidence.json"
OUTSIDE_CONTRACT="$TMP/outside-contract.md"
printf '%s\n' "outside workspace contract fixture" >"$OUTSIDE_CONTRACT"
python3 - "$FRAMEWORK_GAP_BAD_EVIDENCE" "$OUTSIDE_CONTRACT" <<'PY'
import json, sys
from pathlib import Path
report_path, outside_contract = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
        "framework_gap": True,
        "contract_evidence": [f"{outside_contract}:1"],
    },
}) + "\n", encoding="utf-8")
PY
assert_fail "framework-gap-bad-evidence" "$VALIDATOR" "$FRAMEWORK_GAP_BAD_EVIDENCE"
grep -q "workspace root" "$TMP/framework-gap-bad-evidence.out"

# AC-NEG2: framework_gap=true but contract_evidence line beyond file range → FAIL.
FRAMEWORK_GAP_LINE_OUT_OF_RANGE="$TMP/framework-gap-line-out-of-range.json"
python3 - "$FRAMEWORK_GAP_LINE_OUT_OF_RANGE" "$CONTRACT_EVIDENCE" <<'PY'
import json, sys
from pathlib import Path
report_path, evidence = sys.argv[1:3]
raw_path, _raw_line = evidence.rsplit(":", 1)
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
        "framework_gap": True,
        "contract_evidence": [f"{raw_path}:999999"],
    },
}) + "\n", encoding="utf-8")
PY
assert_fail "framework-gap-line-out-of-range" "$VALIDATOR" "$FRAMEWORK_GAP_LINE_OUT_OF_RANGE"
grep -q "outside file range" "$TMP/framework-gap-line-out-of-range.out"

# ─── 10. friction_log_summary contract ───────────────────────────────────────
# Build a ledger with friction entries and verify summary-match contract.
# (terminal_status absent + no pause → complete-eligible for cross-check (a).)
LEDGER="$TMP/ledger.json"
python3 - "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": "1",
    "friction_log": [
        {"ts": "2026-05-01T00:00:00+08:00", "stage": "breakdown", "friction_kind": "deterministic_gap", "summary": "x"},
        {"ts": "2026-05-01T00:01:00+08:00", "stage": "engineering", "friction_kind": "manual_artifact_patch", "summary": "y"},
        {"ts": "2026-05-01T00:02:00+08:00", "stage": "engineering", "friction_kind": "deterministic_gap", "summary": "z"},
    ],
}) + "\n", encoding="utf-8")
PY

# Match: report friction_log_summary equals ledger aggregation
MATCH_REPORT="$TMP/friction-match.json"
python3 - "$MATCH_REPORT" "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
report_path, ledger_path = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-237-V1"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
    "friction_log_summary": {
        "total": 3,
        "by_stage": {"breakdown": 1, "engineering": 2},
        "by_kind": {"deterministic_gap": 2, "manual_artifact_patch": 1},
    },
}) + "\n", encoding="utf-8")
PY
assert_pass "friction-match" "$VALIDATOR" "$MATCH_REPORT"

# Mismatch: declared summary does not equal computed aggregation
MISMATCH_REPORT="$TMP/friction-mismatch.json"
python3 - "$MISMATCH_REPORT" "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
report_path, ledger_path = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-237-V1"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
    "friction_log_summary": {"total": 99, "by_stage": {}, "by_kind": {}},
}) + "\n", encoding="utf-8")
PY
assert_fail "friction-mismatch" "$VALIDATOR" "$MISMATCH_REPORT"
grep -q "friction_log_summary does not match" "$TMP/friction-mismatch.out"

# ═══ DP-311 T3 — AC5: report↔ledger terminal cross-check ════════════════════

# ─── 11. AC5 NEG: complete report + paused ledger → exit 2 + marker ──────────
AC5_PAUSED="$TMP/ac5-paused.json"
write_report "$AC5_PAUSED" complete complete DP-237 "$PAUSED_LEDGER"
assert_fail2 "ac5-paused" "$VALIDATOR" "$AC5_PAUSED"
grep -q 'POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH' "$TMP/ac5-paused.out" \
  || { echo "FAIL: ac5-paused should emit POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH" >&2; cat "$TMP/ac5-paused.out" >&2; exit 1; }

# ─── 12. AC5 NEG: complete report + non-complete terminal ledger → exit 2 ────
AC5_BLOCKED="$TMP/ac5-blocked.json"
write_report "$AC5_BLOCKED" complete complete DP-237 "$BLOCKED_LEDGER"
assert_fail2 "ac5-blocked" "$VALIDATOR" "$AC5_BLOCKED"
grep -q 'POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH' "$TMP/ac5-blocked.out"

# ─── 13. AC5 NEG: complete report + unreadable ledger → exit 2 (fail-closed) ─
AC5_GONE="$TMP/ac5-gone.json"
write_report "$AC5_GONE" complete complete DP-237 "$TMP/does-not-exist-ledger.json"
assert_fail2 "ac5-gone" "$VALIDATOR" "$AC5_GONE"
grep -q 'POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE' "$TMP/ac5-gone.out"

# ─── 14. AC5 POS: complete report + complete-eligible ledger (null terminal,
#         no pause) is accepted — write-time state before parent-flip finalize
#         (DP-311 D5 ordering: report write precedes auto-pass-finalize-ledger
#         inside mark-spec-implemented). ────────────────────────────────────
AC5_ELIGIBLE="$TMP/ac5-eligible.json"
write_report "$AC5_ELIGIBLE" complete complete DP-237 "$ELIGIBLE_LEDGER"
assert_pass "ac5-eligible" "$VALIDATOR" "$AC5_ELIGIBLE"

# ─── 15. AC5: non-complete report terminal does not require ledger terminal
#         alignment (paused ledger referenced by a blocked report passes). ───
AC5_BLOCKED_REPORT="$TMP/ac5-blocked-report.json"
write_report "$AC5_BLOCKED_REPORT" blocked_by_gate_failure blocked DP-237 "$PAUSED_LEDGER"
assert_pass "ac5-blocked-report-paused-ledger" "$VALIDATOR" "$AC5_BLOCKED_REPORT"

# ═══ DP-311 T3 — AC6: verification↔head-bound marker cross-check ═════════════

# ─── 16. AC6 NEG: verification PASS but no head-bound marker → exit 2 ────────
AC6_NO_MARKER="$TMP/ac6-no-marker.json"
write_report "$AC6_NO_MARKER" complete complete DP-556 "$COMPLETE_LEDGER"
assert_fail2 "ac6-no-marker" "$VALIDATOR" "$AC6_NO_MARKER"
grep -q 'POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISSING' "$TMP/ac6-no-marker.out" \
  || { echo "FAIL: ac6-no-marker should emit POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISSING" >&2; cat "$TMP/ac6-no-marker.out" >&2; exit 1; }

# ─── 17. AC6 NEG: marker exists but status != PASS (stale summary) → exit 2 ──
write_marker "DP-557-V1" "$HEAD_SHA" "FAIL"
AC6_STALE="$TMP/ac6-stale.json"
write_report "$AC6_STALE" complete complete DP-557 "$COMPLETE_LEDGER"
assert_fail2 "ac6-stale" "$VALIDATOR" "$AC6_STALE"
grep -q 'POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH' "$TMP/ac6-stale.out"

# ─── 18. AC6 NEG: pinned verification.head_sha that does not match the V ─────
#         work item's recorded deliverable.head_sha → exit 2 + MISMATCH.
#         DP-360 T7: there is ONE durable delivery record per work item (the
#         task.md deliverable block, head=aaaa from line 84). A pinned head
#         (bbbb) that does not bind to the recorded head is a genuine MISMATCH
#         (delivery happened at a different head), not a missing record.
AC6_PINNED_MISS="$TMP/ac6-pinned-miss.json"
python3 - "$AC6_PINNED_MISS" "$COMPLETE_LEDGER" <<'PY'
import json, sys
from pathlib import Path
report_path, ledger_path = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-237-V1",
                     "head_sha": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}) + "\n", encoding="utf-8")
PY
assert_fail2 "ac6-pinned-miss" "$VALIDATOR" "$AC6_PINNED_MISS"
grep -q 'POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH' "$TMP/ac6-pinned-miss.out"

# ─── 19. AC6 POS: pinned verification.head_sha with matching PASS marker ─────
AC6_PINNED_OK="$TMP/ac6-pinned-ok.json"
python3 - "$AC6_PINNED_OK" "$COMPLETE_LEDGER" "$HEAD_SHA" <<'PY'
import json, sys
from pathlib import Path
report_path, ledger_path, head = sys.argv[1:4]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-237-V1", "head_sha": head},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}) + "\n", encoding="utf-8")
PY
assert_pass "ac6-pinned-ok" "$VALIDATOR" "$AC6_PINNED_OK"

# ─── 20. AC6 NEG: verification PASS without work_item_id → exit 2 ────────────
AC6_NO_WI="$TMP/ac6-no-wi.json"
python3 - "$AC6_NO_WI" "$COMPLETE_LEDGER" <<'PY'
import json, sys
from pathlib import Path
report_path, ledger_path = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-237",
    "terminal_status": "complete",
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "PASS"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}) + "\n", encoding="utf-8")
PY
assert_fail2 "ac6-no-work-item" "$VALIDATOR" "$AC6_NO_WI"
grep -q 'POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISSING' "$TMP/ac6-no-work-item.out"

# AC6: non-PASS verification status does not require a marker — covered by
# cases 3 / 9 (UNCERTAIN verification passes without any marker fixture).

echo "PASS: validate-auto-pass-report selftest"
