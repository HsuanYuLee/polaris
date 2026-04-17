#!/usr/bin/env bash
# codex-guarded-git-push.sh
# Codex fallback command gate for git push.
#
# Runs P0.5 push gate:
#  - pre-push-quality-gate
#
# Usage:
#   codex-guarded-git-push.sh [--dry-run] [git push args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

push_cmd="git push"
if [[ $# -gt 0 ]]; then
  push_cmd="git push $*"
fi

"$ADAPTER" "$ROOT_DIR/.claude/hooks/pre-push-quality-gate.sh" "$push_cmd"

if [[ "$dry_run" == true ]]; then
  echo "PASS: push gate passed (dry-run)"
  exit 0
fi

exec git push "$@"
