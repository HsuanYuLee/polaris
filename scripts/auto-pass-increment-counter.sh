#!/usr/bin/env bash
# auto-pass-increment-counter.sh — DP-220 deterministic counter writer.
#
# Increment a named counter under ledger.loop_counters.{transition}. When the
# counter transitions 1 -> 2 (i.e. the same stage retry pattern repeats), emit
# a friction_log[] entry with kind=inner_skill_halt_bypass so /auto-pass has
# durable audit evidence that the orchestrator re-dispatched the same stage
# after an inner skill HALT signal rather than terminal-stopping.
#
# Usage:
#   scripts/auto-pass-increment-counter.sh <ledger.json> \
#     --transition <engineering_to_breakdown|breakdown_to_refinement_inbox|verify_ac_to_engineering> \
#     [--stage <stage>] \
#     [--summary "<override summary>"]
#
# Exit:
#   0 success (counter incremented; friction appended only when threshold crossed)
#   1 invalid input
#   2 ledger missing or unreadable

set -euo pipefail

LEDGER=""
TRANSITION=""
STAGE="engineering"
SUMMARY_OVERRIDE=""

usage() {
  sed -n '3,18p' "$0" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transition) TRANSITION="${2:-}"; shift 2 ;;
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

CROSSED="$(python3 - "$LEDGER" "$TRANSITION" <<'PY'
import json
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
transition = sys.argv[2]

try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    sys.exit(f"ERROR: ledger invalid JSON: {exc}")

if not isinstance(ledger, dict):
    sys.exit("ERROR: ledger root must be an object")

counters = ledger.get("loop_counters")
if counters is None:
    counters = {}
    ledger["loop_counters"] = counters
elif not isinstance(counters, dict):
    sys.exit("ERROR: ledger.loop_counters must be an object")

previous = int(counters.get(transition, 0))
current = previous + 1
counters[transition] = current

tmp = ledger_path.with_suffix(ledger_path.suffix + ".tmp")
tmp.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
tmp.replace(ledger_path)

# Emit "1" only on the 1 -> 2 transition (counter became 2). This is the
# canonical "stage retry" friction trigger; subsequent increments are tracked
# by the counter itself but do not append additional friction entries (cap is
# enforced upstream in auto-pass-probe.sh ledger_terminal()).
print("1" if previous == 1 else "0")
PY
)"

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
