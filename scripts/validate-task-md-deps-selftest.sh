#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_TASK_MD_DEPS_SELFTEST=1 bash "$SCRIPT_DIR/validate-task-md-deps.sh"
