#!/usr/bin/env bash
# .claude/hooks/no-independent-cmd-chaining.sh — PreToolUse hook for Bash
#
# DP-030 Phase 2B: downgrades the behavioral canary
# `no-independent-cmd-chaining` (rules/bash-command-splitting.md § Do Not
# Chain Independent Commands) from mechanism-registry into a deterministic
# hook.
#
# Hook type: PreToolUse
# Matcher:   Bash
#
# Reads the Claude Code PreToolUse JSON from stdin, extracts
# `tool_input.command`, and delegates to
# scripts/check-no-independent-cmd-chaining.sh. The script's exit code
# becomes the hook's exit code:
#   0 — allow tool call
#   2 — block tool call

set -u

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Defend the matcher (settings.json already filters Bash, but double-check).
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-no-independent-cmd-chaining.sh"

if [[ ! -f "$checker" ]]; then
  echo "[no-independent-cmd-chaining] WARN: validator missing at $checker — allowing (fail-open)" >&2
  exit 0
fi

bash "$checker" --command "$command"
exit $?
