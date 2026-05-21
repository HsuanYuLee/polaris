#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-probe.sh DP-NNN
  scripts/auto-pass-probe.sh --stage source --source-id DP-NNN [--repo PATH] [--ledger /absolute/path/to/ledger.json]
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
    *)
      if [[ -z "$STAGE" && -z "$SOURCE_ID" && "$1" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
        STAGE="source"
        SOURCE_ID="$1"
        WORK_ITEM_ID="$1"
        shift
      else
        echo "auto-pass-probe: unknown arg: $1" >&2
        usage
      fi
      ;;
  esac
done

if [[ -z "$STAGE" || -z "$SOURCE_ID" ]]; then
  usage
fi
case "$STAGE" in
  source|breakdown|engineering|verify-AC) ;;
  *) echo "auto-pass-probe: unsupported stage: $STAGE" >&2; exit 2 ;;
esac
if [[ "$STAGE" != "source" && -z "$WORK_ITEM_ID" ]]; then
  usage
fi
if [[ "$STAGE" == "source" && -z "$WORK_ITEM_ID" ]]; then
  WORK_ITEM_ID="$SOURCE_ID"
fi
if [[ ! -d "$REPO" ]]; then
  echo "auto-pass-probe: repo not found: $REPO" >&2
  exit 2
fi

python3 - "$REPO" "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" <<'PY'
import hashlib
import json
import os
import subprocess
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
    # DP-220: deterministic friction trigger — UNKNOWN means probe could not
    # determine outcome from durable evidence; flag as deterministic_gap so the
    # /auto-pass ledger has an audit trail. NOOP when AUTO_PASS_LEDGER_PATH is
    # unset or ledger missing (helper handles both).
    if status == "UNKNOWN":
        ledger_env = os.environ.get("AUTO_PASS_LEDGER_PATH", "")
        if ledger_env:
            helper = repo / "scripts" / "append-auto-pass-friction.sh"
            if helper.is_file():
                try:
                    summary = f"probe UNKNOWN: stage={stage} source={source_id} work_item={work_item_id} reason={reason or 'n/a'} (auto-trigger from auto-pass-probe, DP-220)"
                    subprocess.run(
                        [
                            "bash",
                            str(helper),
                            ledger_env,
                            "--stage",
                            stage if stage in {"source", "breakdown", "engineering", "verify-AC", "framework-release", "post-task"} else "post-task",
                            "--kind",
                            "deterministic_gap",
                            "--summary",
                            summary[:280],
                        ],
                        check=False,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=2.0,
                    )
                except Exception:
                    pass
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0)


def status_of(path):
    data = marker(path)
    if not data:
        return None
    return data.get("status") or "UNKNOWN"


def frontmatter_status(path: Path):
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    for raw in text[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        if key.strip() == "status":
            return value.strip().strip('"').strip("'")
    return None


def refinement_hash(container: Path):
    digest = hashlib.sha256()
    for name in ("refinement.md", "refinement.json"):
        path = container / name
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def find_dp_container():
    design_plans = repo / "docs-manager/src/content/docs/specs/design-plans"
    matches = sorted(path for path in design_plans.glob(f"{source_id}-*") if path.is_dir())
    return matches


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


if stage == "source":
    if not source_id.startswith("DP-"):
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "source resolver for non-DP key is not available in this runtime")
    matches = find_dp_container()
    if len(matches) != 1:
        emit(
            "BLOCKED",
            "blocked_by_gate_failure",
            "blocked",
            matches[0] if matches else None,
            f"expected exactly one DP container, got {len(matches)}",
        )
    container = matches[0]
    missing = [name for name in ("index.md", "refinement.md", "refinement.json") if not (container / name).is_file()]
    if missing:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container, "missing source artifacts: " + ", ".join(missing))
    status = frontmatter_status(container / "index.md")
    if status != "LOCKED":
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container / "index.md", f"source status must be LOCKED, got {status or 'missing'}")
    try:
        refinement = json.loads((container / "refinement.json").read_text(encoding="utf-8"))
    except Exception as exc:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container / "refinement.json", f"refinement.json invalid JSON: {exc}")
    ref_source = refinement.get("source") or {}
    if ref_source.get("id") and ref_source.get("id") != source_id:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container / "refinement.json", "refinement.json source.id mismatch")
    if ledger_arg:
        ledger_path = Path(ledger_arg)
        if not ledger_path.is_absolute() or not ledger_path.is_file():
            emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "ledger missing or not absolute")
        try:
            ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        except Exception as exc:
            emit("UNKNOWN", "blocked_by_gate_failure", "blocked", ledger_path, f"ledger invalid JSON: {exc}")
        ledger_source = ledger.get("source") or {}
        if ledger_source.get("id") != source_id:
            emit("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path, "ledger source.id mismatch")
        if ledger_source.get("refinement_hash") != refinement_hash(container):
            emit("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path, "ledger refinement hash stale")
    emit("PASS", None, "breakdown", container)


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
        # DP-212: refinement-inbox presence is now a non-terminal signal —
        # auto-pass dispatches `refinement` in amendment mode, then loops
        # back to breakdown. terminal_status stays null so the orchestrator
        # does not stop unless counter cap or scope guard fires.
        emit("ROUTE_BACK_AMEND", None, "refinement_amendment", inbox_matches[0], "refinement inbox present (amendment loop)")
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
        # DP-212: spec_issue → non-terminal amendment loop (same as breakdown
        # inbox presence). terminal_status stays null; orchestrator continues
        # to dispatch refinement amendment mode until cap or scope guard fires.
        emit(status_of(spec_issue) or "ROUTE_BACK_AMEND", None, "refinement_amendment", spec_issue, "verify-AC spec issue (amendment loop)")
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
