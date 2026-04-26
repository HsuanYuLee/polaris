#!/usr/bin/env bash
# stop-todo-check.sh — Stop hook
# When Claude finishes responding, check if this is a substantial session.
# If yes, block stopping once to nudge Strategist to review todo dispositions.
#
# Solves: premature-completion / checklist-before-done mechanisms
# Previously behavioral-only — now deterministic.
#
# Hook type: Stop (fires when Claude finishes responding)
# Exit 0 = allow stop, Exit 2 = block stop
# JSON {"decision":"block","reason":"..."} on stdout = block with reason
#
# IMPORTANT: must check stop_hook_active to prevent infinite loops.

set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop: if this hook already ran this turn, allow stop
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [ "$STOP_HOOK_ACTIVE" = "True" ] || [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Extract session_id for per-session tracking
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', ''))" 2>/dev/null || true)
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Per-session state: track whether we've already nudged this session
NUDGE_FILE="/tmp/polaris-stop-nudged-${SESSION_ID}"
if [ -f "$NUDGE_FILE" ]; then
  # Already nudged once this session — don't repeat
  exit 0
fi

# Use per-session call count from context-pressure-monitor
# The monitor writes to a global file, but we can use session start time
# as a proxy. Simpler: count calls since session start by checking
# the session-specific state file.
STATE_FILE="/tmp/polaris-session-calls.txt"
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Count only recent calls (last 2 hours) as a proxy for current session
RECENT_COUNT=$(find "$STATE_FILE" -mmin -120 -exec wc -l < {} \; 2>/dev/null | tr -d ' ')
if [ -z "$RECENT_COUNT" ] || [ "$RECENT_COUNT" -lt 20 ]; then
  # Lightweight session — no need to gate
  exit 0
fi

# Mark as nudged so we don't block again
touch "$NUDGE_FILE"

# Nudge once
cat <<EOF
{"decision":"block","reason":"[stop-todo-check] Substantial session detected. Before stopping, review: (1) Are all todo items completed or explicitly carried forward? (2) If there's a starting checklist, does every item have a disposition? If all clear, proceed to stop."}
EOF

exit 0
