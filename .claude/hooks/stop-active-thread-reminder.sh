#!/usr/bin/env bash
# Purpose: Stop (session-end) fail-closed gate for the active-thread anchor (DP-300 T2 + DP-314 T1).
#          When the session still has parked / incomplete work AND the active-thread anchor
#          (.claude/active-thread.md) was NOT refreshed this work session, block the stop and tell
#          the user to refresh the anchor via scripts/update-active-thread.sh, so the next session's
#          SessionStart hook injects a current 「下一步」 handoff instead of a stale one.
#
#          DP-314 T1 hardens two concurrent-session false-positive paths:
#            D1 — per-session block-state: when the hook blocks it persists a per-session
#                 block-state record (timestamp keyed by session_id). On a later Stop in the
#                 SAME session, if the anchor was refreshed AFTER that block-state timestamp, the
#                 hook allows stop even when a concurrent session has since written a NEWER
#                 baseline (so the anchor mtime no longer beats the newest baseline mtime). The
#                 block-state is NOT an unconditional pass: if the anchor was not refreshed after
#                 the block, the hook still blocks.
#            D2 — freshness window: a parked baseline whose mtime is older than the freshness
#                 window (default 7 days) no longer counts as an incomplete-work signal, so stale
#                 leftover baselines from old sessions do not block forever.
# Inputs:  Stop JSON payload on stdin (session_id, stop_hook_active). Project dir resolves
#          via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}. Runtime baseline
#          dir resolves via ${POLARIS_RUNTIME_DIR:-<project>/.polaris/runtime}.
#          POLARIS_STOP_GATE_BYPASS=1 is the explicit user opt-out.
#          POLARIS_STOP_GATE_BASELINE_WINDOW_DAYS overrides the D2 freshness window (default 7).
# Outputs: On block: a JSON {"decision":"block","reason":"..."} object on stdout, a per-session
#          block-state file under $RUNTIME_DIR/stop-gate-block-state/<session_id>.json, and exit 2.
#          Otherwise: nothing on stdout, exit 0 (allow stop).
# Signals:
#   - incomplete-work (fallback, no TodoWrite state available to a Stop hook): there is at least
#     one un-closed-out skill-workflow-boundary baseline ($RUNTIME_DIR/skill-workflow-boundary/*.json)
#     whose mtime is within the freshness window (D2), OR the working tree has dirty tracked files.
#   - anchor-refreshed (D1): a per-session block-state record exists AND the anchor mtime is newer
#     than the recorded block timestamp -> the user already refreshed the anchor in response to a
#     prior block this session; allow stop regardless of concurrent baseline churn.
#   - anchor-not-refreshed: .claude/active-thread.md is missing, OR (no block-state pass) its mtime
#     is OLDER than the newest in-window parked baseline.
#   Block only when there is incomplete work AND the anchor is not refreshed. No parked work,
#   refreshed anchor, or a satisfied block-state pass -> exit 0 (false-positive guard).

# Deliberately NOT using `set -e`: every internal failure must fall through to a safe
# decision rather than crash the Stop hook.
set -uo pipefail 2>/dev/null || true

# D2 default freshness window for parked baselines, in days. Baselines whose mtime is older
# than this window are treated as stale leftovers and do not signal incomplete work.
DEFAULT_BASELINE_WINDOW_DAYS=7

INPUT="$(cat 2>/dev/null || true)"

emit_field() {
  # Parse a single key out of the Stop JSON payload; empty on any failure (fail-open).
  printf '%s' "$INPUT" \
    | python3 -c "import sys,json;
try:
    print(json.load(sys.stdin).get('$1',''))
except Exception:
    pass" 2>/dev/null || true
}

# Loop guard: if this Stop hook already ran this turn, allow stop (never re-block).
STOP_HOOK_ACTIVE="$(emit_field stop_hook_active)"
case "$STOP_HOOK_ACTIVE" in
  True|true) exit 0 ;;
esac

# Explicit user bypass: user signalled "I'm done / no parked work".
if [ "${POLARIS_STOP_GATE_BYPASS:-0}" = "1" ]; then
  exit 0
fi

SESSION_ID="$(emit_field session_id)"

# Fail-open on a malformed / session-less Stop payload (AC4 / EC2): without a session_id the
# per-session block-state contract (D1) cannot be tracked, and a bad payload is an internal
# error that must never crash or wrongly block the Stop chain.
if [ -z "$SESSION_ID" ]; then
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
BLOCK_STATE_DIR="$RUNTIME_DIR/stop-gate-block-state"

# Resolve the freshness window (seconds), fail-open to the default on any bad value.
WINDOW_DAYS="${POLARIS_STOP_GATE_BASELINE_WINDOW_DAYS:-$DEFAULT_BASELINE_WINDOW_DAYS}"
case "$WINDOW_DAYS" in
  ''|*[!0-9]*) WINDOW_DAYS="$DEFAULT_BASELINE_WINDOW_DAYS" ;;
esac
NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
WINDOW_CUTOFF=$(( NOW_EPOCH - WINDOW_DAYS * 86400 ))

