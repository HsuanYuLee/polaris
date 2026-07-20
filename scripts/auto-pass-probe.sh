#!/usr/bin/env bash
# Purpose: auto-pass durable-evidence probe — for a given stage
#          (source/breakdown/engineering/verify-AC) read the durable delivery
#          evidence and emit the machine terminal status (PASS /
#          blocked_by_gate_failure / etc.) as JSON.
# Inputs:  --stage, --source-id, --work-item-id, [--head-sha], [--ledger],
#          [--pr-state-file], [--repo].
# Outputs: probe JSON on stdout; exit 0 on emit, 2 on usage error,
#          3 on fail-closed review-state unavailability (POLARIS_TOOL_MISSING).
#
# DP-360 T7: the engineering and verify-AC stages no longer read head-sha-keyed
# completion-gate / ac-verification markers. The delivered head and the
# verification disposition are read from the canonical task.md `deliverable`
# block (deliverable.head_sha + deliverable.verification.status), resolved by
# work_item_id through the single canonical resolve-task-md.sh (so a task.md
# that moved to pr-release/ or container archive after delivery still resolves).
# The three-layer local pre-push gate makes the pushed head verified-by-
# construction, so the persisted task.md head is the delivered-head authority —
# the probe NEVER falls back to a mutable branch ref. The breakdown stage still
# reads the task-snapshot marker (planning freshness, untouched); the amendment
# loop still reads spec-issue-{id}-{head}.json (distinct from ac-verification).
#
# DP-313 T1: at the engineering stage, AFTER the completion-gate marker is PASS,
# the probe optionally consumes a review-state classification supplied as
# EXPLICIT INPUT via --pr-state-file (a fixture / classifier-output JSON; the
# probe NEVER calls gh or any network itself). When the review state is
# actionable it routes back to the owning skill (engineering revision /
# breakdown / refinement amendment); otherwise it stays at parity with current
# behaviour and continues to verify-AC.
#
# DP-313 T3 (AC-NEG2): when --pr-state-file IS supplied (the orchestrator
# attempted a review-state read) but the state is UNAVAILABLE — the file is
# missing / unreadable / not JSON, or it explicitly signals gh/PR-state
# unavailability (tool_missing:true, or pr_state:UNKNOWN with no readiness) —
# the probe FAILS CLOSED: it writes POLARIS_TOOL_MISSING to stderr and exits 3
# instead of silently continuing to verify-AC and declaring the work item
# complete. Omitting --pr-state-file entirely is NOT a failure (parity,
# AC-NEG1): no review-state was requested, so the probe continues to verify-AC.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-probe.sh DP-NNN
  scripts/auto-pass-probe.sh --stage source --source-id DP-NNN [--repo PATH] [--ledger /absolute/path/to/ledger.json]
  scripts/auto-pass-probe.sh --stage breakdown|engineering|verify-AC
    --source-id DP-NNN --work-item-id DP-NNN-T1 [--repo PATH]
    [--head-sha SHA] [--ledger /absolute/path/to/ledger.json]
    [--pr-state-file /absolute/path/to/review-state.json]
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --pr-state-file) PR_STATE_FILE="${2:-}"; shift 2 ;;
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

SCRIPT_DIR_RESOLVED="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$SCRIPT_DIR_RESOLVED/spec-source-resolver.sh"
TASK_MD_RESOLVER="$SCRIPT_DIR_RESOLVED/resolve-task-md.sh"
TASK_MD_PARSER="$SCRIPT_DIR_RESOLVED/parse-task-md.sh"
PR_OWNERSHIP_GATE="$SCRIPT_DIR_RESOLVED/auto-pass-pr-ownership-gate.sh"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_probe_1.py" "$REPO" "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" "$RESOLVER" "$PR_STATE_FILE" "$TASK_MD_RESOLVER" "$TASK_MD_PARSER" "$PR_OWNERSHIP_GATE"
