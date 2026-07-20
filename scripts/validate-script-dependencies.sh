#!/usr/bin/env bash
# Validate framework script dependencies against Polaris-managed contracts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="diff"
BASE_BRANCH=""
PATHS=()

usage() {
  cat <<'EOF'
Usage:
  scripts/validate-script-dependencies.sh [--mode diff|audit] [--base <ref>] [--path <script>]...

Checks framework scripts for unmanaged third-party dependencies.

Modes:
  diff   blocking mode for changed scripts
  audit  advisory mode for a wider scan; reports issues but exits 0

Baseline / allowlist entries must use the shared DP-184 D8 schema:
  owner, reason, remediation_task, expiry, scope
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --base)
      BASE_BRANCH="${2:-}"
      shift 2
      ;;
    --path)
      PATHS+=("${2:-}")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$MODE" in
  diff|audit) ;;
  *) echo "invalid --mode: $MODE" >&2; exit 2 ;;
esac

PY_ARGS=("$ROOT_DIR" "$MODE" "$BASE_BRANCH")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_script_dependencies_1.py" "${PY_ARGS[@]}"
