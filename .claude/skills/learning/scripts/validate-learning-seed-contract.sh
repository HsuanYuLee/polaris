#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python learning/refinement seed authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_learning_seed_contract_1.py" "$@"
