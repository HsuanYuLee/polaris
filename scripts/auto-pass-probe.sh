#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-probe.sh --stage breakdown|engineering|verify-AC
    --source-id DP-NNN --work-item-id DP-NNN-T1 [--repo PATH]
    [--head-sha SHA] [--ledger /absolute/path/to/ledger.json]
USAGE
  exit 2
}

REPO="$(pwd)"
STAGE=""
SOURCE_ID=""
WORK_ITEM_ID=""
HEAD_SHA=""
LEDGER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "auto-pass-probe: unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$STAGE" || -z "$SOURCE_ID" || -z "$WORK_ITEM_ID" ]]; then
  usage
fi
case "$STAGE" in
  breakdown|engineering|verify-AC) ;;
  *) echo "auto-pass-probe: unsupported stage: $STAGE" >&2; exit 2 ;;
esac
if [[ ! -d "$REPO" ]]; then
  echo "auto-pass-probe: repo not found: $REPO" >&2
  exit 2
fi

python3 - "$REPO" "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
stage, source_id, work_item_id, head_sha, ledger_arg = sys.argv[2:7]


def marker(path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"status": "UNKNOWN", "invalid_json": True}


def emit(status, terminal_status, next_action, evidence_path=None, reason=None):
    payload = {
        "schema_version": 1,
        "stage": stage,
        "source_id": source_id,
        "work_item_id": work_item_id,
        "status": status,
        "terminal_status": terminal_status,
        "next_action": next_action,
        "evidence_path": str(evidence_path) if evidence_path else None,
        "reason": reason,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0)


def status_of(path):
    data = marker(path)
    if not data:
        return None
    return data.get("status") or "UNKNOWN"


def ledger_terminal():
    if not ledger_arg:
        return None
    ledger_path = Path(ledger_arg)
    if not ledger_path.is_absolute() or not ledger_path.is_file():
        return ("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "ledger missing or not absolute")
    try:
        data = json.loads(ledger_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return ("UNKNOWN", "blocked_by_gate_failure", "blocked", ledger_path, f"ledger invalid JSON: {exc}")
    loops = data.get("loop_counters") or {}
    if max(int(loops.get("engineering_to_breakdown", 0)), int(loops.get("breakdown_to_refinement_inbox", 0))) >= 3:
        return ("BLOCKED", "loop_cap_reached", "blocked", ledger_path, "planning loop cap reached")
    drift = data.get("drift_retry") or {}
    if int(drift.get(work_item_id, 0)) >= 3:
        return ("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path, "drift retry cap reached")
    return None


ledger_result = ledger_terminal()
if ledger_result:
    emit(*ledger_result)

evidence = repo / ".polaris" / "evidence"

if stage == "breakdown":
    for subdir, terminal, action, reason in (
        ("validation-fail", "blocked_by_gate_failure", "blocked", "breakdown validation failed"),
        ("missing-v-task", "blocked_by_gate_failure", "breakdown", "missing V task"),
    ):
        path = evidence / subdir / f"{work_item_id}.json"
        if path.is_file():
            emit(status_of(path) or "BLOCKED", terminal, action, path, reason)
    inbox = repo / "docs-manager" / "src" / "content" / "docs" / "specs" / "design-plans"
    inbox_matches = list(inbox.glob(f"{source_id}-*/refinement-inbox/*.md"))
    if inbox_matches:
        emit("ROUTE_BACK", "paused_for_refinement", "refinement", inbox_matches[0], "refinement inbox present")
    path = evidence / "task-snapshot" / f"{work_item_id}.json"
    if status_of(path) == "PASS":
        emit("PASS", None, "engineering", path)
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "breakdown PASS marker missing")

if stage == "engineering":
    if not head_sha:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "engineering probe requires --head-sha")
    for subdir, reason in (
        ("blocked-conflict", "blocked conflict"),
        ("unsupported-mutation", "unsupported mutation"),
    ):
        path = evidence / subdir / f"{work_item_id}-{head_sha}.json"
        if path.is_file():
            emit(status_of(path) or "BLOCKED", "blocked_by_gate_failure", "blocked", path, reason)
    path = evidence / "completion-gate" / f"{work_item_id}-{head_sha}.json"
    if status_of(path) == "PASS":
        emit("PASS", None, "verify-AC", path)
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "completion gate marker missing")

if stage == "verify-AC":
    if not head_sha:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "verify-AC probe requires --head-sha")
    spec_issue = evidence / "ac-verification" / f"spec-issue-{work_item_id}-{head_sha}.json"
    if spec_issue.is_file():
        emit(status_of(spec_issue) or "ROUTE_BACK", "paused_for_refinement", "refinement", spec_issue, "spec issue")
    path = evidence / "ac-verification" / f"{work_item_id}-{head_sha}.json"
    status = status_of(path)
    if status == "PASS":
        emit("PASS", "complete", "report", path)
    if status in {"MANUAL_REQUIRED", "BLOCKED_ENV"}:
        emit(status, "paused_for_user_external_write", "user", path, status)
    if status in {"UNCERTAIN", "FAIL", "UNKNOWN"}:
        emit(status, "blocked_by_gate_failure", "blocked", path, "verification not pass")
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "AC verification marker missing")
PY
