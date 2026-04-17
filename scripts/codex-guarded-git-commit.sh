#!/usr/bin/env bash
# codex-guarded-git-commit.sh
# Codex fallback command gate for git commit.
#
# Runs P0 commit gates:
#  - quality-evidence-required
#  - version-docs-lint-gate
#
# Usage:
#   codex-guarded-git-commit.sh [--dry-run] [git commit args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if [[ $# -eq 0 ]]; then
  set -- -m "wip: gated commit dry-run placeholder"
fi

commit_cmd="git commit $*"

"$ADAPTER" "$ROOT_DIR/scripts/quality-gate.sh" "$commit_cmd"
"$ADAPTER" "$ROOT_DIR/.claude/hooks/version-docs-lint-gate.sh" "$commit_cmd"

if [[ "$dry_run" == true ]]; then
  echo "PASS: commit gates passed (dry-run)"
  exit 0
fi

exec git commit "$@"
