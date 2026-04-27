#!/usr/bin/env bash
set -euo pipefail

# gate-ci-local.sh — Portable git-hook gate (DP-032 Wave δ + DP-043).
# Extracted from .claude/hooks/ci-local-gate.sh for cross-LLM portability.
# Can be called from: git pre-commit/pre-push hooks, polaris-pr-create.sh, or directly.
#
# Usage:
#   bash scripts/gates/gate-ci-local.sh [--repo <path>] [--push-mode]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_CI_LOCAL=1

PREFIX="[polaris gate-ci-local]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/ci-local-path.sh
. "$SCRIPT_DIR/../lib/ci-local-path.sh"

REPO_ROOT=""
PUSH_MODE=0

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --push-mode) PUSH_MODE=1; shift ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-ci-local.sh [--repo <path>] [--push-mode]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
      echo "  --push-mode     Only run on task/* and fix/* branches"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Default repo
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Bypass
if [[ "${POLARIS_SKIP_CI_LOCAL:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_CI_LOCAL=1 — bypassing (emergency only)" >&2
  exit 0
fi

# Repo must have ci-local.sh to be onboarded (DP-043: located in .claude/scripts/)
CI_LOCAL_ABS="$(ci_local_path_for_repo "$REPO_ROOT")"
[[ -f "$CI_LOCAL_ABS" ]] || exit 0

# Branch detection
branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)

# Push mode: only run on task/* and fix/* branches
if [[ "$PUSH_MODE" -eq 1 ]]; then
  case "$branch" in
    task/*|fix/*) ;;
    *)
      exit 0
      ;;
  esac
fi

# Compute evidence path
branch_slug=$(printf '%s' "$branch" | tr '/' '-')
head_sha=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
evidence="/tmp/polaris-ci-local-${branch_slug}-${head_sha}.json"

# Cache hit?
if [[ -f "$evidence" ]]; then
  cached_status=$(python3 -c "
import json
try:
    with open('${evidence}') as f:
        d = json.load(f)
    assert d.get('branch') == '${branch}' and d.get('head_sha') == '${head_sha}'
    print(d.get('status', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
  if [[ "$cached_status" == "PASS" ]]; then
    echo "$PREFIX ✅ Cache hit (${evidence##*/}) — skipping." >&2
    exit 0
  fi
fi

# Cache miss / FAIL → run ci-local.sh synchronously
echo "$PREFIX Running ${CI_LOCAL_ABS} on ${branch} ..." >&2
ci_log="${REPO_ROOT}/.polaris-ci-local-gate.log"

if bash "$CI_LOCAL_ABS" >"$ci_log" 2>&1; then
  rm -f "$ci_log"
  echo "$PREFIX ✅ ci-local.sh passed." >&2
  exit 0
fi

rc=$?
echo "" >&2
echo "$PREFIX BLOCKED: ci-local.sh FAILED for ${branch} @ ${head_sha} (exit ${rc})" >&2
echo "" >&2
tail -60 "$ci_log" >&2
echo "" >&2
echo "  Full log: ${ci_log}" >&2
echo "  Re-run:   bash ${CI_LOCAL_ABS}" >&2
exit 2
