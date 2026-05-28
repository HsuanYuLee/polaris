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

CROSSED="$(python3 - "$LEDGER" "$TRANSITION" "$EVIDENCE_ID" <<'PY'
import json
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
transition = sys.argv[2]
evidence_id = sys.argv[3]

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

# Migrate legacy integer shape to new {count, evidence_ids[]} shape.
# Backwards compat: if the value is a plain int, treat it as count=N, evidence_ids=[].
existing = counters.get(transition)
if existing is None:
    entry = {"count": 0, "evidence_ids": []}
elif isinstance(existing, int):
    # Legacy integer format — migrate to new shape, preserving count.
    entry = {"count": existing, "evidence_ids": []}
elif isinstance(existing, dict):
    entry = existing
    if "count" not in entry:
        entry["count"] = 0
    if "evidence_ids" not in entry:
        entry["evidence_ids"] = []
else:
    sys.exit(f"ERROR: loop_counters.{transition} has unexpected type: {type(existing)}")

# DP-246 AC2: duplicate evidence_id -> silent exit 0 (idempotent no-op).
if evidence_id in entry["evidence_ids"]:
    print("DUPLICATE")
    sys.exit(0)

previous = entry["count"]
current = previous + 1
entry["count"] = current
entry["evidence_ids"].append(evidence_id)
counters[transition] = entry

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
