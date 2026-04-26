#!/usr/bin/env bash
# .claude/hooks/feedback-reflection-stop.sh — Stop hook
#
# DP-030 Phase 2C (B2, partial graduation): advisory Stop hook for the
# `post-task-feedback-reflection` canary. When Claude finishes a turn, checks
# for self-correct signals without a matching new feedback memory and emits
# a nudge on stdout.
#
# Hook type: Stop
# Mode:      Advisory only — never outputs `decision: block`.
#
# Exit codes:
#   0 — always (advisory only)

set -u

INPUT=$(cat 2>/dev/null || true)

STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [[ "$STOP_HOOK_ACTIVE" == "True" || "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-feedback-signals.sh"

if [[ ! -f "$checker" ]]; then
  exit 0
fi

bash "$checker" --skill stop
exit 0
