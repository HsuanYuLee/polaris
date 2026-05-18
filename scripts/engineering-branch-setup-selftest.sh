#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ENGINEERING_BRANCH_SETUP_SELFTEST=1 bash "$SCRIPT_DIR/engineering-branch-setup.sh"
