#!/usr/bin/env bash
# scripts/auto-pass-runner.sh — DP-237 deterministic auto-pass runner.
#
# Runner-first contract (DP-237 T3): this script is the SINGLE next-action
# authority for /auto-pass orchestration. The orchestrator reads runner JSON
# (schema_version=1, fields documented below) and dispatches based on
# next_action / next_skill / terminal_status alone — it does NOT re-run
# auto-pass-probe.sh, re-parse the ledger, or walk .polaris/evidence/**
# between stages.
#
# Internally the runner still wraps existing tools (spec-source-resolver,
# auto-pass-probe, validate-auto-pass-ledger). Those are implementation
# detail; the orchestrator contract is the JSON shape below.
#
# The runner is read-only:
# - It NEVER calls release, deploy, merge, or any code mutation.
# - It NEVER writes task.md, refinement.md, refinement.json, or any
#   workflow artifact.
# - It NEVER reads inner-skill prose ("PASS" text) to escalate status;
#   missing / UNKNOWN markers are always blocked_by_gate_failure.
#
# Portability: runner authority is portable across LLM runtimes (Claude Code,
# Codex, others). It does NOT depend on Claude-only hooks, Claude-only env
# vars, or any specific MCP server. Runtime adapters may invoke the same
# script through the same JSON contract.
#
# Output (stable JSON, schema_version=1):
#   {
#     "schema_version": 1,
#     "source_id": "DP-237",
#     "stage": "source|breakdown|engineering|verify-AC",
#     "status": "PASS|UNKNOWN|HALT|FAIL|BLOCKED|ROUTE_BACK_AMEND|...",
#     "terminal_status": "complete|loop_cap_reached|blocked_by_gate_failure
#                         |paused_for_session_handoff|paused_for_user_external_write
#                         |null",
#     "next_action": "dispatch|blocked|terminal|resume|refinement_amendment|...",
#     "next_skill": "breakdown|engineering|verify-AC|refinement|null",
#     "next_work_item_id": "DP-237-T1|null",
#     "evidence_path": "/abs/path|null",
#     "reason": "short string"
#   }
#
# Usage:
#   scripts/auto-pass-runner.sh DP-NNN
#   scripts/auto-pass-runner.sh --source-id DP-NNN [--stage source]
#     [--repo /abs/path] [--ledger /abs/path]
#   scripts/auto-pass-runner.sh --source-id DP-NNN
#     --stage breakdown|engineering|verify-AC
#     --work-item-id DP-NNN-T1
#     [--head-sha SHA] [--ledger /abs/path] [--repo /abs/path]

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-runner.sh DP-NNN
  scripts/auto-pass-runner.sh --source-id DP-NNN [--stage source]
    [--repo /abs/path] [--ledger /abs/path]
  scripts/auto-pass-runner.sh --source-id DP-NNN
    --stage breakdown|engineering|verify-AC
    --work-item-id DP-NNN-T1
    [--head-sha SHA] [--ledger /abs/path] [--repo /abs/path]
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
        SOURCE_ID="$1"
        shift
      else
        echo "auto-pass-runner: unknown arg: $1" >&2
        usage
      fi
      ;;
  esac
done

if [[ -z "$SOURCE_ID" ]]; then
  usage
fi
if [[ -z "$STAGE" ]]; then
  STAGE="source"
fi
case "$STAGE" in
  source|breakdown|engineering|verify-AC) ;;
  *) echo "auto-pass-runner: unsupported stage: $STAGE" >&2; exit 2 ;;
esac
if [[ "$STAGE" == "source" && -z "$WORK_ITEM_ID" ]]; then
  WORK_ITEM_ID="$SOURCE_ID"
fi
if [[ "$STAGE" != "source" && -z "$WORK_ITEM_ID" ]]; then
  echo "auto-pass-runner: --work-item-id required for stage=$STAGE" >&2
  usage
fi
if [[ ! -d "$REPO" ]]; then
  echo "auto-pass-runner: repo not found: $REPO" >&2
  exit 2
fi

SCRIPT_DIR_RESOLVED="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR_RESOLVED/auto-pass-probe.sh"
LEDGER_VALIDATOR="$SCRIPT_DIR_RESOLVED/validate-auto-pass-ledger.sh"

