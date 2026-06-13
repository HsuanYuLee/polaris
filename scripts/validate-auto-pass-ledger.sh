#!/usr/bin/env bash
# Purpose: Validate an auto-pass source-scoped ledger.json against the contract
#          (schema_version, source/refinement-hash, consent enum, terminal enum,
#          loop_counters cap incl. engineering_revision_rounds, pause/friction shape).
# Inputs:  ledger path (absolute) + optional --source-container/--source-id/--task-write-at.
# Outputs: stdout PASS line; exit 0 PASS, 1 validation failure, 2 usage error.
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
# DP-228 AC14: JIRA source 才要求 jira_status_transition consent。consent_excludes 必須
# 始終是上面的全集；JIRA status transition consent 只放行 transitionJiraIssue 對 source
# Epic / Bug 自身的 status 變更，不得放行 child write / comment / worklog / merge / release / deploy。
JIRA_SOURCE_TYPES = {"jira", "bug"}
JIRA_CONSENT_RECORD_REQUIRED_FIELDS = (
    "session_id",
    "source_id",
    "granted_at",
    "ttl_seconds",
)
# DP-212: paused_for_refinement is no longer a terminal status. It survives
# as a non-terminal pause.kind (sibling of session_handoff). Legacy ledgers
# that still set terminal_status=paused_for_refinement are explicitly flagged
# with PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL so they cannot silently coast.
TERMINAL_STATUSES = {
    "complete",
    "paused_for_user_external_write",
    "loop_cap_reached",
    "blocked_by_gate_failure",
    "user_aborted",
}
LEGACY_TERMINAL_PAUSED_FOR_REFINEMENT = "paused_for_refinement"
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
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", str(source_id or "")):
        errors.append("source.id must match {PREFIX}-NNN")
    source_type = source_data.get("type")
    if source_type is not None and source_type not in {"dp", "jira", "bug"}:
        errors.append("source.type must be dp, jira, or bug when present")
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
        source_data = source
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
    if terminal_status == LEGACY_TERMINAL_PAUSED_FOR_REFINEMENT:
        errors.append(
            "PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL: terminal_status=paused_for_refinement "
            "is no longer accepted (DP-212). Migrate to non-terminal pause.kind=paused_for_refinement "
            "or close the ledger with a current terminal status."
        )
    else:
        errors.append(f"unknown terminal_status: {terminal_status}")

consent = ledger.get("consent_policy")
# DP-228 AC14: validate JIRA-only consent fields based on source.type.
# Source type lookup falls back to None if `source` is malformed (errors already collected above).
ledger_source_type = None
if isinstance(source, dict):
    ledger_source_type = source.get("type")
is_jira_source = ledger_source_type in JIRA_SOURCE_TYPES

if not isinstance(consent, dict):
    errors.append("consent_policy must be an object")
else:
    for field in CONSENT_FIELDS:
        if consent.get(field) is not True:
            errors.append(f"consent_policy.{field} must be true")
    # jira_status_transition flag: required (true) for JIRA source; forbidden for DP source.
    has_jira_status_transition = "jira_status_transition" in consent
    if is_jira_source:
        if not has_jira_status_transition:
            errors.append(
                "consent_policy.jira_status_transition is required for JIRA source (DP-228 AC14)"
            )
        elif consent.get("jira_status_transition") is not True:
            errors.append(
                "consent_policy.jira_status_transition must be true for JIRA source (DP-228 AC14)"
            )
    else:
        if has_jira_status_transition:
            errors.append(
                "consent_policy.jira_status_transition is JIRA-only; DP source must not declare it "
                "(DP-228 AC14)"
            )

