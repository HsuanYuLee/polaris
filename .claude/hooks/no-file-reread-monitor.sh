#!/usr/bin/env bash
# .claude/hooks/no-file-reread-monitor.sh — PostToolUse hook for Read
#
# DP-030 Phase 2B: downgrades the behavioral canary `no-file-reread`
# (rules/context-monitoring.md § 3) into a deterministic advisory hook.
#
# Hook type: PostToolUse
# Matcher:   Read
#
# Reads the Claude Code PostToolUse JSON from stdin, extracts
# `tool_input.file_path`, and delegates to scripts/check-no-file-reread.sh.
# Advisory only:
#   0 — always (warning emitted on stdout when threshold exceeded)

set -u

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Defend the matcher.
[[ "$tool_name" == "Read" ]] || exit 0

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-no-file-reread.sh"

if [[ ! -f "$checker" ]]; then
  exit 0
fi

bash "$checker" --file-path "$file_path"
exit 0
