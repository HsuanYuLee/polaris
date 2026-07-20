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
# The runner is read-only, with one declared exception:
# - It NEVER calls release, deploy, merge, or any code mutation.
# - It NEVER writes task.md, refinement.md, refinement.json, or any
#   workflow artifact — EXCEPT the DP-311 Terminal Complete Sequence:
#   before declaring terminal_status=complete it advances every required V
#   work item whose ac_verification block is PASS with
#   human_disposition=passed through the existing canonical task-level
#   writer scripts/mark-spec-implemented.sh (move → tasks/pr-release/ +
#   status IMPLEMENTED), then fail-closed confirms every required V work
#   item reached the canonical terminal contract (pr-release/ + IMPLEMENTED
#   + ac_verification PASS, same contract as
#   close-parent-spec-if-complete.sh). Any miss downgrades the result to
#   blocked_by_gate_failure instead of complete.
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
#                         |paused_for_user_external_write|user_aborted|null",
#     "next_action": "dispatch|blocked|terminal|resume|refinement_amendment|...",
#     "next_skill": "breakdown|engineering|verify-AC|refinement|null",
#     "next_work_item_id": "DP-237-T1|null",
#     "evidence_path": "/abs/path|null",
#     "delegation_authority": {"source_id":"DP-420", ...}|null,
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
#     [--gap-ledger /abs/path]
#     [--pr-state-file /abs/path]
#
# DP-313 T1: at the engineering stage, --pr-state-file passes an explicit
# review-state classification (a fixture / pr-action-classifier.sh output JSON;
# never a live gh read inside the runner/probe) that the runner forwards to the
# probe. After the completion-gate marker is PASS, an actionable review state
# routes back to the owning skill: needs_code_changes → engineering (revision),
# planning_gap → breakdown, spec issue → refinement (amendment). Any
# non-actionable state (or no file) keeps parity with current behaviour and
# continues to verify-AC.

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
    [--gap-ledger /abs/path]
    [--pr-state-file /abs/path]
USAGE
  exit 2
}

REPO="$(pwd)"
STAGE=""
SOURCE_ID=""
WORK_ITEM_ID=""
HEAD_SHA=""
LEDGER=""
PR_STATE_FILE=""
GAP_LEDGER=""
GAP_LEDGER_EXPLICIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --gap-ledger) GAP_LEDGER="${2:-}"; GAP_LEDGER_EXPLICIT=1; shift 2 ;;
    --pr-state-file) PR_STATE_FILE="${2:-}"; shift 2 ;;
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
GAP_LEDGER_VALIDATOR="$SCRIPT_DIR_RESOLVED/validate-current-head-gap-ledger.sh"
SOURCE_RESOLVER="$SCRIPT_DIR_RESOLVED/spec-source-resolver.sh"
if [[ -z "$GAP_LEDGER" ]]; then
  GAP_LEDGER="$SCRIPT_DIR_RESOLVED/current-head-gap-ledger.json"
fi

if [[ ! -x "$PROBE" && ! -f "$PROBE" ]]; then
  echo "auto-pass-runner: probe not found at $PROBE" >&2
  exit 2
fi

# DP-420 T9: validate the complete current-head gap/source ledger before the
# probe can authorize a dispatch.  The canonical ledger is source-scoped: an
# unrelated source remains outside its coverage, while an explicit ledger is
# always fail-closed on missing/malformed/mismatched input.  DP-420 itself also
# fails closed if its canonical ledger is absent or unreadable.
GAP_PREFLIGHT_OUTPUT_RAW=""
GAP_LEDGER_SOURCE=""
if [[ -f "$GAP_LEDGER" ]]; then
  set +e
  GAP_LEDGER_SOURCE="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_runner_1.py" "$GAP_LEDGER"
)"
  GAP_LEDGER_SOURCE_RC=$?
  set -e
else
  GAP_LEDGER_SOURCE_RC=2
fi

GAP_PREFLIGHT_REQUIRED=0
if [[ "$GAP_LEDGER_EXPLICIT" -eq 1 || "$SOURCE_ID" == "DP-420" || "$GAP_LEDGER_SOURCE" == "$SOURCE_ID" ]]; then
  GAP_PREFLIGHT_REQUIRED=1
fi

emit_gap_ledger_blocked() {
  local reason="$1"
  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_runner_2.py" "$SOURCE_ID" "$STAGE" "$GAP_LEDGER" "$reason"
}

