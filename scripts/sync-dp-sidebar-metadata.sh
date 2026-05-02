#!/usr/bin/env bash
# Compatibility wrapper for the generic spec sidebar metadata synchronizer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=("$@")
HAS_PATH=0

for arg in "$@"; do
  case "$arg" in
    --check|--apply|-h|--help) ;;
    -*) ;;
    *) HAS_PATH=1 ;;
  esac
done

if [[ "$HAS_PATH" -eq 0 ]]; then
  ARGS+=("docs-manager/src/content/docs/specs/design-plans")
fi

exec "$SCRIPT_DIR/sync-spec-sidebar-metadata.sh" "${ARGS[@]}"
