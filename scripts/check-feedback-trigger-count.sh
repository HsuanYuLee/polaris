#!/usr/bin/env bash
# scripts/check-feedback-trigger-count.sh
#
# Purpose: Stop-time advisory — scan the feedback-read log populated by the
#          PostToolUse Read hook and report feedback memories whose
#          `last_triggered` frontmatter was NOT bumped in this session. This
#          supports the behavioral canary `feedback-trigger-count-update`
#          (rules/feedback-and-memory.md § Trigger Count Update Rules).
#
# Canary: feedback-trigger-count-update (DP-030 Phase 2C — partial graduation
#         to deterministic signal capture; behavioral write still required)
#
# Mode: Advisory only. Exit 0 on every path. Emits reminder on stdout when
#       stale feedback reads are detected.
#
# Exit codes:
#   0 — always (advisory emission only)
#
# State:
#   /tmp/polaris-session-feedback-reads.txt — one line per feedback memory
#     absolute path read this session (dedup'd, appended by
#     .claude/hooks/feedback-read-logger.sh).
#
# Environment variables:
#   POLARIS_FEEDBACK_READS_STATE — override state file path (default above)
#   POLARIS_FEEDBACK_TODAY       — override today's date (YYYY-MM-DD, used
#                                   in tests; defaults to `date +%F`)
#
# Usage:
#   check-feedback-trigger-count.sh          # scan and emit advisory
#   check-feedback-trigger-count.sh --clear  # scan then clear the state file
#
# Invoked by:
#   - .claude/hooks/feedback-trigger-advisory.sh (Stop hook)

set -u

STATE_FILE="${POLARIS_FEEDBACK_READS_STATE:-/tmp/polaris-session-feedback-reads.txt}"
TODAY="${POLARIS_FEEDBACK_TODAY:-$(date +%F)}"
CLEAR_AFTER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clear)
      CLEAR_AFTER=1
      shift
      ;;
    -h|--help)
      sed -n '2,30p' "$0" >&2
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Dedup the state file on the fly — later appenders may have added duplicates.
# Read unique paths.
paths=$(awk 'NF && !seen[$0]++' "$STATE_FILE" 2>/dev/null || true)

if [[ -z "$paths" ]]; then
  exit 0
fi

# Accumulate stale entries (last_triggered ≠ today OR missing).
stale=""
total=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  total=$((total + 1))
  if [[ ! -f "$p" ]]; then
    # File moved/deleted mid-session — skip silently.
    continue
  fi
  # Grab `last_triggered:` value from frontmatter (first 50 lines).
  last=$(sed -n '1,50p' "$p" 2>/dev/null \
    | grep -E '^last_triggered:' \
    | head -1 \
    | sed -E 's/^last_triggered:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')
  if [[ -z "$last" || "$last" != "$TODAY" ]]; then
    stale+=$'\n  - '"$p"
    [[ -n "$last" ]] && stale+=" (last_triggered: $last)" \
      || stale+=" (last_triggered missing)"
  fi
done <<< "$paths"

if [[ -n "$stale" ]]; then
  # Use quoted heredoc to prevent backtick command substitution inside the
  # message body; emit the two interpolated values via printf first.
  printf '\n[feedback-trigger-count-update] %s feedback memory file(s) were read this session.\n' "$total"
  printf 'The following file(s) were NOT bumped (last_triggered ≠ %s):%s\n' "$TODAY" "$stale"
  cat <<'EOF'

If any of these feedback memories actually guided a decision this session, the
rule (rules/feedback-and-memory.md § Trigger Count Update Rules) requires:

  1. Increment `trigger_count` (+1)
  2. Set `last_triggered` to today's date (YYYY-MM-DD)

If they were merely scanned (hygiene / dedup check, not a reference that drove
behavior), no bump is needed — ignore this advisory.
EOF
fi

if (( CLEAR_AFTER == 1 )); then
  : > "$STATE_FILE"
fi

exit 0
