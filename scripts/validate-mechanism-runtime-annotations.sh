#!/usr/bin/env bash
set -euo pipefail

PREFIX="[mechanism-runtime]"
REGISTRY="${1:-.claude/rules/mechanism-registry.md}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/validate-mechanism-runtime-annotations.sh [registry.md]

Validates the DP-188 Runtime Annotation Registry table.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ -f "$REGISTRY" ]] || { echo "$PREFIX registry not found: $REGISTRY" >&2; exit 2; }

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_mechanism_runtime_annotations_1.py" "$REGISTRY"
