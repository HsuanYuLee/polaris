#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/doctor-mise-check.sh [--tool <command>]

Outputs one JSON object:
  status: present|missing|blocked_env
  blocker_class: none|mise-missing|mise-managed:<tool>
USAGE
}

json_emit() {
  local status="$1"
  local blocker_class="$2"
  local tool="$3"
  local version="$4"
  local path="$5"
  local remediation="$6"
  python3 - "$status" "$blocker_class" "$tool" "$version" "$path" "$remediation" <<'PY'
import json
import sys

status, blocker_class, tool, version, path, remediation = sys.argv[1:7]
print(json.dumps({
    "schema_version": 1,
    "status": status,
    "blocker_class": blocker_class,
    "tool": tool,
    "version": version,
    "path": path,
    "remediation": remediation,
}, ensure_ascii=False, sort_keys=True))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

if ! command -v mise >/dev/null 2>&1; then
  json_emit "blocked_env" "mise-missing" "${TOOL:-mise}" "" "" "Install mise, reopen shell, then rerun bootstrap/doctor."
  exit 1
fi

mise_path="$(command -v mise)"
if [[ -z "$TOOL" || "$TOOL" == "mise" ]]; then
  version="$(mise --version 2>/dev/null | head -n 1 || true)"
  json_emit "present" "none" "mise" "$version" "$mise_path" ""
  exit 0
fi

tool_path="$(cd "$WORKSPACE_ROOT" && mise exec -- bash -lc "command -v $(printf '%q' "$TOOL")" 2>/dev/null || true)"
if [[ -z "$tool_path" ]]; then
  json_emit "blocked_env" "mise-managed:${TOOL}" "$TOOL" "" "" "Run 'mise install' in the Polaris workspace and retry."
  exit 1
fi

version="$(cd "$WORKSPACE_ROOT" && mise exec -- "$TOOL" --version 2>/dev/null | head -n 1 || true)"
json_emit "present" "none" "$TOOL" "$version" "$tool_path" ""
