#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-ledger.sh /absolute/path/to/ledger.json
    [--source-container /absolute/path/to/DP-NNN-container]
    [--source-id DP-NNN]
    [--task-write-at ISO8601]
    [--print-refinement-hash]
USAGE
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

LEDGER=""
SOURCE_CONTAINER=""
SOURCE_ID=""
TASK_WRITE_AT=""
PRINT_HASH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-container)
      SOURCE_CONTAINER="${2:-}"
      shift 2
      ;;
    --source-id)
      SOURCE_ID="${2:-}"
      shift 2
      ;;
    --task-write-at)
      TASK_WRITE_AT="${2:-}"
      shift 2
      ;;
    --print-refinement-hash)
      PRINT_HASH=1
      shift
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$LEDGER" ]]; then
        echo "ERROR: unexpected argument: $1" >&2
        usage
      fi
      LEDGER="$1"
      shift
      ;;
  esac
done

if [[ -z "$LEDGER" ]]; then
  usage
fi

python3 - "$LEDGER" "$SOURCE_CONTAINER" "$SOURCE_ID" "$TASK_WRITE_AT" "$PRINT_HASH" <<'PY'
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
expected_container = sys.argv[2]
expected_source_id = sys.argv[3]
task_write_at = sys.argv[4]
print_hash = sys.argv[5] == "1"

CONSENT_EXCLUDES = [
    "base_branch_force_push",
    "force_push_without_lease",
    "history_rewrite",
    "merge",
    "release",
    "deploy",
    "production_write",
    "jira_child_write",
    "jira_comment_write",
    "jira_worklog_write",
    "task_scope_outside_mutation",
]
TERMINAL_STATUSES = {
    "complete",
    "paused_for_refinement",
    "paused_for_user_external_write",
    "loop_cap_reached",
    "blocked_by_gate_failure",
    "user_aborted",
}
CONSENT_FIELDS = ("auto_reestimate", "auto_resplit", "auto_task_repair")


def fail(errors):
    print("FAIL: auto-pass ledger validation", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)


def parse_iso(value, field, errors):
    if value in (None, ""):
        errors.append(f"{field} is required")
        return None
    candidate = str(value)
    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"
    try:
        return dt.datetime.fromisoformat(candidate)
    except ValueError:
        errors.append(f"{field} must be ISO8601: {value}")
        return None


def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    data = {}
    for raw in text[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def refinement_hash(container):
    digest = hashlib.sha256()
    for name in ("refinement.md", "refinement.json"):
        path = container / name
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def validate_source(container, source_id, refinement_hash_value, errors):
    if not container.is_absolute():
        errors.append("source.container must be an absolute path")
        return
    if expected_container:
        try:
            if container.resolve() != Path(expected_container).resolve():
                errors.append("source.container does not match --source-container")
        except FileNotFoundError:
            errors.append("source.container does not exist")
    if not re.fullmatch(r"DP-[0-9]+", str(source_id or "")):
        errors.append("source.id must match DP-NNN")
    if expected_source_id and source_id != expected_source_id:
        errors.append("source.id does not match --source-id")
    index_path = container / "index.md"
    refinement_md = container / "refinement.md"
    refinement_json = container / "refinement.json"
    for required in (index_path, refinement_md, refinement_json):
        if not required.is_file():
            errors.append(f"required source artifact missing: {required}")
    if not index_path.is_file() or not refinement_md.is_file() or not refinement_json.is_file():
        return
    status = frontmatter(index_path).get("status")
    if status != "LOCKED":
        errors.append(f"source index.md status must be LOCKED, got {status or 'missing'}")
    try:
        refinement = json.loads(refinement_json.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"refinement.json invalid JSON: {exc}")
        return
    ref_source = refinement.get("source") or {}
    if ref_source.get("id") and ref_source.get("id") != source_id:
        errors.append("refinement.json source.id does not match ledger source.id")
    actual_hash = refinement_hash(container)
    if print_hash:
        print(actual_hash)
    if refinement_hash_value != actual_hash:
        errors.append("source.refinement_hash is stale or does not match refinement artifacts")


errors = []
if not ledger_path.is_absolute():
    errors.append("ledger path must be absolute")
if not ledger_path.is_file():
    errors.append(f"ledger file not found: {ledger_path}")
if errors:
    fail(errors)

try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail([f"invalid JSON: {exc}"])

if str(ledger.get("schema_version")) != "1":
    errors.append("schema_version must be \"1\"")

source = ledger.get("source")
if not isinstance(source, dict):
    errors.append("source must be an object")
else:
    container_raw = source.get("container")
    source_id = source.get("id")
    refinement_hash_value = source.get("refinement_hash")
    if not container_raw:
        errors.append("source.container is required")
    if not refinement_hash_value:
        errors.append("source.refinement_hash is required")
    if container_raw and refinement_hash_value:
        validate_source(Path(container_raw), source_id, refinement_hash_value, errors)

started_at = parse_iso(ledger.get("started_at"), "started_at", errors)
resumed_at = ledger.get("resumed_at")
resume_ts = None
if resumed_at not in (None, ""):
    resume_ts = parse_iso(resumed_at, "resumed_at", errors)
task_write_ts = None
if task_write_at:
    task_write_ts = parse_iso(task_write_at, "--task-write-at", errors)
    ordering_ts = resume_ts or started_at
    if task_write_ts and ordering_ts and task_write_ts < ordering_ts:
        errors.append("--task-write-at must be later than ledger started_at/resumed_at")

terminal_status = ledger.get("terminal_status")
if terminal_status not in (None, "") and terminal_status not in TERMINAL_STATUSES:
    errors.append(f"unknown terminal_status: {terminal_status}")

consent = ledger.get("consent_policy")
if not isinstance(consent, dict):
    errors.append("consent_policy must be an object")
else:
    for field in CONSENT_FIELDS:
        if consent.get(field) is not True:
            errors.append(f"consent_policy.{field} must be true")

if ledger.get("consent_excludes") != CONSENT_EXCLUDES:
    errors.append("consent_excludes must exactly match the canonical enum")

for list_field in ("task_snapshot", "stage_events"):
    if list_field in ledger and not isinstance(ledger[list_field], list):
        errors.append(f"{list_field} must be an array")

loop_counters = ledger.get("loop_counters")
if loop_counters is not None:
    if not isinstance(loop_counters, dict):
        errors.append("loop_counters must be an object")
    else:
        for key in ("engineering_to_breakdown", "breakdown_to_refinement_inbox"):
            value = loop_counters.get(key)
            if not isinstance(value, int) or value < 0:
                errors.append(f"loop_counters.{key} must be a non-negative integer")

drift_retry = ledger.get("drift_retry")
if drift_retry is not None:
    if not isinstance(drift_retry, dict):
        errors.append("drift_retry must be an object")
    else:
        for key, value in drift_retry.items():
            if not isinstance(value, int) or value < 0:
                errors.append(f"drift_retry.{key} must be a non-negative integer")

pause = ledger.get("pause")
if pause is not None:
    if not isinstance(pause, dict):
        errors.append("pause must be null or an object")
    else:
        kind = pause.get("kind")
        if kind not in ("paused_for_refinement", "paused_for_user_external_write"):
            errors.append("pause.kind must be a supported pause terminal status")
        if not pause.get("reason"):
            errors.append("pause.reason is required")
        parse_iso(pause.get("created_at"), "pause.created_at", errors)
        if kind == "paused_for_refinement" and not pause.get("inbox_path"):
            errors.append("paused_for_refinement pause requires inbox_path")

if errors:
    fail(errors)

print(f"PASS: auto-pass ledger validation ({ledger_path})")
PY
