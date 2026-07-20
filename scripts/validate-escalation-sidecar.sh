#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python engineering escalation sidecar authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_escalation_sidecar_1.py" "$@"
