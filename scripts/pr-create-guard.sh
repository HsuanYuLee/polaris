#!/usr/bin/env bash
# pr-create-guard.sh — PreToolUse hook
# Blocks direct `gh pr create`. Forces use of the engineering PR wrapper.
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)
# PR metadata language checks are delegated to gate-pr-language.sh, which wraps
# validate-language-policy.sh for title/body/body-file artifacts.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PR_LANGUAGE_GATE="$SCRIPT_DIR/gates/gate-pr-language.sh"
SPINE_DELIVERY_GATE="$SCRIPT_DIR/gates/gate-spine-delivery.sh"

# Description: true when the current commit is one a spine delivery record names.
# Args: none
#
# The wrapper this guard points at resolves a task.md from the branch name, which
# a spine source does not have and deliberately does not want — its identity lives
# in {source}/.spine/delivery.json, not in the ref. Without a lane here the spine
# cannot open the PR that spine-release.sh requires, so the flow would dead-end at
# its own delivery step. The authorisation is the same one four other gates already
# accept: a fence someone signed plus a delivery record pinned to this commit.
#
# The repository is the one the command is being run in, not the one this script
# lives in: a record here must not authorise opening a PR somewhere else.
is_spine_delivery() {
  [[ -f "$SPINE_DELIVERY_GATE" ]] || return 1
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo_root" ]] || return 1
  bash "$SPINE_DELIVERY_GATE" --repo "$repo_root" --is-spine-push >/dev/null 2>&1
}

# Block gh pr create (direct PR creation without quality gates)
# Only match when gh pr create is the actual command, not inside quotes/args
if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+create\b'; then
  if is_spine_delivery; then
    exit 0
  fi
  echo "BLOCKED: Direct gh pr create — use engineering / scripts/polaris-pr-create.sh" >&2
  echo "The engineering flow runs lint, test, coverage, pre-PR review and evidence gates before creating the PR." >&2
  echo "Command was: $command" >&2
  exit 2
fi

if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+(edit|comment|review)\b'; then
  if [[ -x "$PR_LANGUAGE_GATE" ]]; then
    "$PR_LANGUAGE_GATE" --command "$command"
  fi
fi

exit 0
