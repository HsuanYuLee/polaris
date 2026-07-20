#!/usr/bin/env bash
# 相容入口；template resolution 由 Python module 負責。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/refinement_resolve_template.py" "$@"
