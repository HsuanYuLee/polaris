#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/write-completion-gate-marker.sh --source-id DP-NNN --work-item-id DP-NNN-Tn --head-sha SHA [--status STATUS] [--task-md PATH] [--out PATH]

Emits an engineering-owned completion_gate marker under .polaris/evidence/completion-gate/.
USAGE
  exit 2
}

SOURCE_ID=""
WORK_ITEM_ID=""
HEAD_SHA=""
STATUS="PASS"
TASK_MD=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$SOURCE_ID" && -n "$WORK_ITEM_ID" && -n "$HEAD_SHA" ]] || usage

if [[ -z "$OUT" ]]; then
  OUT=".polaris/evidence/completion-gate/${WORK_ITEM_ID}-${HEAD_SHA}.json"
fi

mkdir -p "$(dirname "$OUT")"

python3 - "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$STATUS" "$TASK_MD" "$OUT" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

source_id, work_item_id, head_sha, status, task_md, out = sys.argv[1:7]
freshness = {"head_sha": head_sha}
if task_md:
    task_path = Path(task_md)
    if not task_path.is_file():
        raise SystemExit(f"ERROR: task-md not found: {task_md}")
    freshness["task_artifact_sha256"] = hashlib.sha256(task_path.read_bytes()).hexdigest()
    freshness["source_artifact"] = task_path.as_posix()

payload = {
    "schema_version": 1,
    "marker_kind": "completion_gate",
    "writer": "engineering",
    "owning_skill": "engineering",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": status,
    "freshness": freshness,
    "at": datetime.now(timezone.utc).isoformat(),
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"WROTE: {out}")
PY
