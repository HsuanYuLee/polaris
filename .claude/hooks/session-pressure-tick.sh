#!/usr/bin/env bash
# Purpose: PostToolUse tick hook (DP-291 T1). Accumulates a session-keyed tool-call
#          count into .polaris/runtime/session-pressure/{session_id}.json so the
#          DP-291 T2 UserPromptSubmit eval hook can read a real per-session pressure
#          signal instead of the old global /tmp counter. Counts only meaningful
#          tool calls (skips meta tools). Also TTL-prunes session state files older
#          than the retention window so parallel / dead sessions do not accumulate.
#          This replaces the unregistered dead-code scripts/context-pressure-monitor.sh.
# Inputs:  PostToolUse JSON payload on stdin (session_id, tool_name, ...). Project dir
#          resolves via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}.
#          Runtime state dir resolves via
#          ${POLARIS_RUNTIME_DIR:-<project>/.polaris/runtime}/session-pressure.
#          POLARIS_SESSION_PRESSURE_TTL_DAYS overrides the cleanup window (default 30).
# Outputs: No stdout (silent tick). Writes/updates one session state JSON file.
#          ALWAYS exits 0 — a PostToolUse hook that exits non-zero would surface as
#          an error; this hook must never block or fail the response.

# Deliberately NOT using `set -e`: any internal failure must fall through to exit 0
# rather than abort the hook (AC-NEG1).
set -uo pipefail 2>/dev/null || true

# Read the hook payload; empty on any failure.
INPUT="$(cat 2>/dev/null || true)"

# Resolve project dir (fail-open: if we cannot resolve, exit 0 without writing).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

RUNTIME_DIR="${POLARIS_RUNTIME_DIR:-$PROJECT_DIR/.polaris/runtime}"
STATE_DIR="$RUNTIME_DIR/session-pressure"

# Extract a payload field; empty string on any failure.
payload_field() {
  printf '%s' "$INPUT" | python3 -c "import sys,json;
try:
    print(json.load(sys.stdin).get('$1',''))
except Exception:
    pass" 2>/dev/null || true
}

SESSION_ID="$(payload_field session_id)"
TOOL_NAME="$(payload_field tool_name)"

# Missing session_id -> nothing to key on; exit 0 (AC-NEG1).
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Sanitize session_id into a filesystem-safe key (defensive; ids are normally uuids).
SAFE_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
if [ -z "$SAFE_ID" ]; then
  exit 0
fi

# Count only meaningful tool calls; skip internal / meta tools so the signal tracks
# real work rather than bookkeeping.
case "$TOOL_NAME" in
  Bash|Edit|Write|Read|Grep|Glob|Agent|NotebookEdit|MultiEdit|WebFetch|WebSearch)
    ;;
  *)
    exit 0
    ;;
esac

# --- TTL cleanup of stale session state files -------------------------------
# Prune files older than the retention window so dead / parallel sessions do not
# accumulate. Best-effort: any failure here must not block the tick.
TTL_DAYS="${POLARIS_SESSION_PRESSURE_TTL_DAYS:-30}"
case "$TTL_DAYS" in
  ''|*[!0-9]*) TTL_DAYS=30 ;;
esac
if [ -d "$STATE_DIR" ]; then
  find "$STATE_DIR" -maxdepth 1 -type f -name '*.json' -mtime "+$TTL_DAYS" -delete 2>/dev/null || true
fi

# --- increment this session's count -----------------------------------------
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/$SAFE_ID.json"

# Read the current count; treat a missing/corrupt file as 0 (AC-NEG1 recovery).
PREV=0
if [ -f "$STATE_FILE" ]; then
  PREV="$(python3 -c "import json;
try:
    print(int(json.load(open('$STATE_FILE')).get('count',0)))
except Exception:
    print(0)" 2>/dev/null || echo 0)"
  case "$PREV" in
    ''|*[!0-9]*) PREV=0 ;;
  esac
fi
NEXT=$((PREV + 1))

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"

# Atomic write via tmp + mv so a concurrent reader never sees a half-written file.
TMP_FILE="$STATE_FILE.tmp.$$"
if printf '{"session_id":"%s","count":%s,"last_tick":"%s"}\n' \
     "$SESSION_ID" "$NEXT" "$NOW" > "$TMP_FILE" 2>/dev/null; then
  mv -f "$TMP_FILE" "$STATE_FILE" 2>/dev/null || rm -f "$TMP_FILE" 2>/dev/null || true
fi

exit 0
