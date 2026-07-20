#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python mise dependency-change authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_mise_dependency_change_1.py" "$@"
