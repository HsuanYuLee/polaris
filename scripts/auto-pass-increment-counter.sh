#!/usr/bin/env bash
# auto-pass-increment-counter.sh — DP-220 deterministic counter writer.
#
# Increment a named counter under ledger.loop_counters.{transition}. When the
# counter transitions 1 -> 2 (i.e. the same stage retry pattern repeats), emit
# a friction_log[] entry with kind=inner_skill_halt_bypass so /auto-pass has
# durable audit evidence that the orchestrator re-dispatched the same stage
# after an inner skill HALT signal rather than terminal-stopping.
#
# DP-246 T2: --evidence-id is now REQUIRED. Callers must pass a stable
# transition-key such as "<source>:<from>-><to>:<seq>" to guarantee idempotency.
# Duplicate evidence_id for the same transition -> silent exit 0 (no increment).
#
# Usage:
#   scripts/auto-pass-increment-counter.sh <ledger.json> \
#     --transition <engineering_to_breakdown|breakdown_to_refinement_inbox|verify_ac_to_engineering> \
#     --evidence-id <stable-transition-key> \
#     [--stage <stage>] \
#     [--summary "<override summary>"]
#
# Exit:
#   0 success (counter incremented; friction appended only when threshold crossed)
#   0 duplicate evidence-id (idempotent no-op; counter and friction unchanged)
#   1 invalid input / missing --evidence-id
#   2 ledger missing or unreadable

set -euo pipefail

LEDGER=""
TRANSITION=""
EVIDENCE_ID=""
STAGE="engineering"
SUMMARY_OVERRIDE=""

usage() {
  sed -n '3,27p' "$0" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transition) TRANSITION="${2:-}"; shift 2 ;;
    --evidence-id) EVIDENCE_ID="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --summary) SUMMARY_OVERRIDE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage ;;
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

if [[ -z "$LEDGER" || -z "$TRANSITION" ]]; then
  echo "ERROR: ledger path and --transition are required" >&2
  usage
fi

# DP-246 AC-NEG2: --evidence-id is required; no ENV bypass allowed.
if [[ -z "$EVIDENCE_ID" ]]; then
  echo "POLARIS_COUNTER_EVIDENCE_ID_REQUIRED: --evidence-id is required (DP-246 AC-NEG2)" >&2
  exit 1
fi

case "$TRANSITION" in
  engineering_to_breakdown|breakdown_to_refinement_inbox|verify_ac_to_engineering) ;;
  *) echo "ERROR: --transition must be one of engineering_to_breakdown|breakdown_to_refinement_inbox|verify_ac_to_engineering" >&2; exit 1 ;;
esac

if [[ ! -f "$LEDGER" ]]; then
  if [[ "${POLARIS_FRICTION_DEBUG:-0}" == "1" ]]; then
    echo "auto-pass-increment-counter: NOOP (ledger not found: $LEDGER)" >&2
  fi
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRICTION_HELPER="$SCRIPT_DIR/append-auto-pass-friction.sh"

CROSSED="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_increment_counter_1.py" "$LEDGER" "$TRANSITION" "$EVIDENCE_ID"
)"

if [[ "$CROSSED" == "DUPLICATE" ]]; then
  if [[ "${POLARIS_FRICTION_DEBUG:-0}" == "1" ]]; then
    echo "auto-pass-increment-counter: NOOP (duplicate evidence-id: $EVIDENCE_ID)" >&2
  fi
  exit 0
fi

if [[ "$CROSSED" == "1" ]]; then
  if [[ -n "$SUMMARY_OVERRIDE" ]]; then
    SUMMARY="$SUMMARY_OVERRIDE"
  else
    SUMMARY="stage retry: transition=$TRANSITION counter=2 (auto-trigger from auto-pass-increment-counter, DP-220)"
  fi
  bash "$FRICTION_HELPER" "$LEDGER" \
    --stage "$STAGE" \
    --kind inner_skill_halt_bypass \
    --summary "$SUMMARY" \
    >/dev/null 2>&1 || true
fi

exit 0