if [[ ! -x "$PROBE" && ! -f "$PROBE" ]]; then
  echo "auto-pass-runner: probe not found at $PROBE" >&2
  exit 2
fi

# Capture probe output (the probe already returns JSON with schema_version=1).
PROBE_ARGS=(--repo "$REPO" --stage "$STAGE" --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID")
if [[ -n "$HEAD_SHA" ]]; then
  PROBE_ARGS+=(--head-sha "$HEAD_SHA")
fi
if [[ -n "$LEDGER" ]]; then
  PROBE_ARGS+=(--ledger "$LEDGER")
fi

# We must NOT capture errors silently — probe writes to stdout for JSON and
# can write to stderr for ledger-friction side effects; both are fine.
set +e
PROBE_OUTPUT_RAW="$(bash "$PROBE" "${PROBE_ARGS[@]}" 2>/dev/null)"
PROBE_RC=$?
set -e
export PROBE_OUTPUT_RAW

python3 - "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" "$PROBE_RC" "$LEDGER_VALIDATOR" "$REPO" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

stage, source_id, work_item_id, head_sha, ledger_arg, probe_rc, ledger_validator, repo = sys.argv[1:9]
probe_rc = int(probe_rc)
probe_raw = os.environ.get("PROBE_OUTPUT_RAW", "")
# fallback path: read from stdin file descriptor via env-passed text. Bash side
# uses a heredoc, so we pull from the shell-set variable indirectly. To keep
# this tractable, the bash shell passes the text via the PROBE_OUTPUT env var.

probe_data = None
probe_error = None
if probe_raw:
    try:
        probe_data = json.loads(probe_raw)
    except Exception as exc:
        probe_error = f"probe output not JSON: {exc}"
elif probe_rc != 0:
    probe_error = f"probe exited rc={probe_rc} with empty stdout"
else:
    probe_error = "probe produced empty stdout"


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0)


# Stage → expected next skill on PASS (forward dispatch).
STAGE_NEXT_SKILL = {
    "source": "breakdown",
    "breakdown": "engineering",
    "engineering": "verify-AC",
    "verify-AC": None,
}


def map_next_action(probe_status, probe_terminal, probe_next, probe_evidence, probe_reason):
    """Translate probe machine fields to runner next_action / next_skill / terminal_status.

    Probe contract recap (auto-pass-probe.sh):
      - status: PASS | UNKNOWN | BLOCKED | ROUTE_BACK_AMEND | MANUAL_REQUIRED |
                BLOCKED_ENV | UNCERTAIN | FAIL | (any other JSON-derived value)
      - terminal_status: complete | blocked_by_gate_failure | loop_cap_reached |
                         paused_for_user_external_write | null
      - next_action (probe field name conflict): probe uses this to hint the
        next stage or action token. The runner re-interprets:
          * PASS + non-terminal → dispatch to next skill
          * ROUTE_BACK_AMEND → refinement_amendment (loop, non-terminal)
          * MANUAL_REQUIRED / paused → terminal pause
          * UNKNOWN / BLOCKED / FAIL / UNCERTAIN → terminal blocked
    """
    # ── Terminal cases ───────────────────────────────────────────────────────
    if probe_terminal == "complete":
        return {
            "status": probe_status or "PASS",
            "terminal_status": "complete",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "stage complete",
        }
    if probe_terminal == "loop_cap_reached":
        return {
            "status": probe_status or "BLOCKED",
            "terminal_status": "loop_cap_reached",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "planning loop cap reached",
        }
    if probe_terminal == "paused_for_user_external_write":
        return {
            "status": probe_status or "MANUAL_REQUIRED",
            "terminal_status": "paused_for_user_external_write",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "manual external write required",
        }
    if probe_terminal == "blocked_by_gate_failure":
        # AC-NEG3: missing / UNKNOWN markers must remain blocked even if
        # inner-skill prose contains "PASS"; we trust ONLY the machine field.
        # DP-269 AC3: probe_reason carries the specific cause from a breakdown
        # validation_fail / missing_v_task durable marker (emitted by
        # breakdown-emit-blocker-marker.sh). Forward it verbatim so the
        # orchestrator reports a readable blocker, not "marker missing".
        return {
            "status": probe_status or "UNKNOWN",
            "terminal_status": "blocked_by_gate_failure",
            "next_action": "blocked",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "blocked by gate failure",
        }

    # ── Non-terminal cases ───────────────────────────────────────────────────
    if probe_status == "ROUTE_BACK_AMEND" or probe_next == "refinement_amendment":
        return {
            "status": "ROUTE_BACK_AMEND",
            "terminal_status": None,
            "next_action": "refinement_amendment",
            "next_skill": "refinement",
            "next_work_item_id": source_id,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "refinement amendment loop",
        }
    if probe_status == "PASS":
        next_skill = STAGE_NEXT_SKILL.get(stage)
        # On verify-AC PASS without explicit "complete" terminal, treat as
        # complete (probe always pairs PASS+complete for verify-AC, but be
        # defensive).
        if stage == "verify-AC":
            return {
                "status": "PASS",
                "terminal_status": "complete",
                "next_action": "terminal",
                "next_skill": None,
                "next_work_item_id": None,
                "evidence_path": probe_evidence,
                "reason": probe_reason or "verify-AC complete",
            }
        return {
            "status": "PASS",
            "terminal_status": None,
            "next_action": "dispatch",
            "next_skill": next_skill,
            # Forward to a placeholder work item id — orchestrator owns the
            # exact next id; runner reports the source id when it cannot infer
            # a sibling task id from current evidence.
            "next_work_item_id": work_item_id if stage != "source" else None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or f"{stage} PASS",
        }

    # Default: any unrecognized probe status escalates to blocked. We do not
    # invent PASS semantics, and we do not read any inner-skill prose.
    return {
        "status": probe_status or "UNKNOWN",
        "terminal_status": "blocked_by_gate_failure",
        "next_action": "blocked",
        "next_skill": None,
        "next_work_item_id": None,
        "evidence_path": probe_evidence,
        "reason": probe_reason or "probe status not recognized",
    }


