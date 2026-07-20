#!/usr/bin/env bash
# Purpose: 稽核受治理 script prose producer 是否遵從 workspace-config language。
#          會標出外部寫入 callsite 與硬編 prose 預設；producer 必須讀取 workspace
#          language、對具體 body 跑 language/external-write gate，或登錄 callsite 例外。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXCEPTIONS_PATH=""
MODE="repo"
QUIET=0
PATHS=()

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/validate-config-driven-authoring.sh [--root <repo>] [--exceptions <json>] [--quiet] [--path <file> ...]

稽核 framework scripts 中必須遵從 workspace language 的 external-write /
generated-prose callsite。每筆 finding 都需要相鄰 language gate、
workspace-config language read，或 callsite-level exception。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="${2:-}"; shift 2 ;;
    --exceptions) EXCEPTIONS_PATH="${2:-}"; shift 2 ;;
    --path) PATHS+=("${2:-}"); MODE="paths"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
if [[ -z "$EXCEPTIONS_PATH" ]]; then
  EXCEPTIONS_PATH="$ROOT_DIR/scripts/lib/config-driven-authoring-exceptions.json"
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_config_driven_authoring_1.py" "$ROOT_DIR" "$EXCEPTIONS_PATH" "$MODE" "$QUIET" "${PATHS[@]+"${PATHS[@]}"}"
