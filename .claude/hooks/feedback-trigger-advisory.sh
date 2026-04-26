#!/usr/bin/env bash
# .claude/hooks/feedback-trigger-advisory.sh — Stop hook
#
# DP-030 Phase 2C (B1, partial graduation): advisory Stop hook for the
# `feedback-trigger-count-update` canary. Runs when Claude finishes a turn;
# if the session read feedback memory files whose `last_triggered`
# frontmatter is not today's date, emits a reminder on stdout.
#
# Hook type: Stop
# Mode:      Advisory only — NEVER outputs a `decision: block` envelope. We
#            coexist with stop-todo-check.sh (blocking) without interfering.
#
# The hook honors `stop_hook_active` to avoid recursion / double-emission.
#
# Exit codes:
#   0 — always (advisory only)

set -u

INPUT=$(cat 2>/dev/null || true)

# Prevent recursive firing.
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [[ "$STOP_HOOK_ACTIVE" == "True" || "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-feedback-trigger-count.sh"

if [[ ! -f "$checker" ]]; then
  exit 0
fi

# Do NOT pass --clear — we want the state to persist in case the user resumes
# work and the advisory is worth re-surfacing. The state file is session-
# scoped via /tmp (cleared on reboot).
bash "$checker"
exit 0
