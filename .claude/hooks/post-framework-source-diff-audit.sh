#!/usr/bin/env bash
# Purpose: Claude Code PostToolUse diff audit adapter for framework source writes.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
VALIDATOR="$PROJECT_DIR/scripts/validate-framework-source-write.sh"
PAYLOAD="$(cat || true)"

mapfile -t PATHS < <(python3 - "$PAYLOAD" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1] or "{}")
except Exception:
    payload = {}

tool_input = payload.get("tool_input") or payload.get("input") or {}
paths = []
for key in ("path", "file_path", "notebook_path"):
    value = tool_input.get(key)
    if isinstance(value, str):
        paths.append(value)
for edit in tool_input.get("edits") or []:
    if isinstance(edit, dict):
        value = edit.get("file_path") or edit.get("path")
        if isinstance(value, str):
            paths.append(value)
for value in paths:
    print(value)
PY
)

if [[ "${#PATHS[@]}" -eq 0 ]]; then
  exit 0
fi

ARGS=()
for p in "${PATHS[@]}"; do
  ARGS+=(--changed-file "$p")
done

exec bash "$VALIDATOR" --repo "$PROJECT_DIR" --mode diff-audit --writer claude-posttooluse \
  --task-md "${POLARIS_TASK_MD:-${POLARIS_FRAMEWORK_TASK_MD:-}}" "${ARGS[@]}"
