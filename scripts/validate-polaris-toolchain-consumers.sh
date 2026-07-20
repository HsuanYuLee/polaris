#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python runtime-tool consumer authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_polaris_toolchain_consumers_1.py" "$@"
