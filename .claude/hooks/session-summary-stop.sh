#!/usr/bin/env bash
# session-summary-stop.sh — Stop hook (backup path for session summary)
# Fires when Claude finishes responding. Covers short sessions that never hit
# PreCompact. Complements:
#   - .claude/hooks/session-summary-precompact.sh (main path, fires on compact)
#   - .claude/hooks/stop-todo-check.sh (also a Stop hook, checks todo dispositions)
#
# Solves: D4 session_summary capture — Stop backup path (DP-024).
#
# Hook type: Stop (exit 0 = allow stop; non-blocking — we only inject advice)
#
# Filter conditions (all must hold to nudge):
#   1. session_id present on stdin
#   2. substantial session (≥ 10 recent tool calls per context-pressure tracker)
#   3. no unpushed commits on current branch (session is "complete-looking")
#   4. no prior session_summary for this session_id in timeline
#
# Rationale:
#   - We do NOT replicate stop-todo-check.sh's block-once; that hook handles
#     todo discipline. This hook is an advisory about capturing narrative.
#   - Non-blocking exit 0 keeps Claude flow clean. The injected stdout is a
#     reminder the Strategist can act on or skip.
#   - Dedup via --session-id: if PreCompact already wrote for this session,
#     our append will replace it with the (presumably richer) end-of-session
#     narrative.

set -euo pipefail

REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INPUT=$(cat 2>/dev/null || true)

# Prevent loop: if stop_hook_active, the user is already being blocked by
# another Stop hook — don't pile on more injections.
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [ "$STOP_HOOK_ACTIVE" = "True" ] || [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', ''))" 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# --- Filter 1: per-session once-fired gate ---
FIRED_FILE="/tmp/polaris-summary-nudged-${SESSION_ID}"
[ -f "$FIRED_FILE" ] && exit 0

# --- Filter 2: substantial session (piggyback on context-pressure state) ---
STATE_FILE="/tmp/polaris-session-calls.txt"
[ ! -f "$STATE_FILE" ] && exit 0
RECENT_COUNT=$(find "$STATE_FILE" -mmin -120 -exec wc -l < {} \; 2>/dev/null | tr -d ' ')
if [ -z "$RECENT_COUNT" ] || [ "$RECENT_COUNT" -lt 10 ]; then
  exit 0
fi

# --- Filter 3: no unpushed commits (session looks "delivered") ---
# `git log @{u}..HEAD` lists commits ahead of upstream. Any output = unpushed.
UNPUSHED=""
if git -C "$REPO" rev-parse @{u} >/dev/null 2>&1; then
  UNPUSHED=$(git -C "$REPO" log '@{u}..HEAD' --oneline 2>/dev/null | head -1 || true)
fi
# If unpushed work exists, skip — Strategist likely still mid-delivery.
[ -n "$UNPUSHED" ] && exit 0

# --- Filter 4: no prior session_summary for this session_id ---
TIMELINE_SCRIPT="$REPO/scripts/polaris-timeline.sh"
if [ -x "$TIMELINE_SCRIPT" ]; then
  EXISTING=$(POLARIS_WORKSPACE_ROOT="$REPO" "$TIMELINE_SCRIPT" query --since 24h --event session_summary 2>/dev/null \
    | jq -c --arg sid "$SESSION_ID" 'select((.session_id // "") == $sid)' 2>/dev/null | head -1)
  if [ -n "$EXISTING" ]; then
    # PreCompact or earlier Stop-fire already captured this session — dedup takes care of it.
    # We could still re-fire to let Strategist refresh, but once-per-session is simpler.
    touch "$FIRED_FILE"
    exit 0
  fi
fi

# --- Collect metadata (same logic as PreCompact hook) ---
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null || echo "unknown")
TICKET=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)
TODAY_UTC=$(date -u +%Y-%m-%d)
COMMITS_JSON="[]"
if git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
  COMMITS_JSON=$(git -C "$REPO" log --since="$TODAY_UTC 00:00" --format='%h' 2>/dev/null \
    | jq -R . | jq -sc . 2>/dev/null || echo "[]")
fi
SKILLS_JSON="[]"
TICKETS_JSON="[]"
if [ -x "$TIMELINE_SCRIPT" ]; then
  SKILLS_JSON=$(POLARIS_WORKSPACE_ROOT="$REPO" "$TIMELINE_SCRIPT" query --since 4h --event skill_invoked 2>/dev/null \
    | jq -sc '[.[].skill] | unique' 2>/dev/null || echo "[]")
  TICKETS_JSON=$(POLARIS_WORKSPACE_ROOT="$REPO" "$TIMELINE_SCRIPT" query --since 4h 2>/dev/null \
    | jq -sc --arg t "$TICKET" '
        ([.[].ticket // empty] + (if $t != "" then [$t] else [] end))
        | unique
      ' 2>/dev/null || echo "[]")
fi
BRANCHES_JSON=$(printf '%s' "$BRANCH" | jq -R . | jq -sc '.')

touch "$FIRED_FILE"

cat <<EOF

[Stop/session-summary] Substantial session wrapping up with no unpushed
commits and no existing summary. Capture a one-line narrative for future
cross-session resume:

  POLARIS_WORKSPACE_ROOT="$REPO" \\
    bash "$REPO/scripts/polaris-timeline.sh" append --event session_summary \\
    --text "<one-line narrative>" \\
    --session-id "$SESSION_ID" \\
    --field 'branches=$BRANCHES_JSON' \\
    --field 'tickets=$TICKETS_JSON' \\
    --field 'skills=$SKILLS_JSON' \\
    --field 'commits=$COMMITS_JSON'

Metadata above is pre-computed. You only write the --text. Skip only if the
session's outcome is fully described by the commits list above.
EOF

exit 0
