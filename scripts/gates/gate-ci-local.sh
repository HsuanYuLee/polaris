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

head_sha=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
canonical_script="$(ci_local_path_for_repo "$REPO_ROOT" 2>/dev/null || true)"
legacy_script="$(ci_local_legacy_path_for_repo "$REPO_ROOT" 2>/dev/null || true)"

if [[ -z "$canonical_script" || ! -f "$canonical_script" ]]; then
  if [[ -n "$legacy_script" && -f "$legacy_script" ]]; then
    echo "$PREFIX BLOCKED: repo-local legacy ci-local exists but workspace-owned canonical script is missing." >&2
    echo "$PREFIX canonical: ${canonical_script:-<unresolved>}" >&2
    echo "$PREFIX legacy:    $legacy_script" >&2
    echo "$PREFIX Run: bash ${SCRIPT_DIR}/../ci-local-generate.sh --repo ${REPO_ROOT} --force, then remove the legacy repo-local script." >&2
    exit 2
  fi
  echo "$PREFIX NO_CI_LOCAL_CONFIGURED — skipped (canonical=${canonical_script:-<unresolved>})." >&2
  exit 0
fi

# Run ci-local.sh synchronously. The generated script owns context-aware
# evidence caching because the cache key includes base/event/source/ref.
echo "$PREFIX Running ci-local on ${branch} ..." >&2
ci_log="${REPO_ROOT}/.polaris-ci-local-gate.log"

if bash "$SCRIPT_DIR/../ci-local-run.sh" --repo "$REPO_ROOT" >"$ci_log" 2>&1; then
  rm -f "$ci_log"
  echo "$PREFIX ci-local.sh passed." >&2
  exit 0
fi

rc=$?
echo "" >&2
if grep -q "BLOCKED_ENV" "$ci_log"; then
  echo "$PREFIX BLOCKED_ENV: ci-local.sh was blocked by local network/dependency infrastructure for ${branch} @ ${head_sha} (exit ${rc})" >&2
  echo "$PREFIX This remains a hard delivery block. Use the RETRY_WITH_ESCALATION payload below, or remediate VPN/proxy/registry access and rerun." >&2
else
  echo "$PREFIX BLOCKED: ci-local.sh FAILED for ${branch} @ ${head_sha} (exit ${rc})" >&2
fi
echo "" >&2
tail -60 "$ci_log" >&2
echo "" >&2
echo "  Full log: ${ci_log}" >&2
echo "  Re-run:   bash ${SCRIPT_DIR}/../ci-local-run.sh --repo ${REPO_ROOT}" >&2
exit 2
