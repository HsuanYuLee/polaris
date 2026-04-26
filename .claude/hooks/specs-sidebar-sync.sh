#!/usr/bin/env bash
# Claude PostToolUse wrapper for docs-viewer sidebar sync.
# Delegates logic to runtime-agnostic entrypoint.

set -euo pipefail

WORKSPACE_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
exec bash "$WORKSPACE_ROOT/scripts/docs-viewer-sync-hook.sh" "$WORKSPACE_ROOT"
