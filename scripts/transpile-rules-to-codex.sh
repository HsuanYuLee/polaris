#!/usr/bin/env bash
set -euo pipefail

# Legacy entrypoint kept only for callers during DP-079 migration.
# Source of truth: .claude/instructions/manifest.yaml

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/compile-runtime-instructions.sh" --target codex "$@"
