#!/usr/bin/env bash
# Purpose: emit a breakdown-owned durable blocker marker (validation_fail /
#          missing_v_task) under .polaris/evidence/ when breakdown cannot
#          materialize a legal task set (DP-269 D4 / AC3).
# Inputs:  --source-id, --work-item-id, --marker-kind {validation_fail|missing_v_task},
#          --reason "<specific human-readable cause>", [--out PATH]
# Outputs: writes the marker JSON; prints WROTE: <path>. Exit 2 on usage error.
#
# Models scripts/breakdown-emit-task-snapshot.sh — a deterministic producer
# script writes the marker so it bypasses the no-direct-evidence-write hook
# (the hook excludes .polaris/evidence/** written by registered producer
# scripts). auto-pass-probe.sh reads validation-fail/{id}.json and
# missing-v-task/{id}.json and surfaces the marker's own `reason` so the
# orchestrator reports a specific blocked_by_gate_failure cause instead of the
# generic "breakdown PASS marker missing".

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/breakdown-emit-blocker-marker.sh --source-id DP-NNN --work-item-id DP-NNN-Tn \
    --marker-kind validation_fail|missing_v_task --reason "<specific cause>" [--out PATH]

Emits a breakdown-owned blocker marker under
  .polaris/evidence/validation-fail/{work-item-id}.json   (validation_fail)
  .polaris/evidence/missing-v-task/{work-item-id}.json     (missing_v_task)
USAGE
  exit 2
}

SOURCE_ID=""
WORK_ITEM_ID=""
MARKER_KIND=""
REASON=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --marker-kind) MARKER_KIND="${2:-}"; shift 2 ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$SOURCE_ID" && -n "$WORK_ITEM_ID" && -n "$MARKER_KIND" && -n "$REASON" ]] || usage

case "$MARKER_KIND" in
  validation_fail) SUBDIR="validation-fail" ;;
  missing_v_task)  SUBDIR="missing-v-task" ;;
  *) echo "ERROR: --marker-kind must be validation_fail or missing_v_task (got: $MARKER_KIND)" >&2; usage ;;
esac

if [[ -z "$OUT" ]]; then
  OUT=".polaris/evidence/${SUBDIR}/${WORK_ITEM_ID}.json"
fi

mkdir -p "$(dirname "$OUT")"

python3 - "$SOURCE_ID" "$WORK_ITEM_ID" "$MARKER_KIND" "$REASON" "$OUT" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

source_id, work_item_id, marker_kind, reason, out = sys.argv[1:6]
payload = {
    "schema_version": 1,
    "marker_kind": marker_kind,
    "writer": "breakdown",
    "owning_skill": "breakdown",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": "BLOCKED",
    "reason": reason,
    "at": datetime.now(timezone.utc).isoformat(),
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"WROTE: {out}")
PY
