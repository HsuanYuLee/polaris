#!/usr/bin/env bash
set -euo pipefail

# gate-base-check.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from .claude/hooks/pr-base-gate.sh for cross-LLM portability.
# Can be called from: git pre-push hooks, polaris-pr-create.sh, or directly.
#
# DP-334 D3 / AC2 / AC-NEG1: framework DP delivery routes through a per-DP
# feat/DP-NNN aggregation branch (resolve-task-base.sh returns feat/DP-NNN as the
# expected base). A DP task PR must target its feat/DP-NNN branch; a DP task PR
# that directly targets main fails closed (the v3.76.18 raw-commit escape this DP
# closes). The legacy --aggregate-release bundle escape below is RETAINED as a
# bootstrap fallback only — Migration Boundaries removal criteria: removed in
# DP-334 once it self-releases under the feat model (AC7 PASS); see
# docs-manager/.../DP-334-framework-release-feature-branch-aggregation-release-model/index.md
# § Migration Boundaries.
#
# Usage:
#   bash scripts/gates/gate-base-check.sh [--repo <path>] [--base <branch>] [--aggregate-release]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_PR_BASE_GATE=1

PREFIX="[polaris gate-base-check]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
ACTUAL_BASE=""
AGGREGATE_RELEASE=0

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --base) ACTUAL_BASE="$2"; shift 2 ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-base-check.sh [--repo <path>] [--base <branch>] [--aggregate-release]"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --base <branch>   The intended PR base branch to validate"
      echo "  --aggregate-release  Allow an explicit framework aggregate release PR to target main"
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
resolve_chain=""

for search_dir in "$REPO_ROOT/scripts" "$WORKSPACE_SCRIPTS"; do
  if [[ -z "$resolve_by_branch" && -f "$search_dir/resolve-task-md-by-branch.sh" ]]; then
    resolve_by_branch="$search_dir/resolve-task-md-by-branch.sh"
  fi
  if [[ -z "$resolve_base" && -f "$search_dir/resolve-task-base.sh" ]]; then
    resolve_base="$search_dir/resolve-task-base.sh"
  fi
  if [[ -z "$resolve_chain" && -f "$search_dir/resolve-branch-chain.sh" ]]; then
    resolve_chain="$search_dir/resolve-branch-chain.sh"
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

# DP-334 D3 / AC2 / AC-NEG1: framework DP feature-branch aggregation lifecycle.
# When the task.md resolves to a feat/DP-NNN aggregation base, the DP task PR
# MUST target that feat branch; a DP task PR that directly targets main is a
# fail-closed violation — even under --aggregate-release. The --aggregate-release
# bundle escape (below) is reserved for the legacy bundle release path whose
# task.md base is itself a non-feat upstream; it must never launder a DP task
# whose expected base is feat/DP-NNN into a main-targeting PR (that is the
# v3.76.18 raw-commit escape this DP closes).
if [[ "$expected_base" =~ ^feat/DP-[0-9]+$ && "$ACTUAL_BASE" == "main" ]]; then
  current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<unknown>")
  cat >&2 <<EOF

$PREFIX BLOCKED: DP task PR must target its feat/DP-NNN aggregation branch, not main.
  Current branch:  ${current_branch}
  Task.md:         ${task_md_path}
  Expected --base: ${expected_base}
  Actual --base:   ${ACTUAL_BASE}

Why: DP-334 routes framework DP delivery through a per-DP feat/DP-NNN aggregation
branch. Task PRs merge into feat/DP-NNN; only a single feat/DP-NNN -> main PR may
target main. Targeting main from a task branch is the raw-commit escape this gate
closes (AC2 / AC-NEG1).

Fix:
  Use --base ${expected_base} (the feat/DP-NNN value from task.md).
EOF
  exit 2
fi

# DP-334 Migration Boundaries: legacy aggregate-release bundle escape. RETAINED as
# bootstrap fallback only; removed in DP-334 once it self-releases under the
# feat/DP-NNN model (AC7 PASS). The guard above already fail-closes a feat/DP-NNN
# DP task that targets main, so this escape can no longer launder DP task commits.
if [[ "$AGGREGATE_RELEASE" == "1" ]]; then
  current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<unknown>")
  if [[ "$ACTUAL_BASE" != "main" ]]; then
    cat >&2 <<EOF

$PREFIX BLOCKED: aggregate release PR base must be main.
  Current branch:  ${current_branch}
  Task.md:         ${task_md_path}
  Expected --base: ${expected_base}
  Actual --base:   ${ACTUAL_BASE}
EOF
    exit 2
  fi

  if [[ "$expected_base" == "main" ]]; then
    echo "$PREFIX WARN: --aggregate-release was unnecessary because task.md already resolves to main" >&2
    exit 0
  fi

  if [[ -z "$resolve_chain" ]]; then
    echo "$PREFIX BLOCKED: resolve-branch-chain.sh is required for aggregate release validation" >&2
    exit 2
  fi

  branch_chain=$(bash "$resolve_chain" "$task_md_path" 2>/dev/null || true)
  if [[ -z "$branch_chain" ]] ||
     ! printf '%s\n' "$branch_chain" | grep -qxF "$current_branch" ||
     ! printf '%s\n' "$branch_chain" | grep -qxF "$expected_base"; then
    cat >&2 <<EOF

$PREFIX BLOCKED: aggregate release branch is not backed by task.md Branch chain.
  Current branch:  ${current_branch}
  Task.md:         ${task_md_path}
  Expected --base: ${expected_base}
  Actual --base:   ${ACTUAL_BASE}
EOF
    exit 2
  fi

  echo "$PREFIX ✅ aggregate release PR base accepted: main (task upstream: ${expected_base})" >&2
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