# ── Fail-stop: if probe itself failed to emit JSON, this is a blocker. ──────
if probe_data is None:
    emit({
        "schema_version": 1,
        "source_id": source_id,
        "stage": stage,
        "status": "UNKNOWN",
        "terminal_status": "blocked_by_gate_failure",
        "next_action": "blocked",
        "next_skill": None,
        "next_work_item_id": None,
        "evidence_path": None,
        "reason": probe_error or "probe failure",
    })

probe_status = probe_data.get("status")
probe_terminal = probe_data.get("terminal_status")
probe_next = probe_data.get("next_action")
probe_evidence = probe_data.get("evidence_path")
probe_reason = probe_data.get("reason")

# ── Ledger-level resume detection ────────────────────────────────────────────
# DP-237 AC-NEG4 / contract: when a ledger is provided and has
# pause.kind=session_handoff with required resume_artifact / next_work_item_id,
# the runner emits next_action=resume (non-terminal — the sidecar is expected
# to continue). This is a runner-layer signal, not a probe-layer one.
ledger_resume = None
if ledger_arg:
    ledger_path = Path(ledger_arg)
    if ledger_path.is_absolute() and ledger_path.is_file():
        try:
            ledger_payload = json.loads(ledger_path.read_text(encoding="utf-8"))
        except Exception:
            ledger_payload = None
        if isinstance(ledger_payload, dict):
            pause = ledger_payload.get("pause")
            if isinstance(pause, dict) and pause.get("kind") == "session_handoff":
                resume_artifact = pause.get("resume_artifact")
                next_id = pause.get("next_work_item_id")
                # Only surface as resume when both required fields are present;
                # otherwise leave pause handling to probe / ledger validator.
                if resume_artifact and next_id:
                    ledger_resume = {
                        "resume_artifact": resume_artifact,
                        "next_work_item_id": next_id,
                    }

if ledger_resume is not None:
    emit({
        "schema_version": 1,
        "source_id": source_id,
        "stage": stage,
        "status": "PASS",
        "terminal_status": None,
        "next_action": "resume",
        "next_skill": STAGE_NEXT_SKILL.get(stage),
        "next_work_item_id": ledger_resume["next_work_item_id"],
        "evidence_path": ledger_resume["resume_artifact"],
        "reason": "session_handoff resume",
    })

mapped = map_next_action(probe_status, probe_terminal, probe_next, probe_evidence, probe_reason)
payload = {
    "schema_version": 1,
    "source_id": source_id,
    "stage": stage,
}
payload.update(mapped)
print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
PY