# jira_status_consent_record: required for JIRA source; forbidden for DP source.
status_record = ledger.get("jira_status_consent_record")
if is_jira_source:
    if status_record is None:
        errors.append(
            "jira_status_consent_record is required for JIRA source (DP-228 AC14)"
        )
    elif not isinstance(status_record, dict):
        errors.append("jira_status_consent_record must be an object when present")
    else:
        for field in JIRA_CONSENT_RECORD_REQUIRED_FIELDS:
            value = status_record.get(field)
            if value in (None, ""):
                errors.append(f"jira_status_consent_record.{field} is required")
        # source_id consistency check
        record_source_id = status_record.get("source_id")
        if record_source_id and isinstance(source, dict) and source.get("id") and record_source_id != source.get("id"):
            errors.append(
                "jira_status_consent_record.source_id must match ledger source.id"
            )
        # ttl_seconds positive integer
        ttl = status_record.get("ttl_seconds")
        if ttl is not None and (not isinstance(ttl, int) or isinstance(ttl, bool) or ttl <= 0):
            errors.append(
                "jira_status_consent_record.ttl_seconds must be a positive integer"
            )
        # granted_at must be ISO8601 when present
        if status_record.get("granted_at"):
            parse_iso(status_record.get("granted_at"), "jira_status_consent_record.granted_at", errors)
else:
    if status_record is not None:
        errors.append(
            "jira_status_consent_record is JIRA-only; DP source must not declare it (DP-228 AC14)"
        )

if ledger.get("consent_excludes") != CONSENT_EXCLUDES:
    errors.append("consent_excludes must exactly match the canonical enum")

for list_field in ("task_snapshot", "stage_events"):
    if list_field in ledger and not isinstance(ledger[list_field], list):
        errors.append(f"{list_field} must be an array")

loop_counters = ledger.get("loop_counters")
# DP-212: counter cap=3 is enforced here. breakdown_to_refinement_inbox > 3
# must be promoted to terminal_status=loop_cap_reached by the orchestrator;
# the validator surfaces the cap violation as an error so it cannot keep
# looping silently.
#
# DP-246 T2: loop_counters values may be either:
#   - legacy integer shape: N  (backward compat; still accepted)
#   - new object shape: {"count": N, "evidence_ids": [...]}
# Both shapes are valid. The validator extracts the count from either form.
#
# DP-313 T2 (AC4): engineering_revision_rounds is an additive counter key tracking how
# many engineering revision rounds the auto-pass review-revision loop has dispatched. It
# is validated-when-present (absent key == 0, same as the other counters), shares the same
# {count, evidence_ids[]} / legacy-int shape for idempotency, and is subject to the same
# cap: count > cap requires terminal_status=loop_cap_reached so the revision loop cannot
# iterate silently.
COUNTER_CAP = 3
CAP_ENFORCED_COUNTERS = (
    "engineering_to_breakdown",
    "breakdown_to_refinement_inbox",
    "engineering_revision_rounds",
)


def _counter_count(value):
    """Extract integer count from legacy int or new {count, evidence_ids} shape.
    Returns (count_int_or_None, error_str_or_None)."""
    if isinstance(value, int) and not isinstance(value, bool):
        if value < 0:
            return None, "must be a non-negative integer"
        return value, None
    if isinstance(value, dict):
        count = value.get("count")
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            return None, "object must have 'count' as a non-negative integer"
        evidence_ids = value.get("evidence_ids")
        if evidence_ids is not None and not isinstance(evidence_ids, list):
            return None, "object 'evidence_ids' must be an array when present"
        if isinstance(evidence_ids, list):
            for idx, eid in enumerate(evidence_ids):
                if not isinstance(eid, str):
                    return None, f"evidence_ids[{idx}] must be a string"
        return count, None
    return None, "must be a non-negative integer or {count, evidence_ids[]} object"


if loop_counters is not None:
    if not isinstance(loop_counters, dict):
        errors.append("loop_counters must be an object")
    else:
        for key in CAP_ENFORCED_COUNTERS:
            value = loop_counters.get(key)
            if value is None:
                # Key absent is fine — treated as 0.
                continue
            count, err = _counter_count(value)
            if err is not None:
                errors.append(f"loop_counters.{key}: {err}")
                continue
            if count > COUNTER_CAP and terminal_status != "loop_cap_reached":
                errors.append(
                    f"loop_counters.{key}={count} exceeds cap={COUNTER_CAP}; "
                    f"terminal_status must be loop_cap_reached"
                )

