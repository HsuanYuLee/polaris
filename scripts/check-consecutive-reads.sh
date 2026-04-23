#!/usr/bin/env bash
# scripts/check-consecutive-reads.sh
#
# Purpose: Track consecutive Read/Grep tool calls and warn when the count
#          exceeds 5. Rule (rules/context-monitoring.md § 1 Delegate Heavy
#          Exploration) says never issue > 5 consecutive Read/Grep in main
#          session without producing a conclusion — delegate to Explorer
#          instead.
#
# Canary: max-five-consecutive-reads (L1-only — hook-observable, no skill
#         flow binding)
#
# Mode: Advisory only. Exit 0 always; warning emitted on stdout (PostToolUse
#       convention — warnings surface back to the LLM as a system-reminder).
#
# Exit codes:
#   0 — always (stdout carries the advisory when threshold hit)
#
# State:
#   /tmp/polaris-consecutive-reads.txt — single integer, the running count.
#   Resets to 0 when any non-Read/Grep counted tool fires. Cleared on reboot.
#
# Usage:
#   check-consecutive-reads.sh --tool-name "<ToolName>"
#
# Invoked by:
#   - .claude/hooks/consecutive-reads-monitor.sh (PostToolUse, broad matcher)

set -u

STATE_FILE="${POLARIS_CONSECUTIVE_READS_STATE:-/tmp/polaris-consecutive-reads.txt}"
THRESHOLD=5  # warn when count STRICTLY exceeds this (i.e. at the 6th)

tool_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool-name)
      tool_name="${2:-}"
      shift 2
      ;;
    --tool-name=*)
      tool_name="${1#--tool-name=}"
      shift
      ;;
    -h|--help)
      sed -n '2,28p' "$0" >&2
      exit 0
      ;;
    *)
      if [[ -z "$tool_name" ]]; then
        tool_name="$1"
      fi
      shift
      ;;
  esac
done

# Read existing count (default 0).
if [[ -f "$STATE_FILE" ]]; then
  count=$(head -n 1 "$STATE_FILE" | tr -cd '0-9')
  [[ -z "$count" ]] && count=0
else
  count=0
fi

# Tool classification:
#   - Read / Grep → increment consecutive counter
#   - Bash / Edit / Write / Agent / NotebookEdit / Glob → reset to 0
#     (these count as "intervening conclusion-producing tool calls")
#   - Other (ToolSearch, TodoWrite, Skill, MCP tools) → ignore, state unchanged
case "$tool_name" in
  Read|Grep)
    count=$((count + 1))
    printf '%s\n' "$count" > "$STATE_FILE"
    if (( count > THRESHOLD )); then
      cat <<EOF
📚 [max-five-consecutive-reads] ${count} consecutive Read/Grep calls in the main session (threshold ${THRESHOLD}).

Per rules/context-monitoring.md § 1, long exploration should be delegated:
  • Dispatch an Explorer sub-agent (subagent_type=Explore) for remaining file/pattern lookups
  • Or write a milestone summary now with what you've learned, then decide next step

Each additional Read/Grep risks context bloat; the counter resets on the next Bash/Edit/Write/Agent/Glob call.
EOF
    fi
    ;;
  Bash|Edit|Write|Agent|NotebookEdit|Glob)
    # Intervening conclusion-producing tool — reset.
    printf '0\n' > "$STATE_FILE"
    ;;
  *)
    # Uncounted tool — leave state as-is.
    :
    ;;
esac

exit 0
