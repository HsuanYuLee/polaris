#!/usr/bin/env bash
# scripts/lib/ci-local-path.sh — single source of truth for ci-local.sh path.
#
# DP-043 — relocates the framework-generated `ci-local.sh` from `<repo>/scripts/`
# (a repo source tree path that risked accidental commit) to `<repo>/.claude/scripts/`
# (gitignored via `.git/info/exclude`).
#
# Every reader of this path — generator, gate, hook, references — sources this
# file and resolves through `ci_local_path_for_repo` so the path lives in one
# place. Changing the constant here automatically updates every downstream
# consumer.
#
# Why a relative constant + helper, not an env var or workspace-config field:
#   - Hardcoded by design (DP-043 D2): "find ci-local.sh" must not depend on
#     workspace config load order, env var presence, or per-repo overrides.
#   - The path is a framework convention, not a user knob.
#
# Usage (from any framework script):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/ci-local-path.sh"
#   abs_path="$(ci_local_path_for_repo "$REPO_ROOT")"
#
# Usage from a script under scripts/gates/, scripts/, etc:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/ci-local-path.sh"
#   # …adjust ../lib relative to the script's depth.
#
# This file is sourced, not executed — it intentionally has no `set -e` and
# no top-level side effects beyond defining variables and functions.

# Repo-relative path to the generated ci-local mirror script. Single source of
# truth — every other reference must derive from this constant.
CI_LOCAL_RELATIVE_PATH=".claude/scripts/ci-local.sh"

# ci_local_path_for_repo <repo_root>
#   Echo the absolute path to ci-local.sh inside the given repo.
#   No filesystem check — pure path composition.
ci_local_path_for_repo() {
  local repo_root="$1"
  if [ -z "$repo_root" ]; then
    echo "ci_local_path_for_repo: missing repo_root argument" >&2
    return 1
  fi
  printf '%s/%s\n' "$repo_root" "$CI_LOCAL_RELATIVE_PATH"
}
