#!/usr/bin/env bash
set -euo pipefail

# gate-base-check.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from .claude/hooks/pr-base-gate.sh for cross-LLM portability.
# Can be called from: git pre-push hooks, polaris-pr-create.sh, or directly.
#
# Usage:
#   bash scripts/gates/gate-base-check.sh [--repo <path>] [--base <branch>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_PR_BASE_GATE=1

PREFIX="[polaris gate-base-check]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
ACTUAL_BASE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --base) ACTUAL_BASE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-base-check.sh [--repo <path>] [--base <branch>]"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --base <branch>   The intended PR base branch to validate"
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
if [[ "${POLARIS_SKIP_PR_BASE_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_PR_BASE_GATE=1 — bypassing." >&2
  exit 0
fi

# No --base provided → gh will use default, don't block
if [[ -z "$ACTUAL_BASE" ]]; then
  exit 0
fi

# Locate resolver scripts (check repo first, then workspace scripts dir)
# The resolvers may live in the Polaris workspace, not the target repo
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
resolve_by_branch=""
resolve_base=""

for search_dir in "$REPO_ROOT/scripts" "$WORKSPACE_SCRIPTS"; do
  if [[ -z "$resolve_by_branch" && -f "$search_dir/resolve-task-md-by-branch.sh" ]]; then
    resolve_by_branch="$search_dir/resolve-task-md-by-branch.sh"
  fi
  if [[ -z "$resolve_base" && -f "$search_dir/resolve-task-base.sh" ]]; then
    resolve_base="$search_dir/resolve-task-base.sh"
  fi
done

# If either resolver is missing → fail-open
if [[ -z "$resolve_by_branch" ]]; then
  echo "$PREFIX WARN: resolve-task-md-by-branch.sh not found — allowing (fail-open)" >&2
  exit 0
fi
if [[ -z "$resolve_base" ]]; then
  echo "$PREFIX WARN: resolve-task-base.sh not found — allowing (fail-open)" >&2
  exit 0
fi

# Resolve task.md for current branch
task_md_path=$(bash "$resolve_by_branch" --current 2>/dev/null || true)
resolve_branch_rc=$?

# Non-zero exit or empty → not managed, allow
if [[ "$resolve_branch_rc" -ne 0 || -z "$task_md_path" ]]; then
  exit 0
fi

# Extra safety: file must exist
if [[ ! -f "$task_md_path" ]]; then
  echo "$PREFIX WARN: resolver returned non-existent task.md: $task_md_path — allowing (fail-open)" >&2
  exit 0
fi

# Resolve expected base from task.md
expected_base=$(bash "$resolve_base" "$task_md_path" 2>/dev/null || true)
resolve_base_rc=$?

if [[ "$resolve_base_rc" -ne 0 || -z "$expected_base" ]]; then
  echo "$PREFIX WARN: resolve-task-base.sh failed (rc=$resolve_base_rc) for $task_md_path — allowing (fail-open)" >&2
  exit 0
fi

# Compare actual vs expected
if [[ "$ACTUAL_BASE" == "$expected_base" ]]; then
  echo "$PREFIX ✅ PR base matches task.md: ${ACTUAL_BASE}" >&2
  exit 0
fi

# Mismatch → block
current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<unknown>")

cat >&2 <<EOF

$PREFIX BLOCKED: PR --base does not match expected base from task.md.
  Current branch:  ${current_branch}
  Task.md:         ${task_md_path}
  Expected --base: ${expected_base}
  Actual --base:   ${ACTUAL_BASE}

Why: DP-028 enforces depends_on → PR base binding. Opening a PR against the
wrong base breaks the stacked PR chain.

Fix options:
  1. Use --base ${expected_base} (the value from task.md)
  2. If task.md is wrong, fix the Base branch field in task.md first
  3. Emergency bypass: POLARIS_SKIP_PR_BASE_GATE=1
EOF
exit 2
