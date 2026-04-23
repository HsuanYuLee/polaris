#!/usr/bin/env bash
# codex-guarded-gh-pr-create.sh
# Codex fallback command gate for gh pr create.
#
# Runs P0 PR gate:
#  - verification-evidence-required
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [[ "${POLARIS_SKIP_CI_CONTRACT:-}" != "1" ]]; then
  if [[ "$dry_run" == true ]]; then
    "$SCRIPT_DIR/ci-contract-run.sh" --repo "$repo_root" --skip-install --dry-run >/dev/null
  else
    "$SCRIPT_DIR/ci-contract-run.sh" --repo "$repo_root" --skip-install >/dev/null
  fi
fi

"$ADAPTER" "$ROOT_DIR/scripts/verification-evidence-gate.sh" "$pr_cmd"

if [[ "$dry_run" == true ]]; then
  echo "PASS: PR create gate passed (dry-run)"
  exit 0
fi

exec gh pr create "$@"
