#!/usr/bin/env bash
# Compatibility shim: task.md validation lives in the Python module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/validate_task_md.py" "$@"
