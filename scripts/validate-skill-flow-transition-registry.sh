#!/usr/bin/env bash
# Purpose: 驗證可觀測的 skill-flow transition 紀錄及其 callable ownership。
# Inputs: 可選的 registry path；預設為 scripts/lib/skill-flow-transition-registry.json。
# Outputs: registry 有效時輸出 PASS；否則彙整 POLARIS_* error 並 exit 2。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
用法：scripts/validate-skill-flow-transition-registry.sh [--source-closeout] [REGISTRY_PATH]
      scripts/validate-skill-flow-transition-registry.sh --describe-authority
USAGE
  exit 0
fi

SOURCE_CLOSEOUT=0
DESCRIBE_AUTHORITY=0
REGISTRY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-closeout)
      SOURCE_CLOSEOUT=1
      shift
      ;;
    --describe-authority)
      DESCRIBE_AUTHORITY=1
      shift
      ;;
    --*)
      echo "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID_ARGUMENT:$1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$REGISTRY" ]]; then
        echo "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID_ARGUMENT_COUNT" >&2
        exit 2
      fi
      REGISTRY="$1"
      shift
      ;;
  esac
done

if [[ "$DESCRIBE_AUTHORITY" -eq 1 ]]; then
  if [[ "$SOURCE_CLOSEOUT" -eq 1 || -n "$REGISTRY" ]]; then
    echo "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID_AUTHORITY_INTROSPECTION" >&2
    exit 2
  fi
  command printf '%s\n' '{"authority_id":"observable_skill_flow_transition_registry","registry":"scripts/lib/skill-flow-transition-registry.json","validator":"scripts/validate-skill-flow-transition-registry.sh"}'
  exit 0
fi

REGISTRY="${REGISTRY:-$ROOT_DIR/scripts/lib/skill-flow-transition-registry.json}"
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "修復：執行 'mise install'（或依序執行 'mise run bootstrap' 與 'mise run doctor -- --profile runtime'）。" >&2
  exit 2
}

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_skill_flow_transition_registry_1.py" "$ROOT_DIR" "$REGISTRY" "$SOURCE_CLOSEOUT"
