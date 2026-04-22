#!/usr/bin/env bash
# Claude PreToolUse wrapper for pipeline artifact schema gate (DP-025).
# Delegates logic to runtime-agnostic entrypoint.

set -euo pipefail

WORKSPACE_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
exec bash "$WORKSPACE_ROOT/scripts/pipeline-artifact-gate.sh" "$@"
