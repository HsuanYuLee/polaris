#!/usr/bin/env bash
# Compatibility shim: structured task.md parsing lives in the Python module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/parse_task_md.py" "$@"
