#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD_SELFTEST=1 bash "$SCRIPT_DIR/parse-task-md.sh"
