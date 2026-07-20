#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python delivery-evidence conformance authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_delivery_evidence_conformance_1.py" "$@"
