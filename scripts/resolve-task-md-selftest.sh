#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_TASK_MD_SELFTEST=1 bash "$SCRIPT_DIR/resolve-task-md.sh"
