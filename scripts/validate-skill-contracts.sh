#!/usr/bin/env bash
# Purpose: compatibility CLI for the Python SKILL.md contract authority.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POLARIS_COMPAT_CLI="$0"
exec python3 "$SCRIPT_DIR/lib/validate_skill_contracts_1.py" "$@"
