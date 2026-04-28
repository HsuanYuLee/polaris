#!/usr/bin/env bash
# ci-local-run.sh — Canonical entry point for running ci-local against current PWD.
#
# DP-043 follow-up. Resolves the canonical ci-local.sh from the main checkout
# (works correctly from inside a worktree) and invokes it with --repo $PWD.
#
# Usage:
#   bash {polaris}/scripts/ci-local-run.sh                   # validates $PWD
#   bash {polaris}/scripts/ci-local-run.sh --repo <path>     # validates <path>
#   bash {polaris}/scripts/ci-local-run.sh --repo <path> --base-branch <branch>
#
# Behavior:
#   - Resolves main checkout via `git rev-parse --git-common-dir`
#   - If main checkout has no `.claude/scripts/ci-local.sh` → exit 0 (skip; consistent
#     with hook/gate's "no ci-local declared" semantics)
#   - Otherwise: bash <main>/.claude/scripts/ci-local.sh --repo <target>
#   - If no --base-branch is provided, attempts to resolve the task.md base
#     from the current branch so stacked PR local Codecov checks match CI.
#
# Exit codes: forwarded from ci-local.sh (0 PASS, 1 FAIL, 2 invalid usage).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/main-checkout.sh
. "$SCRIPT_DIR/lib/main-checkout.sh"
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"

TARGET_REPO=""
BASE_BRANCH=""
EVENT=""
SOURCE_BRANCH=""
REF=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) TARGET_REPO="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --source-branch) SOURCE_BRANCH="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,/^set -uo pipefail$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[ci-local-run] Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$TARGET_REPO" ]] && TARGET_REPO="$(pwd)"
TARGET_REPO="$(cd "$TARGET_REPO" 2>/dev/null && pwd)" || {
  echo "[ci-local-run] ERROR: target path not accessible: $TARGET_REPO" >&2
  exit 2
}

main_checkout="$(resolve_main_checkout "$TARGET_REPO")" || {
  echo "[ci-local-run] ERROR: not inside a git repo (target: $TARGET_REPO)" >&2
  exit 2
}

canonical_script="$main_checkout/$CI_LOCAL_RELATIVE_PATH"
if [[ ! -f "$canonical_script" ]]; then
  # Consistent with hook semantics: no ci-local declared → skip silently
  exit 0
fi

if [[ -z "$BASE_BRANCH" ]]; then
  task_md="$(cd "$TARGET_REPO" && bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --current 2>/dev/null | head -1 || true)"
  if [[ -n "$task_md" && -x "$SCRIPT_DIR/resolve-task-base.sh" ]]; then
    BASE_BRANCH="$(bash "$SCRIPT_DIR/resolve-task-base.sh" "$task_md" 2>/dev/null || true)"
  fi
fi

args=(--repo "$TARGET_REPO")
[[ -n "$EVENT" ]] && args+=(--event "$EVENT")
[[ -n "$BASE_BRANCH" ]] && args+=(--base-branch "$BASE_BRANCH")
[[ -n "$SOURCE_BRANCH" ]] && args+=(--source-branch "$SOURCE_BRANCH")
[[ -n "$REF" ]] && args+=(--ref "$REF")

exec bash "$canonical_script" "${args[@]}"
