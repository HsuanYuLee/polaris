#!/usr/bin/env bash
# Purpose: 從 canonical registry 解析一筆可觀測的 skill-flow transition。
# Inputs: --id TRANSITION_ID，可選的 --registry PATH 與 --field DOT_PATH。
# Outputs: transition JSON（或指定欄位）；無效或缺少紀錄時 exit 2。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$ROOT_DIR/scripts/lib/skill-flow-transition-registry.json"
VALIDATOR="$ROOT_DIR/scripts/validate-skill-flow-transition-registry.sh"
TRANSITION_ID=""
FIELD=""

usage() {
  local exit_code="${1:-2}"
  local output_fd=2
  [[ "$exit_code" -eq 0 ]] && output_fd=1
  cat >&"$output_fd" <<'USAGE'
用法：scripts/resolve-skill-flow-transition.sh --id TRANSITION_ID [--registry PATH] [--field DOT_PATH]
USAGE
  exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id|--registry|--field)
      option="$1"
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "POLARIS_SKILL_FLOW_TRANSITION_OPTION_VALUE_REQUIRED:$option" >&2
        exit 2
      fi
      case "$option" in
        --id) TRANSITION_ID="$2" ;;
        --registry) REGISTRY="$2" ;;
        --field) FIELD="$2" ;;
      esac
      shift 2
      ;;
    --help|-h) usage 0 ;;
    *) echo "POLARIS_SKILL_FLOW_TRANSITION_RESOLVE_INVALID_ARGUMENT:$1" >&2; usage ;;
  esac
done

[[ -n "$TRANSITION_ID" ]] || {
  echo "POLARIS_SKILL_FLOW_TRANSITION_ID_REQUIRED" >&2
  exit 2
}
[[ -f "$REGISTRY" ]] || {
  echo "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_MISSING:$REGISTRY" >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "修復：執行 'mise install'（或依序執行 'mise run bootstrap' 與 'mise run doctor -- --profile runtime'）。" >&2
  exit 2
}

# Resolver 先呼叫 validator，讓 registry validity 只有一個權威來源。
bash "$VALIDATOR" "$REGISTRY" >/dev/null

python3 - "$REGISTRY" "$TRANSITION_ID" "$FIELD" <<'PY'
import json
import sys
from pathlib import Path

registry_path, transition_id, field = sys.argv[1:4]
try:
    payload = json.loads(Path(registry_path).read_text(encoding="utf-8"))
except Exception as exc:
    print(f"POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:{exc}", file=sys.stderr)
    raise SystemExit(2)

matches = [
    row for row in payload.get("transitions", [])
    if isinstance(row, dict) and row.get("id") == transition_id
]
if len(matches) != 1:
    print(
        f"POLARIS_SKILL_FLOW_TRANSITION_NOT_UNIQUE:{transition_id}:matches={len(matches)}",
        file=sys.stderr,
    )
    raise SystemExit(2)

value = matches[0]
if field:
    for segment in field.split("."):
        if not isinstance(value, dict) or segment not in value:
            print(
                f"POLARIS_SKILL_FLOW_TRANSITION_FIELD_MISSING:{transition_id}:{field}",
                file=sys.stderr,
            )
            raise SystemExit(2)
        value = value[segment]

if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
