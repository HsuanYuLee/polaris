#!/usr/bin/env bash
# Purpose: SessionStart (matcher=startup) hook for DP-290 deterministic cross-session
#          handoff. Injects the active-thread anchor (.claude/active-thread.md) plus the
#          current git branch and dirty filenames into the session start context. This
#          replaces probabilistic memory recall with a deterministic cat.
# Inputs:  SessionStart JSON payload on stdin (ignored content-wise; project dir resolved
#          via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}).
# Outputs: Anchor body + branch + dirty filenames on stdout. ALWAYS exit 0 (fail-open):
#          missing anchor, non-git dir, or git failure prints a one-line notice and
#          continues. Commands limited to cat + git status/branch (no network, no build,
#          no env dump).

# NOTE: deliberately NOT using `set -e` — this hook must never block a session, so every
# branch falls through to `exit 0` even on internal error.
set -uo pipefail 2>/dev/null || true

# Drain stdin so the caller's pipe does not block; payload content is not needed.
cat >/dev/null 2>&1 || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$PROJECT_DIR" ]; then
  echo "[session-start-thread-anchor] fail-open: no project dir (not a git repo, CLAUDE_PROJECT_DIR unset); skipping anchor injection."
  exit 0
fi

ANCHOR_FILE="$PROJECT_DIR/.claude/active-thread.md"

echo "=== active-thread anchor (DP-290 cross-session handoff) ==="
if [ -f "$ANCHOR_FILE" ]; then
  # DP-300 T3: the anchor may now carry multiple keyed thread sections
  # (<!-- thread:KEY --> ... <!-- /thread:KEY -->). When more than one active
  # thread is parked, surface ALL of them — list every key up front so the
  # session-start context shows every parked 「下一步」, not just the first.
  THREAD_KEYS="$(grep -oE '^<!-- thread:[^ ]+ -->$' "$ANCHOR_FILE" 2>/dev/null \
    | sed -E 's/^<!-- thread:(.+) -->$/\1/' || true)"
  if [ -n "$THREAD_KEYS" ]; then
    THREAD_COUNT="$(printf '%s\n' "$THREAD_KEYS" | grep -c . || true)"
    echo "active threads ($THREAD_COUNT) — resume each 下一步 below:"
    printf '%s\n' "$THREAD_KEYS" | sed 's/^/  - thread: /'
  fi
  cat "$ANCHOR_FILE" 2>/dev/null || echo "[session-start-thread-anchor] fail-open: anchor unreadable; skipping."
else
  echo "[session-start-thread-anchor] fail-open: no active-thread anchor yet (run scripts/update-active-thread.sh to set the「下一步」handoff)."
fi

# Branch name (fail-open: blank if not a git repo).
BRANCH="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)"
if [ -n "$BRANCH" ]; then
  echo "branch: $BRANCH"
fi

# Dirty filenames only (no diff content, no env). Columns 1-2 are status codes; the
# remainder is the path. Fail-open on any git status failure.
DIRTY="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | sed 's/^...//' || true)"
if [ -n "$DIRTY" ]; then
  echo "dirty files:"
  printf '%s\n' "$DIRTY"
fi

exit 0