drift_retry = ledger.get("drift_retry")
if drift_retry is not None:
    if not isinstance(drift_retry, dict):
        errors.append("drift_retry must be an object")
    else:
        for key, value in drift_retry.items():
            if not isinstance(value, int) or value < 0:
                errors.append(f"drift_retry.{key} must be a non-negative integer")

for stash_field in ("pre_dispatch_stash", "post_dispatch_restore"):
    value = ledger.get(stash_field)
    if value is not None and not isinstance(value, dict):
        errors.append(f"{stash_field} must be an object when present")

pause = ledger.get("pause")
if pause is not None:
    if not isinstance(pause, dict):
        errors.append("pause must be null or an object")
    else:
        kind = pause.get("kind")
        if kind not in ("paused_for_refinement", "paused_for_user_external_write", "session_handoff"):
            errors.append("pause.kind must be a supported pause terminal status")
        if not pause.get("reason"):
            errors.append("pause.reason is required")
        parse_iso(pause.get("created_at"), "pause.created_at", errors)
        if kind == "paused_for_refinement":
            # DP-212: paused_for_refinement is now non-terminal — the auto-pass amendment
            # loop owns the inbox consumption. terminal_status must stay null while the
            # ledger is in this pause kind.
            if not pause.get("inbox_path"):
                errors.append("paused_for_refinement pause requires inbox_path")
            if terminal_status not in (None, ""):
                errors.append(
                    "paused_for_refinement pause is non-terminal (DP-212); "
                    "terminal_status must be null while inbox is being consumed"
                )
        if kind == "paused_for_user_external_write" and terminal_status != "paused_for_user_external_write":
            errors.append("paused_for_user_external_write pause requires matching terminal_status")
        if kind == "session_handoff":
            if terminal_status not in (None, ""):
                errors.append("session_handoff pause is non-terminal and requires terminal_status=null")
            if not pause.get("resume_artifact"):
                errors.append("session_handoff pause requires resume_artifact")
            if not pause.get("next_work_item_id"):
                errors.append("session_handoff pause requires next_work_item_id")

# DP-214: friction_log[] is optional but, when present, must follow the schema.
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
FRICTION_SUMMARY_SOFT_LIMIT = 280
friction_log = ledger.get("friction_log")
if friction_log is not None:
    if not isinstance(friction_log, list):
        errors.append("friction_log must be an array when present")
    else:
        for idx, entry in enumerate(friction_log):
            prefix = f"friction_log[{idx}]"
            if not isinstance(entry, dict):
                errors.append(f"{prefix} must be an object")
                continue
            ts = entry.get("ts")
            if not ts:
                errors.append(f"{prefix}.ts is required")
            else:
                parse_iso(ts, f"{prefix}.ts", errors)
            stage = entry.get("stage")
            if not stage:
                errors.append(f"{prefix}.stage is required")
            elif stage not in FRICTION_STAGE_ENUM:
                errors.append(f"{prefix}.stage must be one of {sorted(FRICTION_STAGE_ENUM)}")
            kind = entry.get("friction_kind")
            if not kind:
                errors.append(f"{prefix}.friction_kind is required")
            elif kind not in FRICTION_KIND_ENUM:
                errors.append(f"{prefix}.friction_kind must be one of {sorted(FRICTION_KIND_ENUM)}")
            summary = entry.get("summary")
            if not summary or not isinstance(summary, str):
                errors.append(f"{prefix}.summary is required and must be a string")

if errors:
    fail(errors)

# DP-214: surface advisory warnings (does not change exit code).
if friction_log:
    for idx, entry in enumerate(friction_log):
        summary = entry.get("summary", "")
        if isinstance(summary, str) and len(summary) > FRICTION_SUMMARY_SOFT_LIMIT:
            print(
                f"WARNING: friction_log[{idx}].summary exceeds {FRICTION_SUMMARY_SOFT_LIMIT} chars "
                f"({len(summary)}); helper does not truncate by contract",
                file=sys.stderr,
            )

print(f"PASS: auto-pass ledger validation ({ledger_path})")
PY