# --- incomplete-work signal (fallback) -------------------------------------
# (1) any un-closed-out skill-workflow-boundary baseline whose mtime is within the freshness
#     window (D2) = a parked skill session. Stale (out-of-window) baselines are ignored.
PARKED_BASELINE=""
NEWEST_BASELINE_MTIME=0
if [ -d "$BASELINE_DIR" ]; then
  for f in "$BASELINE_DIR"/*.json; do
    [ -e "$f" ] || continue
    m="$(date -r "$f" +%s 2>/dev/null || echo 0)"
    # D2: skip baselines older than the freshness window.
    if [ "$m" -lt "$WINDOW_CUTOFF" ]; then
      continue
    fi
    PARKED_BASELINE="$f"
    if [ "$m" -gt "$NEWEST_BASELINE_MTIME" ]; then
      NEWEST_BASELINE_MTIME="$m"
    fi
  done
fi

# (2) dirty tracked files in the working tree (secondary incomplete-work signal).
DIRTY=""
DIRTY="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | head -n1 || true)"

if [ -z "$PARKED_BASELINE" ] && [ -z "$DIRTY" ]; then
  # No incomplete work -> never block (false-positive guard).
  exit 0
fi

# Resolve the anchor mtime once (0 if missing).
ANCHOR_MTIME=0
if [ -f "$ANCHOR_FILE" ]; then
  ANCHOR_MTIME="$(date -r "$ANCHOR_FILE" +%s 2>/dev/null || echo 0)"
fi

# --- D1 per-session block-state pass --------------------------------------
# If this session was already blocked once and the user has since refreshed the anchor (anchor
# mtime strictly newer than the recorded block timestamp), allow stop — even if a concurrent
# session has written a newer baseline. The block-state is NOT an unconditional pass.
BLOCK_STATE_FILE=""
if [ -n "$SESSION_ID" ]; then
  BLOCK_STATE_FILE="$BLOCK_STATE_DIR/$SESSION_ID.json"
fi
if [ -n "$BLOCK_STATE_FILE" ] && [ -f "$BLOCK_STATE_FILE" ]; then
  # Read the recorded block epoch from the block-state JSON. A parse failure prints the
  # sentinel "ERR" so a corrupt block-state file fails OPEN (EC3 / AC4) rather than crashing
  # or silently keeping the gate closed.
  BLOCKED_AT="$(printf '%s' "$(cat "$BLOCK_STATE_FILE" 2>/dev/null || true)" \
    | python3 -c "import sys,json;
try:
    print(int(json.load(sys.stdin).get('blocked_at_epoch',0)))
except Exception:
    print('ERR')" 2>/dev/null || echo ERR)"
  if [ "$BLOCKED_AT" = "ERR" ]; then
    # Corrupt block-state JSON -> internal error -> fail-open allow stop (EC3 / AC4).
    exit 0
  fi
  case "$BLOCKED_AT" in
    ''|*[!0-9]*) BLOCKED_AT=0 ;;
  esac
  if [ "$BLOCKED_AT" -gt 0 ] && [ "$ANCHOR_MTIME" -gt "$BLOCKED_AT" ]; then
    # Anchor refreshed after the prior block this session -> allow stop (AC1).
    exit 0
  fi
fi

# --- anchor-not-refreshed signal -------------------------------------------
ANCHOR_STALE=0
if [ ! -f "$ANCHOR_FILE" ]; then
  # No anchor at all but there is parked work -> stale (nothing to hand off).
  ANCHOR_STALE=1
elif [ "$NEWEST_BASELINE_MTIME" -gt 0 ] && [ "$ANCHOR_MTIME" -lt "$NEWEST_BASELINE_MTIME" ]; then
  # A parked baseline exists and the anchor predates the newest in-window baseline -> the
  # anchor was not refreshed since this work session's parking began.
  ANCHOR_STALE=1
fi

if [ "$ANCHOR_STALE" -ne 1 ]; then
  # Anchor refreshed this session (false-positive guard) -> allow stop.
  exit 0
fi

# --- fail-closed block -----------------------------------------------------
# Persist a per-session block-state record so the D1 pass can fire next Stop once the user
# refreshes the anchor. Best-effort: any write failure falls through to the block decision.
if [ -n "$BLOCK_STATE_FILE" ]; then
  mkdir -p "$BLOCK_STATE_DIR" 2>/dev/null || true
  printf '{"session_id":"%s","blocked_at_epoch":%s,"blocked_at_iso":"%s"}\n' \
    "$SESSION_ID" "$NOW_EPOCH" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '')" \
    >"$BLOCK_STATE_FILE" 2>/dev/null || true
fi

REASON='[stop-active-thread-reminder] 偵測到 parked / incomplete work，但本 session 的 active-thread 錨點 (.claude/active-thread.md) 尚未刷新。請先執行 `bash scripts/update-active-thread.sh` 寫入最新「下一步」handoff，再結束 session；或在確認無 parked work 時設 POLARIS_STOP_GATE_BYPASS=1 明確跳過。'
printf '%s\n' "{\"decision\":\"block\",\"reason\":\"$REASON\"}"
exit 2
