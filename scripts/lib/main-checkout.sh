#!/usr/bin/env bash
# scripts/lib/main-checkout.sh — single source of truth for worktree → main checkout resolution.
#
# DP-043 follow-up. Several framework artifacts are gitignored and live only
# in the main checkout (specs/, .claude/skills/, .claude/scripts/ci-local.sh).
# When a script runs inside a `git worktree add` copy, it must resolve the
# main checkout to read/write these artifacts.
#
# This helper is the ONE place that knows how. Every script (gate, hook,
# generator, resolver, runner) sources this file and calls
# `resolve_main_checkout`.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/main-checkout.sh"
#   main_root="$(resolve_main_checkout)"            # uses $PWD
#   main_root="$(resolve_main_checkout "$some_dir")" # uses arg
#
# This file is sourced, not executed — no `set -e`, no top-level side effects.

# resolve_main_checkout [start_dir]
#   Echo absolute path to the main checkout (the directory containing the
#   real `.git` directory). Works from inside the main checkout OR a linked
#   worktree.
#   Exit codes: 0 on success, 1 if not in a git repo or resolution failed.
resolve_main_checkout() {
  local start="${1:-$(pwd)}"
  local gc
  gc="$(git -C "$start" rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$gc" ]] || return 1
  # git-common-dir may return a relative path (resolved against $start)
  if [[ "$gc" != /* ]]; then
    gc="$(cd "$start" && cd "$gc" 2>/dev/null && pwd)" || return 1
  else
    gc="$(cd "$gc" 2>/dev/null && pwd)" || return 1
  fi
  # Main checkout is the parent of the real .git directory
  dirname "$gc"
}
