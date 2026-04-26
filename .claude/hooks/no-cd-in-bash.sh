#!/usr/bin/env bash
# .claude/hooks/no-cd-in-bash.sh — PreToolUse hook for Bash
#
# DP-030 Phase 1 POC #1: downgrades the behavioral canary `no-cd-in-bash`
# from mechanism-registry.md § Bash Execution into a deterministic hook.
#
# Hook type: PreToolUse
# Matcher:   Bash
#
# The hook reads the Claude Code PreToolUse JSON from stdin, extracts
# `tool_input.command`, and delegates to scripts/check-no-cd-in-bash.sh.
# The script's exit code becomes the hook's exit code:
#   0 — allow tool call
#   2 — block tool call
#
# Design: specs/design-plans/DP-030-llm-to-script-migration/plan.md
#         § Phase 1 POC #1

set -u

# Read hook input (PreToolUse: JSON on stdin).
input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Defend the matcher (settings.json already filters Bash, but double-check).
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Delegate to the runtime-agnostic validator.
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-no-cd-in-bash.sh"

if [[ ! -f "$checker" ]]; then
  echo "[no-cd-in-bash] WARN: validator missing at $checker — allowing (fail-open)" >&2
  exit 0
fi

bash "$checker" --command "$command"
exit $?
