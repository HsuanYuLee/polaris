#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-resume.sh --ledger /abs/ledger.json --resume-artifact PATH [--source-id DP-NNN]

Validates auto-pass session_handoff resume artifact against its ledger pause.
USAGE
  exit 2
}

LEDGER=""
RESUME_ARTIFACT=""
SOURCE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --resume-artifact) RESUME_ARTIFACT="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$LEDGER" && -n "$RESUME_ARTIFACT" ]] || usage

python3 - "$LEDGER" "$RESUME_ARTIFACT" "$SOURCE_ID" <<'PY'
import datetime as dt
import json
import re
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
resume_path = Path(sys.argv[2])
expected_source_id = sys.argv[3]

# DP-228 AC4: source-neutral source.type set. Resolver-compatible source_id
# pattern: {PREFIX}-NNN matches DP, JIRA project key (GT, KB2CW), and bug keys.
SOURCE_TYPE_ENUM = {"dp", "jira", "bug"}
SOURCE_ID_PATTERN = re.compile(r"[A-Z][A-Z0-9]*-[0-9]+")

def fail(errors: list[str]) -> None:
    print("FAIL: auto-pass resume validation", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

def parse_iso(value: object, field: str, errors: list[str]) -> None:
    if not value:
        errors.append(f"{field} is required")
        return
    text = str(value)
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt.datetime.fromisoformat(text)
    except ValueError:
        errors.append(f"{field} must be ISO8601")

errors: list[str] = []
if not ledger_path.is_absolute():
    errors.append("ledger path must be absolute")
if not ledger_path.is_file():
    errors.append(f"ledger file not found: {ledger_path}")
if not resume_path.is_file():
    errors.append(f"resume artifact not found: {resume_path}")
if errors:
    fail(errors)

try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail([f"ledger invalid JSON: {exc}"])
try:
    resume = json.loads(resume_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail([f"resume artifact invalid JSON: {exc}"])

source = ledger.get("source") or {}
pause = ledger.get("pause") or {}
source_id = source.get("id")
# DP-228 AC4: source.type, when present, must be one of dp/jira/bug. Absent
# is allowed for legacy DP ledgers (backward compat with pre-DP-228 ledgers).
source_type = source.get("type")
if source_type is not None and source_type not in SOURCE_TYPE_ENUM:
    errors.append(f"ledger source.type must be one of {sorted(SOURCE_TYPE_ENUM)} when present")
if source_id and not SOURCE_ID_PATTERN.fullmatch(str(source_id)):
    errors.append("ledger source.id must match {PREFIX}-NNN (resolver-compatible)")
if expected_source_id and source_id != expected_source_id:
    errors.append("ledger source.id does not match --source-id")
if pause.get("kind") != "session_handoff":
    errors.append("ledger pause.kind must be session_handoff")
if ledger.get("terminal_status") not in (None, ""):
    errors.append("session_handoff ledger must have terminal_status=null")

if resume.get("schema_version") != 1:
    errors.append("resume schema_version must be 1")
resume_source_id = resume.get("source_id")
if resume_source_id and not SOURCE_ID_PATTERN.fullmatch(str(resume_source_id)):
    errors.append("resume source_id must match {PREFIX}-NNN (resolver-compatible)")
if resume_source_id != source_id:
    errors.append("resume source_id does not match ledger source.id")
if Path(str(resume.get("ledger_path", ""))).resolve() != ledger_path.resolve():
    errors.append("resume ledger_path does not match --ledger")
if resume.get("pause_kind") != "session_handoff":
    errors.append("resume pause_kind must be session_handoff")
if resume.get("next_work_item_id") != pause.get("next_work_item_id"):
    errors.append("resume next_work_item_id does not match ledger pause")
if str(pause.get("resume_artifact", "")) not in {str(resume_path), resume_path.as_posix()}:
    errors.append("ledger pause.resume_artifact does not point to resume artifact")
if not resume.get("resume_command"):
    errors.append("resume resume_command is required")
if not resume.get("summary"):
    errors.append("resume summary is required")
parse_iso(resume.get("created_at"), "resume created_at", errors)

if errors:
    fail(errors)
print(f"PASS: auto-pass resume validation ({resume_path})")
PY
