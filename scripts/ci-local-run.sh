#!/usr/bin/env bash
# ci-local-run.sh — Canonical entry point for running ci-local against current PWD.
#
# DP-043 follow-up. Resolves the canonical ci-local.sh from the main checkout
# (works correctly from inside a worktree) and invokes it with --repo $PWD.
#
# Usage:
#   bash {polaris}/scripts/ci-local-run.sh                   # validates $PWD
#   bash {polaris}/scripts/ci-local-run.sh --repo <path>     # validates <path>
#
# Behavior:
#   - Resolves main checkout via `git rev-parse --git-common-dir`
#   - If main checkout has no `.claude/scripts/ci-local.sh` → exit 0 (skip; consistent
#     with hook/gate's "no ci-local declared" semantics)
#   - Otherwise: bash <main>/.claude/scripts/ci-local.sh --repo <target>
#
# Exit codes: forwarded from ci-local.sh (0 PASS, 1 FAIL, 2 invalid usage).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/main-checkout.sh
. "$SCRIPT_DIR/lib/main-checkout.sh"
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"

TARGET_REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) TARGET_REPO="$2"; shift 2 ;;
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

exec bash "$canonical_script" --repo "$TARGET_REPO"
