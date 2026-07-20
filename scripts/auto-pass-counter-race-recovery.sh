#!/usr/bin/env bash
# auto-pass-counter-race-recovery.sh — DP-246 T3 canonical surgical recovery path.
#
# When an auto-pass run terminates with loop_cap_reached and there is evidence
# that the counter was over-incremented due to a race condition (duplicate
# orchestration sessions writing the same transition without idempotency
# guards), this helper creates a corrected ledger that resets loop_counters to
# the actual back-edge count observed in stage_events, carries forward the old
# evidence_ids[] as already-accounted, and writes a COUNTER_RACE_RECOVERY audit
# entry to stage_events.
#
# This script is TERMINAL-ONLY.  It must never be called during an active
# orchestration loop; doing so would defeat the cap enforcement that protects
# against runaway retries.
#
# Three preconditions are checked (all must pass; any failure → exit 1):
#
#   (a) Prior ledger terminal_status == "loop_cap_reached"
#   (b) Prior ledger friction_log[] contains at least one stage_retry entry
#       (kind == inner_skill_halt_bypass or kind == stage_retry)
#   (c) Actual back-edge count computed from stage_events < cap (3)
#
# 24h rate-limit: a recovery is not allowed more than once per source per
# rolling 24-hour window.  The helper writes a stamp file at
#   {source_container}/.polaris/counter-race-recovery-last.json
# and checks mtime / "ts" field on each invocation.
#
# Usage:
#   scripts/auto-pass-counter-race-recovery.sh \
#     --source-id DP-NNN \
#     --prior-ledger /absolute/path/to/ledger.json \
#     [--repo /absolute/path/to/repo-root]
#
# Output:
#   Writes new ledger to same directory as prior-ledger with timestamp suffix:
#   {dir}/YYYYMMDD-HHMMSS-ledger.json
#   Prints path of new ledger to stdout on success.
#
# Exit:
#   0 success — new ledger written; path printed to stdout
#   1 precondition failure — stderr contains POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED
#   2 usage/environment error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SCRIPT_DIR%/scripts}"

SOURCE_ID=""
PRIOR_LEDGER=""

usage() {
  sed -n '3,38p' "$0" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --prior-ledger) PRIOR_LEDGER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage ;;
    *) echo "ERROR: unexpected argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$SOURCE_ID" || -z "$PRIOR_LEDGER" ]]; then
  echo "ERROR: --source-id and --prior-ledger are required" >&2
  usage
fi

if [[ ! -f "$PRIOR_LEDGER" ]]; then
  echo "POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED: prior ledger not found: $PRIOR_LEDGER" >&2
  exit 1
fi

# Delegate all logic to Python so bash arithmetic edge-cases don't matter.
NEW_LEDGER_PATH="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_counter_race_recovery_1.py" "$SOURCE_ID" "$PRIOR_LEDGER" "$REPO" "$SCRIPT_DIR"
)"

echo "$NEW_LEDGER_PATH"
