#!/usr/bin/env bash
# Purpose: Claude Code PreToolUse adapter for lazy repo handbook loading.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
VALIDATOR="${POLARIS_HANDBOOK_VALIDATOR:-$PROJECT_DIR/scripts/validate-handbook-load-gate.sh}"
PAYLOAD="$(cat || true)"

path="$(python3 - "$PAYLOAD" <<'PY'
import json, sys
try:
    payload = json.loads(sys.argv[1] or "{}")
except Exception:
    payload = {}
tool_input = payload.get("tool_input") or payload.get("input") or {}
for key in ("file_path", "path", "notebook_path"):
    value = tool_input.get(key)
    if isinstance(value, str) and value:
        print(value)
        break
PY
)"
[[ -n "$path" ]] || exit 0

args=(--repo "$PROJECT_DIR" --path "$path")
[[ -n "${POLARIS_PROJECT:-}" ]] && args+=(--project "$POLARIS_PROJECT")
[[ -n "${POLARIS_SESSION_ID:-}" ]] && args+=(--session-id "$POLARIS_SESSION_ID")
[[ -n "${POLARIS_HANDBOOK_RESOLVER:-}" ]] && args+=(--resolver "$POLARIS_HANDBOOK_RESOLVER")
context="$("$VALIDATOR" "${args[@]}")"
[[ -n "$context" ]] || exit 0

python3 - "$context" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": "Polaris project handbook resolved before mutation: " + sys.argv[1],
    }
}, ensure_ascii=False))
PY