if [[ "$GAP_PREFLIGHT_REQUIRED" -eq 1 ]]; then
  if [[ "$GAP_LEDGER_SOURCE_RC" -ne 0 || -z "$GAP_LEDGER_SOURCE" ]]; then
    emit_gap_ledger_blocked "current-head gap ledger missing or unreadable"
    exit 0
  fi
  if [[ "$GAP_LEDGER_SOURCE" != "$SOURCE_ID" ]]; then
    emit_gap_ledger_blocked "current-head gap ledger source mismatch: expected $SOURCE_ID, got $GAP_LEDGER_SOURCE"
    exit 0
  fi
  if [[ ! -f "$GAP_LEDGER_VALIDATOR" ]]; then
    emit_gap_ledger_blocked "current-head gap ledger validator missing"
    exit 0
  fi
  GAP_SOURCE_CONTAINER=""
  REPO_ABS="$(cd "$REPO" && pwd)"
  LOCAL_SPECS_ROOT="$REPO_ABS/docs-manager/src/content/docs/specs"
  set +e
  if [[ -d "$LOCAL_SPECS_ROOT" ]]; then
    GAP_SOURCE_RESOLUTION="$(bash "$SOURCE_RESOLVER" --source-id "$SOURCE_ID" --specs-root "$LOCAL_SPECS_ROOT" --json 2>/dev/null)"
    GAP_SOURCE_RESOLUTION_RC=$?
  else
    GAP_SOURCE_RESOLUTION=""
    GAP_SOURCE_RESOLUTION_RC=2
  fi
  if [[ "$GAP_SOURCE_RESOLUTION_RC" -ne 0 ]]; then
    GAP_SOURCE_RESOLUTION="$(bash "$SOURCE_RESOLVER" --source-id "$SOURCE_ID" --json 2>/dev/null)"
    GAP_SOURCE_RESOLUTION_RC=$?
  fi
  set -e
  if [[ "$GAP_SOURCE_RESOLUTION_RC" -eq 0 ]]; then
    GAP_SOURCE_CONTAINER="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_runner_3.py" "$GAP_SOURCE_RESOLUTION"
)"
  fi
  if [[ -z "$GAP_SOURCE_CONTAINER" || ! -d "$GAP_SOURCE_CONTAINER" ]]; then
    emit_gap_ledger_blocked "current-head gap ledger source container cannot be resolved"
    exit 0
  fi
  set +e
  GAP_PREFLIGHT_OUTPUT_RAW="$(bash "$GAP_LEDGER_VALIDATOR" \
    --ledger "$GAP_LEDGER" --repo "$REPO" --source-container "$GAP_SOURCE_CONTAINER" \
    --source-id "$SOURCE_ID" --json 2>&1)"
  GAP_PREFLIGHT_RC=$?
  set -e
  if [[ "$GAP_PREFLIGHT_RC" -ne 0 ]]; then
    GAP_PREFLIGHT_REASON="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_runner_4.py" "$GAP_PREFLIGHT_OUTPUT_RAW"
)"
    emit_gap_ledger_blocked "$GAP_PREFLIGHT_REASON"
    exit 0
  fi
fi
export GAP_PREFLIGHT_OUTPUT_RAW

# Capture probe output (the probe already returns JSON with schema_version=1).
PROBE_ARGS=(--repo "$REPO" --stage "$STAGE" --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID")
if [[ -n "$HEAD_SHA" ]]; then
  PROBE_ARGS+=(--head-sha "$HEAD_SHA")
fi
if [[ -n "$LEDGER" ]]; then
  PROBE_ARGS+=(--ledger "$LEDGER")
fi
# DP-313 T1: forward the explicit review-state input to the probe. The runner
# does not interpret the file itself; the probe owns the actionable / parity
# classification and emits a route-back the runner mirrors below.
if [[ -n "$PR_STATE_FILE" ]]; then
  PROBE_ARGS+=(--pr-state-file "$PR_STATE_FILE")
fi

# Probe writes JSON to stdout; stderr carries ledger-friction side effects and,
# for the DP-313 T3 fail-closed path, a POLARIS_TOOL_MISSING marker (review-state
# unavailable, probe exit 3). Capture stderr to a temp file so the runner can
# re-surface that marker instead of swallowing it (AC-NEG2): a fail-open here
# would silently let the work item be declared complete.
PROBE_STDERR_FILE="$(mktemp)"
trap 'rm -f "$PROBE_STDERR_FILE"' EXIT
set +e
PROBE_OUTPUT_RAW="$(bash "$PROBE" "${PROBE_ARGS[@]}" 2>"$PROBE_STDERR_FILE")"
PROBE_RC=$?
set -e
export PROBE_OUTPUT_RAW

# DP-313 T3 (AC-NEG2): the probe fails closed with exit 3 + POLARIS_TOOL_MISSING
# on stderr when --pr-state-file was supplied but the review state is unavailable
# (gh missing / PR state unreadable). Re-surface that marker on the runner's own
# stderr before mapping the blocked result, so hooks / orchestrator can grep it.
if [[ "$PROBE_RC" -eq 3 ]] && grep -q 'POLARIS_TOOL_MISSING' "$PROBE_STDERR_FILE"; then
  cat "$PROBE_STDERR_FILE" >&2
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_runner_5.py" "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" "$PROBE_RC" "$LEDGER_VALIDATOR" "$REPO"
