#!/usr/bin/env bash
# codex-guarded-gh-pr-create.sh
# Codex fallback command gate for gh pr create.
#
# Delegates to polaris-pr-create.sh so Codex fallback uses the same complete
# PR gate set as the engineering flow:
#  - work-source-required
#  - base-check
#  - verification evidence
#  - ci-local
#  - no tracked local specs
#  - PR title/body/template/language
#  - changeset
#
# Usage:
#   codex-guarded-gh-pr-create.sh [--dry-run] [gh pr create args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

REPO_PATH="${GATE_PROJECT_DIR:-$(pwd)}"
POLARIS_ARGS=(--repo "$REPO_PATH")
if [[ "$dry_run" == true ]]; then
  POLARIS_ARGS+=(--dry-run)
fi

exec "$ROOT_DIR/scripts/polaris-pr-create.sh" "${POLARIS_ARGS[@]}" -- "$@"
