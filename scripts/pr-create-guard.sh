#!/usr/bin/env bash
# pr-create-guard.sh — PreToolUse hook
# Blocks direct `gh pr create`. Forces use of git-pr-workflow skill.
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

# Block gh pr create (direct PR creation without quality gates)
# Only match when gh pr create is the actual command, not inside quotes/args
# POLARIS_PR_WORKFLOW=1 is set by git-pr-workflow skill after quality gates pass
if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+create\b'; then
  if [[ "${POLARIS_PR_WORKFLOW:-}" == "1" ]]; then
    if [[ -x "$PR_LANGUAGE_GATE" ]]; then
      "$PR_LANGUAGE_GATE" --command "$command"
    fi
    exit 0
  fi
  echo "BLOCKED: Direct gh pr create — use git-pr-workflow skill" >&2
  echo "The skill runs lint, test, coverage, pre-PR review, and changeset checks before creating the PR." >&2
  echo "Command was: $command" >&2
  exit 2
fi

if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+(edit|comment|review)\b'; then
  if [[ -x "$PR_LANGUAGE_GATE" ]]; then
    "$PR_LANGUAGE_GATE" --command "$command"
  fi
fi

exit 0
