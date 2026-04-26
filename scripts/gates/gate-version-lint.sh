#!/usr/bin/env bash
set -euo pipefail

# gate-version-lint.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from .claude/hooks/version-docs-lint-gate.sh for cross-LLM portability.
# Can be called from: git pre-commit hooks, or directly.
#
# Usage:
#   bash scripts/gates/gate-version-lint.sh [--repo <path>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_DOCS_LINT=1

PREFIX="[polaris gate-version-lint]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-version-lint.sh [--repo <path>]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
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
if [[ "${POLARIS_SKIP_DOCS_LINT:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_DOCS_LINT=1 — bypassing." >&2
  exit 0
fi

# Only applies to repos with a VERSION file
[[ -f "$REPO_ROOT/VERSION" ]] || exit 0

# Check if VERSION is in staged files
staged=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || true)
if ! echo "$staged" | grep -q '^VERSION$'; then
  exit 0
fi

# VERSION is staged — lint script must exist
lint_script="$REPO_ROOT/scripts/readme-lint.py"
if [[ ! -f "$lint_script" ]]; then
  exit 0
fi

# Run readme-lint
echo "$PREFIX VERSION staged — running readme-lint.py ..." >&2
lint_output=$(python3 "$lint_script" 2>&1) || {
  cat >&2 <<EOF

$PREFIX BLOCKED: VERSION is staged but docs are out of sync.

readme-lint.py output:
$lint_output

Fix: run /docs-sync to update documentation, then re-stage and commit.
  Or: POLARIS_SKIP_DOCS_LINT=1 to bypass (not recommended).
EOF
  exit 2
}

echo "$PREFIX ✅ readme-lint passed." >&2
exit 0
