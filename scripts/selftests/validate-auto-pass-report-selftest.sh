#!/usr/bin/env bash
# DP-237 T1: validate-auto-pass-report selftest
#
# Cover the report validator's contract for each terminal_status the report
# schema accepts:
#   - complete
#   - loop_cap_reached
#   - blocked_by_gate_failure
#   - paused_for_user_external_write
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
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
    }
elif mode == "loop_cap":
    payload["blockers"].append({"kind": "loop_cap", "reason": "planning loop > 3"})
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
    }
elif mode == "paused_user":
    payload["manual_items"].append({"kind": "manual_review", "reason": "needs user external write"})
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
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

# ─── 1. complete terminal (happy path) ───────────────────────────────────────
COMPLETE="$TMP/complete.json"
write_report "$COMPLETE" complete complete
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

# ─── 10. friction_log_summary contract ───────────────────────────────────────
# Build a ledger with friction entries and verify summary-match contract.
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
    "verification": {"status": "PASS"},
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
    "verification": {"status": "PASS"},
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

echo "PASS: validate-auto-pass-report selftest"
