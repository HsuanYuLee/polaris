#!/usr/bin/env bash
# session-summary-precompact.sh — PreCompact hook
# Before context compaction wipes working memory, prompt the Strategist to
# write a one-line session summary into polaris-timeline. Pairs with
# post-compact-context-restore.sh (compress-before-write / restore-after-compact).
#
# Solves: D4 session summary capture — PreCompact path (DP-024).
#
# Hook type: PreCompact (fires before context compaction)
# Stdout: injected into Claude's context
# Exit 0 = continue (never block compaction)
#
# Design:
#   - Hook computes metadata (branch, ticket, recent commits, recent skill_invoked
#     events) from git + polaris-timeline history.
#   - Hook DOES NOT write to timeline itself — Strategist writes the entry, so
#     the `--text` field reflects the actual narrative. Hook supplies the
#     pre-baked `--field` args; Strategist only chooses the sentence.
#   - v1 leaves multi-compaction dedup to follow-up work (plan.md BS D4.6).

set -euo pipefail

REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Hook stdin (Claude Code supplies JSON: session_id, hook_event_name, ...) ---
# Read non-blocking: PreCompact passes JSON on stdin. Empty stdin is tolerated
# (manual/legacy invocation).
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat 2>/dev/null || true)
fi
SESSION_ID=""
if [ -n "$HOOK_INPUT" ]; then
  SESSION_ID=$(printf '%s' "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id', ''))" 2>/dev/null || true)
fi

# --- Git state ---
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null || echo "unknown")
# Active ticket: extract from branch name patterns like task/KB2CW-1234, feat/GT-500, wip/GT-521
TICKET=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)

# Today's commit SHAs (short) on current branch
TODAY_UTC=$(date -u +%Y-%m-%d)
COMMITS_JSON="[]"
if git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
  COMMITS_JSON=$(git -C "$REPO" log --since="$TODAY_UTC 00:00" --format='%h' 2>/dev/null \
    | jq -R . | jq -sc . 2>/dev/null || echo "[]")
fi

# --- Recent skill_invoked events (last 4h) via polaris-timeline ---
SKILLS_JSON="[]"
TIMELINE_SCRIPT="$REPO/scripts/polaris-timeline.sh"
if [ -x "$TIMELINE_SCRIPT" ]; then
  SKILLS_JSON=$(POLARIS_WORKSPACE_ROOT="$REPO" "$TIMELINE_SCRIPT" query --since 4h --event skill_invoked 2>/dev/null \
    | jq -sc '[.[].skill] | unique' 2>/dev/null || echo "[]")
fi

# Tickets seen in last 4h of timeline + current branch ticket
TICKETS_JSON="[]"
if [ -x "$TIMELINE_SCRIPT" ]; then
  TICKETS_JSON=$(POLARIS_WORKSPACE_ROOT="$REPO" "$TIMELINE_SCRIPT" query --since 4h 2>/dev/null \
    | jq -sc --arg t "$TICKET" '
        ([.[].ticket // empty] + (if $t != "" then [$t] else [] end))
        | unique
      ' 2>/dev/null || echo "[]")
fi

BRANCHES_JSON=$(printf '%s' "$BRANCH" | jq -R . | jq -sc '.')

# --- Compose injection ---
SESSION_ID_LINE=""
if [ -n "$SESSION_ID" ]; then
  SESSION_ID_LINE="    --session-id \"$SESSION_ID\" \\\\"$'\n'
fi

cat <<EOF

[PreCompact] Context is about to be compacted. Before compression wipes your
working memory, write a ONE-LINE session summary to polaris-timeline so the
next session can reconstruct what happened.

Run (fill in --text with a concrete one-liner):

  POLARIS_WORKSPACE_ROOT="$REPO" \\
    bash "$REPO/scripts/polaris-timeline.sh" append --event session_summary \\
    --text "<one-line narrative: what did this session accomplish / land / decide>" \\
${SESSION_ID_LINE}    --field 'branches=$BRANCHES_JSON' \\
    --field 'tickets=$TICKETS_JSON' \\
    --field 'skills=$SKILLS_JSON' \\
    --field 'commits=$COMMITS_JSON'

Metadata above is pre-computed from git + timeline. You only write the --text.
The --session-id flag enables dedup — if Stop hook also fires later, the later
summary replaces this one instead of appending a duplicate.
Skip only if the session is trivially short (≤ 3 tool calls, no decisions).
EOF

exit 0
