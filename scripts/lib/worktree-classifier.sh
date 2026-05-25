#!/usr/bin/env bash
# scripts/lib/worktree-classifier.sh — deterministic worktree classifier.
#
# DP-230-T9 (D23). Polaris framework runs two distinct kinds of worktrees:
#
#   1. engineering implementation worktrees, created by
#      scripts/engineering-branch-setup.sh under either:
#        - <main-checkout>/.worktrees/polaris-framework-engineering-<TASK_ID>
#        - <main-checkout>/.worktrees/polaris-framework-<TASK_ID>
#      These hold the task branch and are subject to scope gate / clean-state
#      enforcement during release closeout.
#
#   2. sub-agent worktrees, created by ad-hoc sub-agent dispatch under:
#        - <main-checkout>/.claude/worktrees/agent-<hash>
#        - <main-checkout>/.worktrees/polaris-framework-DP-*-T*-batch-<N>
#      These are short-lived scratch space for sub-agents; framework-release
#      closeout must NOT treat them as implementation worktrees, NOT enforce
#      clean state on them, and NOT remove them (their lifecycle is owned by
#      the dispatcher, not by closeout).
#
# This helper is the ONE place that knows how to tell them apart. Every script
# that consumes a `git worktree list --porcelain` entry sources this file and
# calls `classify_worktree <abs-path>`.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/worktree-classifier.sh"
#   case "$(classify_worktree "$path")" in
#     engineering) ... ;;
#     sub-agent)   ... ;;
#     unknown)     ... ;;
#   esac
#
# Exit codes:
#   classify_worktree always echoes a single token and returns 0. Empty input
#   echoes `unknown`.
#
# This file is sourced, not executed — no `set -e`, no top-level side effects.

# classify_worktree <worktree_path>
#   Echo one of:
#     engineering — engineering implementation worktree (closeout-managed)
#     sub-agent   — sub-agent scratch worktree (closeout must skip)
#     unknown     — neither (caller decides; defaults to fail-safe skip)
classify_worktree() {
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    echo "unknown"
    return 0
  fi

  # Sub-agent namespace #1: .claude/worktrees/agent-<hash>
  # The dispatcher uses a hex-ish suffix; any non-empty suffix counts.
  if [[ "$path" == *"/.claude/worktrees/agent-"* ]]; then
    echo "sub-agent"
    return 0
  fi

  # Sub-agent namespace #2: .worktrees/polaris-framework-<...>-batch-<N>
  # Used by engineering batch mode Phase 2 sub-agents (DP-191, DP-228 …).
  # The trailing -batch-<digits> suffix is the deterministic marker; any
  # numeric suffix is treated as sub-agent regardless of width
  # (batch-2 / batch-10 / batch-99).
  if [[ "$path" == *"/.worktrees/"*"-batch-"* ]]; then
    # Pull the segment after the last `-batch-` and ensure it is all digits.
    local suffix="${path##*-batch-}"
    if [[ "$suffix" =~ ^[0-9]+$ ]]; then
      echo "sub-agent"
      return 0
    fi
  fi

  # Engineering namespace: .worktrees/polaris-framework-<...> (no -batch- suffix)
  # and .worktrees/polaris-framework-engineering-<...>. Both are created by
  # engineering-branch-setup.sh and treated as implementation worktrees.
  if [[ "$path" == *"/.worktrees/polaris-framework-"* ]]; then
    echo "engineering"
    return 0
  fi

  # Anything else under a generic `.worktrees/` directory is treated as
  # engineering (legacy DP-* paths) but the caller should still apply the
  # dirty-state guard.
  if [[ "$path" == *"/.worktrees/"* ]]; then
    echo "engineering"
    return 0
  fi

  echo "unknown"
  return 0
}
