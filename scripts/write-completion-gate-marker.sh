#!/usr/bin/env bash
set -euo pipefail

# DP-230 T5 / D18 — framework artifact writers must anchor at the main
# checkout. When this script runs inside a `git worktree add` copy the
# caller's CWD is the worktree, but completion_gate / pr_freshness /
# blocked_conflict / unsupported_mutation / ci_local markers belong to the
# durable .polaris/evidence/ tree under the main checkout. We source the
# shared resolver helper instead of recomputing the rule per writer.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]]; then
  # shellcheck source=lib/main-checkout.sh
  . "$SCRIPT_DIR/lib/main-checkout.sh"
fi

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/write-completion-gate-marker.sh --source-id DP-NNN --work-item-id DP-NNN-Tn --head-sha SHA [--status STATUS] [--task-md PATH] [--out PATH]

Emits an engineering-owned completion_gate marker under
<main-checkout>/.polaris/evidence/completion-gate/.  When invoked inside a
`git worktree add` copy, the marker still lands under the main checkout
(see .claude/skills/references/framework-artifact-writer-convention.md).
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
  # Default OUT: anchor at the main checkout (not caller CWD) so worktree
  # runs do not silently leak markers into <worktree>/.polaris/.
  main_checkout=""
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$(pwd)" 2>/dev/null || true)"
  fi
  if [[ -n "$main_checkout" ]]; then
    OUT="${main_checkout}/.polaris/evidence/completion-gate/${WORK_ITEM_ID}-${HEAD_SHA}.json"
  else
    # No git context (resolver failed) — fall back to legacy CWD-relative
    # path so callers outside a repo (legacy tests, ad hoc shells) still get
    # a useful marker.
    OUT=".polaris/evidence/completion-gate/${WORK_ITEM_ID}-${HEAD_SHA}.json"
  fi
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
