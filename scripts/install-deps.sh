#!/usr/bin/env bash
# install-deps.sh — compatibility wrapper for Polaris framework dependencies
#
# Installs node_modules for framework tools (E2E, Mockoon).
# Called by /init and sync-from-polaris.sh after version upgrades.
#
# Usage:
#   scripts/install-deps.sh              # Install all
#   scripts/install-deps.sh --check      # Check status only (no install)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  --check)
    exec bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" doctor --required
    ;;
  "" )
    exec bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" install --required
    ;;
  *)
    echo "usage: $0 [--check]" >&2
    echo "This compatibility wrapper delegates to scripts/polaris-toolchain.sh." >&2
    exit 2
    ;;
esac
