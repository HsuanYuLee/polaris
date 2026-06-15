#!/usr/bin/env bash
# Purpose: emit a breakdown-owned task_snapshot marker, and (--check mode) verify
#          that marker's recorded source_refinement_hash still matches the source's
#          current canonical refinement hash. FD1 (DP-301): binds task_snapshot
#          freshness to the source canonical refinement_hash so a task.md derived
#          before a re-LOCK refinement.json change is caught deterministically.
# Inputs:  emit  → --source-id, --work-item-id, --task-md, [--status], [--out],
#                  [--source-container PATH] [--ledger PATH]
#          check → --check, --source-container PATH, --ledger PATH,
#                  (--marker PATH | --work-item-id ID [--out PATH])
# Outputs: emit  → writes marker JSON; prints WROTE: <path>.
#          check → exit 0 PASS (match or missing-field no-op);
#                  exit 2 + POLARIS_TASK_SNAPSHOT_STALE on hash mismatch.
#          Usage error → exit 2.
#
# Models scripts/breakdown-emit-blocker-marker.sh — a registered deterministic
# producer writes the marker so it bypasses the no-direct-evidence-write hook.
#
# Canonical refinement hash: this script does NOT implement its own hash. It
# reuses scripts/validate-auto-pass-ledger.sh --print-refinement-hash as the
# single canonical producer (DP-301 AC1 / AC-NEG1: no second hash impl).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  emit:
    scripts/breakdown-emit-task-snapshot.sh --source-id DP-NNN --work-item-id DP-NNN-Tn \
      --task-md PATH [--status STATUS] [--out PATH] \
      [--source-container PATH] [--ledger PATH]

  check (staleness):
    scripts/breakdown-emit-task-snapshot.sh --check \
      --source-container PATH --ledger PATH \
      (--marker PATH | --work-item-id DP-NNN-Tn [--out PATH])

Emits a breakdown-owned task_snapshot marker under .polaris/evidence/task-snapshot/.
When --source-container and --ledger are supplied at emit, records the source's
canonical refinement hash (via validate-auto-pass-ledger.sh --print-refinement-hash)
as source_refinement_hash. --check recomputes the current hash and fails closed
(exit 2 + POLARIS_TASK_SNAPSHOT_STALE) when the recorded hash no longer matches.
A marker without source_refinement_hash (pre-FD1) is an additive no-op on --check.
USAGE
  exit 2
}

# Description: Resolve the source's canonical refinement hash by reusing
#              validate-auto-pass-ledger.sh --print-refinement-hash. Does NOT
#              re-implement the hash (DP-301 AC-NEG1).
# Args:        $1 = ledger path (absolute), $2 = source container path (absolute)
# Outputs:     prints the sha256:... hash to stdout; exit 1 + POLARIS_* on failure.
resolve_refinement_hash() {
  local ledger="$1"
  local container="$2"
  local hash
  hash="$(bash "$LEDGER_VALIDATOR" "$ledger" \
    --print-refinement-hash --source-container "$container" 2>/dev/null \
    | grep -m1 '^sha256:' || true)"
  if [[ -z "$hash" ]]; then
    echo "POLARIS_TASK_SNAPSHOT_HASH_UNRESOLVED: could not resolve canonical refinement hash via --print-refinement-hash (ledger=$ledger container=$container)" >&2
    return 1
  fi
  printf '%s\n' "$hash"
}

MODE="emit"
SOURCE_ID=""
WORK_ITEM_ID=""
TASK_MD=""
STATUS="PASS"
OUT=""
SOURCE_CONTAINER=""
LEDGER=""
MARKER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --marker) MARKER="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ "$MODE" == "check" ]]; then
  [[ -n "$SOURCE_CONTAINER" && -n "$LEDGER" ]] || usage
  if [[ -z "$MARKER" ]]; then
    [[ -n "$WORK_ITEM_ID" ]] || usage
    MARKER="${OUT:-.polaris/evidence/task-snapshot/${WORK_ITEM_ID}.json}"
  fi
  [[ -f "$MARKER" ]] || { echo "ERROR: marker not found: $MARKER" >&2; exit 2; }

  recorded_hash="$(python3 - "$MARKER" <<'PY'
import json
import sys
from pathlib import Path

marker = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
freshness = marker.get("freshness") or {}
print(freshness.get("source_refinement_hash") or "")
PY
)"

  if [[ -z "$recorded_hash" ]]; then
    # Pre-FD1 marker without source_refinement_hash: additive no-op (validated
    # when present). Do not synthesize a hash; back-compat must not break.
    echo "PASS: task_snapshot has no source_refinement_hash (pre-FD1 marker); staleness check is a no-op ($MARKER)"
    exit 0
  fi

  current_hash="$(resolve_refinement_hash "$LEDGER" "$SOURCE_CONTAINER")"

  if [[ "$recorded_hash" != "$current_hash" ]]; then
    echo "POLARIS_TASK_SNAPSHOT_STALE: task_snapshot source_refinement_hash is stale" >&2
    echo "  marker:    $MARKER" >&2
    echo "  recorded:  $recorded_hash" >&2
    echo "  current:   $current_hash" >&2
    echo "  source:    $SOURCE_CONTAINER" >&2
    exit 2
  fi

  echo "PASS: task_snapshot source_refinement_hash matches current refinement ($MARKER)"
  exit 0
fi

# emit mode
[[ -n "$SOURCE_ID" && -n "$WORK_ITEM_ID" && -n "$TASK_MD" ]] || usage
[[ -f "$TASK_MD" ]] || { echo "ERROR: task-md not found: $TASK_MD" >&2; exit 2; }

if [[ -z "$OUT" ]]; then
  OUT=".polaris/evidence/task-snapshot/${WORK_ITEM_ID}.json"
fi

REFINEMENT_HASH=""
if [[ -n "$SOURCE_CONTAINER" && -n "$LEDGER" ]]; then
  REFINEMENT_HASH="$(resolve_refinement_hash "$LEDGER" "$SOURCE_CONTAINER")"
fi

mkdir -p "$(dirname "$OUT")"

python3 - "$SOURCE_ID" "$WORK_ITEM_ID" "$TASK_MD" "$STATUS" "$OUT" "$REFINEMENT_HASH" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

source_id, work_item_id, task_md, status, out, refinement_hash = sys.argv[1:7]
task_path = Path(task_md)
freshness = {
    "task_artifact_sha256": hashlib.sha256(task_path.read_bytes()).hexdigest(),
    "source_artifact": task_path.as_posix(),
}
# FD1: bind freshness to the source canonical refinement hash when supplied.
# Field is additive — omitted when no source container/ledger was provided so
# legacy callers and markers stay back-compatible.
if refinement_hash:
    freshness["source_refinement_hash"] = refinement_hash
payload = {
    "schema_version": 1,
    "marker_kind": "task_snapshot",
    "writer": "breakdown",
    "owning_skill": "breakdown",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": status,
    "freshness": freshness,
    "task_md": task_path.as_posix(),
    "at": datetime.now(timezone.utc).isoformat(),
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"WROTE: {out}")
PY
