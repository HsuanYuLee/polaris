#!/usr/bin/env bash
# post-compact-context-restore.sh — PostCompact hook
# After context compression, re-inject critical session state so the
# Strategist doesn't lose company context, active ticket, or branch info.
#
# Solves: post-compression-company-context mechanism (mechanism-registry.md)
# Previously behavioral-only — now deterministic.
#
# Hook type: PostCompact (fires after context compaction)
# Stdout: injected into Claude's context
# Exit 0 = continue

set -euo pipefail

# --- Git state ---
REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null || echo "unknown")
STASH_COUNT=$(git -C "$REPO" stash list 2>/dev/null | wc -l | tr -d ' ')
MODIFIED=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# --- Active ticket (extract from branch name) ---
# Patterns: task/TASK-1234-desc, feat/EPIC-500-desc, wip/EPIC-521-debug
TICKET=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)

# --- Todo file (check for active todos) ---
TODO_HINT=""
if [ -f "/tmp/polaris-todos.json" ]; then
  PENDING=$(python3 -c "
import json, sys
try:
    todos = json.load(open('/tmp/polaris-todos.json'))
    pending = [t for t in todos if t.get('status') != 'completed']
    if pending:
        print(f'{len(pending)} pending todo(s)')
except: pass
" 2>/dev/null || true)
  if [ -n "$PENDING" ]; then
    TODO_HINT="Todo: $PENDING"
  fi
fi

# --- Session timeline (last event) ---
LAST_EVENT=""
if command -v polaris-timeline.sh &>/dev/null; then
  LAST_EVENT=$(polaris-timeline.sh query --last 1 2>/dev/null | head -1 || true)
fi

# --- Compose injection ---
cat <<EOF

[PostCompact] Context restored after compression:
  Branch: $BRANCH
  ${TICKET:+Ticket: $TICKET}
  Modified files: $MODIFIED | Stashes: $STASH_COUNT
  ${TODO_HINT:+$TODO_HINT}
  ${LAST_EVENT:+Last event: $LAST_EVENT}

Action required: confirm active company context before proceeding. If unclear, ask the user.
EOF

exit 0
