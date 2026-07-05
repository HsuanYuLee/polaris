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
#  - final remote assignee metadata
#  - changeset
#
# Usage:
#   codex-guarded-gh-pr-create.sh [--dry-run] [--task-md <path>] [gh pr create args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

dry_run=false
TASK_MD_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --skip-gates)
      echo "POLARIS_ENGINEERING_NO_BYPASS: --skip-gates is not allowed for Codex PR creation; use scripts/polaris-pr-create.sh with canonical gates" >&2
      exit 2
      ;;
    --task-md)
      TASK_MD_PATH="${2:-}"
      shift 2
      ;;
    --task-md=*)
      TASK_MD_PATH="${1#--task-md=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

REPO_PATH="${GATE_PROJECT_DIR:-$(pwd)}"
POLARIS_ARGS=(--repo "$REPO_PATH")
if [[ "$dry_run" == true ]]; then
  POLARIS_ARGS+=(--dry-run)
fi
if [[ -n "$TASK_MD_PATH" ]]; then
  POLARIS_ARGS+=(--task-md "$TASK_MD_PATH")
fi

exec "$ROOT_DIR/scripts/polaris-pr-create.sh" "${POLARIS_ARGS[@]}" -- "$@"
