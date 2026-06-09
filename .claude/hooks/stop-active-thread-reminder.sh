#!/usr/bin/env bash
# Purpose: Stop (session-end) fail-closed gate for the active-thread anchor (DP-300 T2).
#          When the session still has parked / incomplete work AND the active-thread
#          anchor (.claude/active-thread.md) was NOT refreshed this work session, block
#          the stop once and tell the user to refresh the anchor via
#          scripts/update-active-thread.sh, so the next session's SessionStart hook
#          injects a current 「下一步」 handoff instead of a stale one. This replaces the
#          prior non-blocking reminder whose writer trigger never actually fired
#          (active-thread-writer-trigger-gap canary).
# Inputs:  Stop JSON payload on stdin (session_id, stop_hook_active). Project dir resolves
#          via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}. Runtime baseline
#          dir resolves via ${POLARIS_RUNTIME_DIR:-<project>/.polaris/runtime}.
#          POLARIS_STOP_GATE_BYPASS=1 is the explicit user opt-out.
# Outputs: On block: a JSON {"decision":"block","reason":"..."} object on stdout and
#          exit 2. Otherwise: nothing on stdout, exit 0 (allow stop).
# Signals:
#   - incomplete-work (fallback, no TodoWrite state available to a Stop hook): there is at
#     least one un-closed-out skill-workflow-boundary baseline file
#     ($RUNTIME_DIR/skill-workflow-boundary/*.json) OR the working tree has dirty tracked
#     files.
#   - anchor-not-refreshed: .claude/active-thread.md is missing, OR its mtime is OLDER
#     than the newest parked boundary baseline (the parked work began after the last
#     anchor refresh -> the anchor is stale for this session).
#   Block only when BOTH hold (AC2). No parked work or refreshed anchor -> exit 0
#   (AC3 / AC-NEG1 false-positive guard).

# Deliberately NOT using `set -e`: every internal failure must fall through to a safe
# decision rather than crash the Stop hook.
set -uo pipefail 2>/dev/null || true

INPUT="$(cat 2>/dev/null || true)"

emit_int() {
  # Parse a single key out of the Stop JSON payload; empty on any failure.
  printf '%s' "$INPUT" \
    | python3 -c "import sys,json;
try:
    print(json.load(sys.stdin).get('$1',''))
except Exception:
    pass" 2>/dev/null || true
}

# Loop guard: if this Stop hook already ran this turn, allow stop (never re-block).
STOP_HOOK_ACTIVE="$(emit_int stop_hook_active)"
case "$STOP_HOOK_ACTIVE" in
  True|true) exit 0 ;;
esac

# Explicit user bypass (AC3): user signalled "I'm done / no parked work".
if [ "${POLARIS_STOP_GATE_BYPASS:-0}" = "1" ]; then
  exit 0
fi

# Resolve project dir (fail-open: cannot evaluate -> allow stop).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

ANCHOR_FILE="$PROJECT_DIR/.claude/active-thread.md"
RUNTIME_DIR="${POLARIS_RUNTIME_DIR:-$PROJECT_DIR/.polaris/runtime}"
BASELINE_DIR="$RUNTIME_DIR/skill-workflow-boundary"

# --- incomplete-work signal (fallback) -------------------------------------
# (1) any un-closed-out skill-workflow-boundary baseline = a parked skill session.
PARKED_BASELINE=""
NEWEST_BASELINE_MTIME=0
if [ -d "$BASELINE_DIR" ]; then
  for f in "$BASELINE_DIR"/*.json; do
    [ -e "$f" ] || continue
    PARKED_BASELINE="$f"
    m="$(date -r "$f" +%s 2>/dev/null || echo 0)"
    if [ "$m" -gt "$NEWEST_BASELINE_MTIME" ]; then
      NEWEST_BASELINE_MTIME="$m"
    fi
  done
fi

# (2) dirty tracked files in the working tree (secondary incomplete-work signal).
DIRTY=""
DIRTY="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | head -n1 || true)"

if [ -z "$PARKED_BASELINE" ] && [ -z "$DIRTY" ]; then
  # No incomplete work -> never block (AC3 / AC-NEG1).
  exit 0
fi

# --- anchor-not-refreshed signal -------------------------------------------
ANCHOR_STALE=0
if [ ! -f "$ANCHOR_FILE" ]; then
  # No anchor at all but there is parked work -> stale (nothing to hand off).
  ANCHOR_STALE=1
else
  ANCHOR_MTIME="$(date -r "$ANCHOR_FILE" +%s 2>/dev/null || echo 0)"
  # If a parked baseline exists and the anchor predates the newest baseline, the
  # anchor was not refreshed since this work session's parking began.
  if [ "$NEWEST_BASELINE_MTIME" -gt 0 ] && [ "$ANCHOR_MTIME" -lt "$NEWEST_BASELINE_MTIME" ]; then
    ANCHOR_STALE=1
  fi
fi

if [ "$ANCHOR_STALE" -ne 1 ]; then
  # Anchor refreshed this session (AC-NEG1 false-positive guard) -> allow stop.
  exit 0
fi

# --- fail-closed block (AC2) -----------------------------------------------
REASON='[stop-active-thread-reminder] 偵測到 parked / incomplete work，但本 session 的 active-thread 錨點 (.claude/active-thread.md) 尚未刷新。請先執行 `bash scripts/update-active-thread.sh` 寫入最新「下一步」handoff，再結束 session；或在確認無 parked work 時設 POLARIS_STOP_GATE_BYPASS=1 明確跳過。'
printf '%s\n' "{\"decision\":\"block\",\"reason\":\"$REASON\"}"
exit 2
