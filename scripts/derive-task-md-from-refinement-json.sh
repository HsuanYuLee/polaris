#!/usr/bin/env bash
# Compatibility shim: structured task.md derivation lives in the Python module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/derive_task_md_from_refinement_json.py" "$@"
