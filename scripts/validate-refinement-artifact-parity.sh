#!/usr/bin/env bash
# 相容入口；結構化驗證由 Python module 負責。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/refinement_validate_artifact_parity.py" "$@"
