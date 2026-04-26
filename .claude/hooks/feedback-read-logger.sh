#!/usr/bin/env bash
# .claude/hooks/feedback-read-logger.sh — PostToolUse hook for Read
#
# DP-030 Phase 2C (B1, partial graduation): signal-capture hook for the
# `feedback-trigger-count-update` canary. Observes Read tool calls; when the
# file path matches a feedback memory (flat or topic-folder), appends the
# absolute path to a per-session state file. The Stop hook
# (feedback-trigger-advisory.sh) later reads this state and checks whether
# the feedback files' `last_triggered` frontmatter was bumped to today.
#
# Hook type: PostToolUse
# Matcher:   Read
# Mode:      Advisory only (exit 0 always; never blocks)
#
# Patterns matched (absolute or relative path with these segments):
#   - `memory/feedback_*.md`
#   - `memory/feedback-*.md`
#   - `memory/<topic>/feedback_*.md`
#   - `memory/<topic>/feedback-*.md`
#
# State: /tmp/polaris-session-feedback-reads.txt
#   Override via POLARIS_FEEDBACK_READS_STATE for tests.
#
# Exit codes:
#   0 — always

set -u

STATE_FILE="${POLARIS_FEEDBACK_READS_STATE:-/tmp/polaris-session-feedback-reads.txt}"

input=$(cat 2>/dev/null || true)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Defend the matcher.
[[ "$tool_name" == "Read" ]] || exit 0

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

[[ -z "$file_path" ]] && exit 0

# Only track feedback memory files. Accept both `feedback_*` and `feedback-*`
# prefixes. The path segment `memory/` must be present (guards against
# matching unrelated `feedback*.md` elsewhere in the workspace).
if ! printf '%s' "$file_path" \
   | grep -qE '(^|/)memory/([^/]+/)?feedback[_-][^/]*\.md$'; then
  exit 0
fi

# Dedup append: skip if the path is already on a line in the state file.
if [[ -f "$STATE_FILE" ]] && grep -qxF "$file_path" "$STATE_FILE" 2>/dev/null; then
  exit 0
fi

# Ensure directory exists (defensive — /tmp always does, but honor override).
state_dir=$(dirname "$STATE_FILE")
[[ -d "$state_dir" ]] || mkdir -p "$state_dir" 2>/dev/null || exit 0

printf '%s\n' "$file_path" >> "$STATE_FILE"

exit 0
