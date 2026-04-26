#!/usr/bin/env bash
# .claude/hooks/version-bump-reminder.sh — PostToolUse hook for git commit
#
# DP-030 Phase 2C: graduates the `version-bump-reminder` canary to
# deterministic enforcement. The behavioral canary (previously in
# mechanism-registry.md § Framework Iteration) is superseded by:
#   - this PostToolUse hook on `git commit` (L1, advisory)
#   - L2 embeds in engineering / git-pr-workflow SKILL.md (post-PR tail)
#
# Hook type: PostToolUse
# Matcher:   Bash (filtered upstream in settings.json via `if: Bash(git*commit*)`)
#
# The hook reads the Claude Code PostToolUse JSON from stdin, extracts the
# executed command, verifies it is a `git commit` invocation, and delegates
# to scripts/check-version-bump-reminder.sh in post-commit mode. The script
# is advisory (exit 0 always); stdout carries the reminder when applicable.
#
# Design: specs/design-plans/DP-030-llm-to-script-migration/plan.md
#         § Phase 2C (2026-04-24)

set -u

# Read hook input (PostToolUse: JSON on stdin).
input=$(cat 2>/dev/null || true)

# Extract the executed command.
COMMAND=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Only process git commit commands (double-check even though settings.json
# already filters via `if: Bash(git*commit*)`).
if ! printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit([[:space:]]|$)'; then
  exit 0
fi

# Resolve repo path: honor `git -C <path> commit` if present.
REPO_PATH=$(printf '%s' "$COMMAND" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [[ -z "$REPO_PATH" ]]; then
  REPO_PATH="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

# Delegate to the runtime-agnostic validator.
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-version-bump-reminder.sh"

if [[ ! -f "$checker" ]]; then
  # Fail-open silently — advisory hook, no point warning about its own absence.
  exit 0
fi

bash "$checker" --mode post-commit --repo "$REPO_PATH"
exit 0
