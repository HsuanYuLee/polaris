#!/usr/bin/env bash
# scripts/check-feedback-signals.sh
#
# Purpose: Advisory — detect signals that a feedback memory SHOULD have been
#          written in this session, and nudge the Strategist to reflect.
#          Rule source: rules/feedback-and-memory.md
#                       § Correction = Immediate Reflection
#                       § Automatic Feedback Mechanism (item 4: command self-
#                         corrected; item 2-6 general reflection triggers).
#
# Canary: post-task-feedback-reflection (DP-030 Phase 2C — partial graduation
#         to deterministic signal capture; behavioral write still required)
#
# Signals monitored (path B scope — minimal viable subset):
#   1. Command self-correct — presence of `/tmp/polaris-test-sequence.json`
#      (populated by `scripts/test-sequence-tracker.sh`) AND/OR a sentinel
#      file `/tmp/polaris-cmd-self-correct.txt` (reserved for future writers)
#   2. New feedback memory files — count `feedback_*.md` files under the
#      workspace memory directory whose mtime is newer than the session start
#      timestamp (derived from the first line of
#      /tmp/polaris-session-calls.txt or a 24h fallback)
#
# Decision:
#   - If self-correct signal > 0 AND no new feedback file was written
#     this session → advisory reminder on stdout
#   - Otherwise → silent (exit 0)
#
# Mode: Advisory only. Exit 0 on every path.
#
# Exit codes:
#   0 — always (advisory on stdout when applicable)
#
# Environment variables:
#   POLARIS_MEMORY_DIR       — absolute path to workspace memory dir (default:
#                              ~/.claude/projects/-Users-hsuanyu-lee-work/memory)
#   POLARIS_SESSION_CALLS    — path to session-calls state file (default:
#                              /tmp/polaris-session-calls.txt)
#   POLARIS_TEST_SEQ_STATE   — path to test-sequence-tracker state (default:
#                              /tmp/polaris-test-sequence.json)
#   POLARIS_CMD_SELFCORRECT  — path to self-correct sentinel (default:
#                              /tmp/polaris-cmd-self-correct.txt; optional)
#
# Usage:
#   check-feedback-signals.sh [--skill <name>]
#
# Invoked by:
#   - .claude/hooks/feedback-reflection-stop.sh (Stop hook)
#   - .claude/skills/engineering/SKILL.md (L2 post-delivery tail)
#   - .claude/skills/verify-AC/SKILL.md (L2 tail)
#   - .claude/skills/breakdown/SKILL.md (L2 tail)
#   - .claude/skills/refinement/SKILL.md (L2 tail)

set -u

DEFAULT_MEMORY_DIR="$HOME/.claude/projects/-Users-hsuanyu-lee-work/memory"
MEMORY_DIR="${POLARIS_MEMORY_DIR:-$DEFAULT_MEMORY_DIR}"
CALLS_FILE="${POLARIS_SESSION_CALLS:-/tmp/polaris-session-calls.txt}"
TEST_SEQ_STATE="${POLARIS_TEST_SEQ_STATE:-/tmp/polaris-test-sequence.json}"
CMD_SELFCORRECT="${POLARIS_CMD_SELFCORRECT:-/tmp/polaris-cmd-self-correct.txt}"
SKILL_TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)
      SKILL_TAG="${2:-}"
      shift 2
      ;;
    --skill=*)
      SKILL_TAG="${1#--skill=}"
      shift
      ;;
    -h|--help)
      sed -n '2,40p' "$0" >&2
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# --- Determine session start epoch ---
# Prefer first-line mtime of calls file; fallback to 24h ago.
session_start_epoch=0
if [[ -f "$CALLS_FILE" ]]; then
  if stat -f %m "$CALLS_FILE" >/dev/null 2>&1; then
    session_start_epoch=$(stat -f %B "$CALLS_FILE" 2>/dev/null \
      || stat -f %m "$CALLS_FILE")  # BSD: %B = birth, fall back to mtime
  else
    # GNU: use creation if recorded, else mtime
    session_start_epoch=$(stat -c %Y "$CALLS_FILE" 2>/dev/null || echo 0)
  fi
fi

# Heuristic fallback: last 24h (some macOS filesystems lack birth-time).
if [[ -z "$session_start_epoch" || "$session_start_epoch" -eq 0 ]]; then
  now_epoch=$(date +%s)
  session_start_epoch=$((now_epoch - 86400))
fi

# --- Signal 1: command self-correct ---
self_correct=0
# test-sequence-tracker state: presence of file means a failing→edit sequence
# is active. Count that as a self-correct signal.
if [[ -f "$TEST_SEQ_STATE" ]]; then
  self_correct=$((self_correct + 1))
fi
# Optional sentinel for non-test self-correct (reserved for future writers).
if [[ -f "$CMD_SELFCORRECT" ]]; then
  # Count non-empty lines as individual self-correct events.
  extra=$(grep -c . "$CMD_SELFCORRECT" 2>/dev/null || echo 0)
  self_correct=$((self_correct + extra))
fi

# --- Signal 2: new feedback memory files this session ---
new_feedback_count=0
if [[ -d "$MEMORY_DIR" ]]; then
  # macOS `find -newermt` needs an ISO string; use `-newer` against a ref file.
  ref_file=$(mktemp)
  # Touch ref_file to session_start_epoch.
  if date -r "$session_start_epoch" >/dev/null 2>&1; then
    # BSD date -r epoch (macOS)
    touch -t "$(date -r "$session_start_epoch" '+%Y%m%d%H%M.%S')" "$ref_file" 2>/dev/null || true
  else
    # GNU date
    touch -d "@$session_start_epoch" "$ref_file" 2>/dev/null || true
  fi

  # Find feedback memory files newer than ref_file (flat + one-level topic folders).
  new_feedback_count=$(find "$MEMORY_DIR" \
      -maxdepth 2 \
      -type f \
      -name 'feedback*.md' \
      -newer "$ref_file" 2>/dev/null \
    | wc -l | tr -d ' ')
  rm -f "$ref_file"
fi

# --- Decide advisory emission ---
if (( self_correct > 0 )) && (( new_feedback_count == 0 )); then
  skill_hint=""
  [[ -n "$SKILL_TAG" ]] && skill_hint=" (skill: ${SKILL_TAG})"
  cat <<EOF

[post-task-feedback-reflection] Advisory${skill_hint}: detected ${self_correct} self-correct signal(s) this session but NO new feedback memory was written.

Per rules/feedback-and-memory.md (items 3–6), the post-task reflection pass
should consider writing a feedback memory when:
  • A command failed and you self-corrected (wrong path/param/API format)
  • You were blocked by a hook / permission
  • You were stuck for 2+ rounds without resolution
  • The user corrected a behavior (framework-level → feedback memory;
    repo-specific → handbook sub-file instead)

If you already ruled this out (repo-specific → handbook, or the correction
was trivial), ignore this advisory. Otherwise: write the feedback memory
before ending the session.
EOF
fi

exit 0
