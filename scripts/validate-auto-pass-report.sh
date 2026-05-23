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
import re
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
# DP-228 AC4: source-neutral schema. source_id must match resolver-compatible
# {PREFIX}-NNN — no hard-coded DP regex.
SOURCE_ID_PATTERN = re.compile(r"[A-Z][A-Z0-9]*-[0-9]+")


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
report_source_id = data.get("source_id")
if not report_source_id:
    errors.append("source_id is required")
elif not SOURCE_ID_PATTERN.fullmatch(str(report_source_id)):
    errors.append("source_id must match {PREFIX}-NNN (resolver-compatible)")
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

# DP-214: friction_log_summary is computed from the ledger referenced by ledger_path.
# It is validator-owned: the report writer MAY include a snapshot, but if present it
# must match the ledger aggregation exactly. Validator will not silently rewrite it.
FRICTION_KIND_ENUM = {
    "inner_skill_halt_bypass",
    "manual_artifact_patch",
    "deterministic_gap",
    "env_bypass",
    "validator_contract_conflict",
    "missing_helper_script",
    "language_drift_repair",
    "other",
}
FRICTION_STAGE_ENUM = {"source", "breakdown", "engineering", "verify-AC", "framework-release", "post-task"}


def aggregate_friction(entries):
    summary = {"total": 0, "by_stage": {}, "by_kind": {}}
    for entry in entries or []:
        if not isinstance(entry, dict):
            continue
        summary["total"] += 1
        stage = entry.get("stage")
        if stage in FRICTION_STAGE_ENUM:
            summary["by_stage"][stage] = summary["by_stage"].get(stage, 0) + 1
        kind = entry.get("friction_kind")
        if kind in FRICTION_KIND_ENUM:
            summary["by_kind"][kind] = summary["by_kind"].get(kind, 0) + 1
    return summary


ledger_friction = None
ledger_path_value = data.get("ledger_path")
if isinstance(ledger_path_value, str) and ledger_path_value:
    ledger_p = Path(ledger_path_value)
    if ledger_p.is_file():
        try:
            ledger_payload = json.loads(ledger_p.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"ledger_path JSON invalid: {exc}")
            ledger_payload = None
        if isinstance(ledger_payload, dict):
            ledger_friction = ledger_payload.get("friction_log") or []
            if not isinstance(ledger_friction, list):
                errors.append("ledger friction_log must be an array when present")
                ledger_friction = []

computed_summary = aggregate_friction(ledger_friction) if ledger_friction is not None else None
declared_summary = data.get("friction_log_summary")
if declared_summary is not None:
    if not isinstance(declared_summary, dict):
        errors.append("friction_log_summary must be an object when present")
    elif computed_summary is None:
        errors.append("friction_log_summary present but ledger could not be read")
    elif declared_summary != computed_summary:
        errors.append(
            "friction_log_summary does not match ledger aggregation; "
            f"expected {json.dumps(computed_summary, sort_keys=True)}, "
            f"got {json.dumps(declared_summary, sort_keys=True)}"
        )

if errors:
    fail(errors)
print(f"PASS: auto-pass report validation ({path})")
PY
