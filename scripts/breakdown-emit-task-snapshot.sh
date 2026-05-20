#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/breakdown-emit-task-snapshot.sh --source-id DP-NNN --work-item-id DP-NNN-Tn --task-md PATH [--status STATUS] [--out PATH]

Emits a breakdown-owned task_snapshot marker under .polaris/evidence/task-snapshot/.
USAGE
  exit 2
}

SOURCE_ID=""
WORK_ITEM_ID=""
TASK_MD=""
STATUS="PASS"
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$SOURCE_ID" && -n "$WORK_ITEM_ID" && -n "$TASK_MD" ]] || usage
[[ -f "$TASK_MD" ]] || { echo "ERROR: task-md not found: $TASK_MD" >&2; exit 2; }

if [[ -z "$OUT" ]]; then
  OUT=".polaris/evidence/task-snapshot/${WORK_ITEM_ID}.json"
fi

mkdir -p "$(dirname "$OUT")"

python3 - "$SOURCE_ID" "$WORK_ITEM_ID" "$TASK_MD" "$STATUS" "$OUT" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

source_id, work_item_id, task_md, status, out = sys.argv[1:6]
task_path = Path(task_md)
payload = {
    "schema_version": 1,
    "marker_kind": "task_snapshot",
    "writer": "breakdown",
    "owning_skill": "breakdown",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": status,
    "freshness": {
        "task_artifact_sha256": hashlib.sha256(task_path.read_bytes()).hexdigest(),
        "source_artifact": task_path.as_posix(),
    },
    "task_md": task_path.as_posix(),
    "at": datetime.now(timezone.utc).isoformat(),
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"WROTE: {out}")
PY
