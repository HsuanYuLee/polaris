#!/usr/bin/env bash
# codex-guarded-bash.sh
# Codex fallback command gate for arbitrary Bash execution.
#
# Runs P1 safety gate:
#  - safety-gate
#
# Usage:
#   codex-guarded-bash.sh [--dry-run] -- <command...>
#   codex-guarded-bash.sh [--dry-run] "<command string>"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--dry-run] -- <command...>" >&2
  exit 1
fi

command_string="$*"

"$ADAPTER" "$ROOT_DIR/scripts/safety-gate.sh" "$command_string"

if [[ "$dry_run" == true ]]; then
  echo "PASS: safety gate passed (dry-run)"
  exit 0
fi

exec bash -lc "$command_string"
