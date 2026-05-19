#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-report.sh /path/to/report.json
USAGE
  exit 2
fi

python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
TERMINAL = {
    "complete",
    "paused_for_refinement",
    "paused_for_user_external_write",
    "loop_cap_reached",
    "blocked_by_gate_failure",
    "user_aborted",
}
OVERLAP = {"keep", "narrow", "deprecate-note", "follow-up-sunset"}


def fail(errors):
    print("FAIL: auto-pass report validation", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)


if not path.is_file():
    fail([f"report not found: {path}"])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    fail([f"invalid JSON: {exc}"])

errors = []
if data.get("schema_version") != 1:
    errors.append("schema_version must be 1")
if not data.get("source_id"):
    errors.append("source_id is required")
terminal = data.get("terminal_status")
if terminal not in TERMINAL:
    errors.append(f"invalid terminal_status: {terminal}")
for field in ("created_at", "ledger_path"):
    if not data.get(field):
        errors.append(f"{field} is required")
for field in ("required_prs", "issues", "blockers", "manual_items", "follow_ups", "overlap_disposition"):
    if not isinstance(data.get(field), list):
        errors.append(f"{field} must be an array")
verification = data.get("verification")
if not isinstance(verification, dict) or not verification.get("status"):
    errors.append("verification.status is required")

for idx, row in enumerate(data.get("overlap_disposition") or []):
    disposition = row.get("disposition") if isinstance(row, dict) else None
    if disposition not in OVERLAP:
        errors.append(f"overlap_disposition[{idx}].disposition invalid: {disposition}")
    if disposition == "follow-up-sunset" and not row.get("candidate"):
        errors.append(f"overlap_disposition[{idx}] follow-up-sunset requires candidate")

seed_needed = (
    terminal != "complete"
    or bool(data.get("issues"))
    or bool(data.get("blockers"))
    or bool(data.get("manual_items"))
    or bool(data.get("follow_ups"))
    or any(row.get("disposition") == "follow-up-sunset" for row in data.get("overlap_disposition") or [] if isinstance(row, dict))
)
seed = data.get("follow_up_dp_seed")
if seed_needed:
    if not isinstance(seed, dict):
        errors.append("follow_up_dp_seed is required when report has issue threshold")
    else:
        for field in ("path", "reason", "source_report"):
            if not seed.get(field):
                errors.append(f"follow_up_dp_seed.{field} is required")
else:
    if seed is not None:
        errors.append("follow_up_dp_seed must be null when no issue threshold is present")

tail = data.get("framework_release_tail")
if tail is not None:
    if not isinstance(tail, dict):
        errors.append("framework_release_tail must be an object or null")
    elif "framework-release" not in str(tail.get("trigger", "")):
        errors.append("framework_release_tail.trigger must reference framework-release")

if errors:
    fail(errors)
print(f"PASS: auto-pass report validation ({path})")
PY
