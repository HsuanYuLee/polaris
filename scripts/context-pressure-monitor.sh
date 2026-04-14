#!/usr/bin/env bash
# context-pressure-monitor.sh — PostToolUse hook
# Counts tool calls per session. At threshold, injects warning to save state.
#
# State file: /tmp/polaris-session-calls.txt
# Contains: one line per tool call timestamp
#
# Thresholds:
#   20 calls — advisory: "consider wrapping up current phase"
#   25 calls — urgent: "save state, delegate remaining work"
#   35 calls — critical: "enter checkpoint mode NOW"
#
# Reset: file is session-scoped (/tmp), auto-cleared on reboot.
#        Or: rm /tmp/polaris-session-calls.txt
#
# Exit 0 = continue (stdout = injected message, if any)

set -euo pipefail

STATE_FILE="/tmp/polaris-session-calls.txt"

# Read hook input (PostToolUse provides tool_name, tool_input, tool_output)
input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Only count meaningful tool calls — skip internal/meta tools
case "$tool_name" in
  Bash|Edit|Write|Read|Grep|Glob|Agent|NotebookEdit)
    ;;
  *)
    # Don't count ToolSearch, TodoWrite, Skill, etc.
    exit 0
    ;;
esac

# Append timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" >> "$STATE_FILE"

# Count total calls
count=$(wc -l < "$STATE_FILE" | tr -d ' ')

# Inject warning at thresholds
# Only inject once per threshold (not every call after threshold)
case "$count" in
  20)
    echo "📊 Context pressure: ${count} tool calls. Consider wrapping up the current phase — write a milestone summary if you haven't yet."
    ;;
  25)
    echo "⚠️ Context pressure: ${count} tool calls. Save state NOW (checkpoint memory + todo review). Delegate remaining exploration to sub-agents."
    ;;
  35)
    echo "🔴 Context pressure: ${count} tool calls — CHECKPOINT MODE. Write a project memory with current progress and pending items before continuing. Suggest new session to user."
    ;;
esac

exit 0
