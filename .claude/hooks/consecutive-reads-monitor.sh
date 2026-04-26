#!/usr/bin/env bash
# .claude/hooks/consecutive-reads-monitor.sh — PostToolUse hook (broad matcher)
#
# DP-030 Phase 2B: downgrades the behavioral canary `max-five-consecutive-reads`
# (rules/context-monitoring.md § 1) into a deterministic advisory hook.
#
# Hook type: PostToolUse
# Matcher:   Bash|Edit|Write|Read|Grep|Glob|Agent|NotebookEdit
#            (matches all state-relevant tools; Read/Grep increment the
#            counter, others reset it)
#
# Reads the Claude Code PostToolUse JSON from stdin, extracts `tool_name`,
# and delegates to scripts/check-consecutive-reads.sh. Advisory only:
#   0 — always (warning emitted on stdout when threshold exceeded)

set -u

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-consecutive-reads.sh"

if [[ ! -f "$checker" ]]; then
  # Fail-open silently — advisory hook, no point warning about its own absence.
  exit 0
fi

bash "$checker" --tool-name "$tool_name"
exit 0
