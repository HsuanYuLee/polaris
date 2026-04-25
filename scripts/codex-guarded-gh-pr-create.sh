#!/usr/bin/env bash
# codex-guarded-gh-pr-create.sh
# Codex fallback command gate for gh pr create.
#
# Runs P0 PR gates:
#  - ci-local-required (Dimension B; D12-c)
#  - verification-evidence-required (Dimension A; runtime/build verify)
#
# Usage:
#   codex-guarded-gh-pr-create.sh [--dry-run] [gh pr create args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

pr_cmd="gh pr create"
if [[ $# -gt 0 ]]; then
  pr_cmd="gh pr create $*"
fi

"$ADAPTER" "$ROOT_DIR/.claude/hooks/ci-local-gate.sh" "$pr_cmd"
"$ADAPTER" "$ROOT_DIR/scripts/verification-evidence-gate.sh" "$pr_cmd"

if [[ "$dry_run" == true ]]; then
  echo "PASS: PR create gate passed (dry-run)"
  exit 0
fi

exec gh pr create "$@"
