#!/usr/bin/env bash
# Purpose: PostToolUse "打轉偵測器" (intra-step repeated-attempt detector, DP-417 T7).
#          Counts, per session, how many times the agent (a) re-edits the SAME target
#          file and (b) retries the SAME FAILING command. When a key's count crosses a
#          configurable threshold N, it emits an escalate marker file + a stderr
#          advisory so the agent stops spinning (and asks for help) instead of burning
#          tokens on an infinite retry loop. Diverse edits across distinct files never
#          accumulate on one key (each distinct file/command is its own key), so honest
#          progress is not flagged (AC-N1).
# Inputs:  PostToolUse JSON payload on stdin (session_id, tool_name,
#          tool_input.file_path / tool_input.command, tool_response). Project dir
#          resolves via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}.
#          Runtime state dir resolves via
#          ${POLARIS_RUNTIME_DIR:-<project>/.polaris/runtime}/repeated-attempt.
#          POLARIS_REPEATED_ATTEMPT_THRESHOLD overrides N (default 5).
#          POLARIS_REPEATED_ATTEMPT_TTL_DAYS overrides the counter-prune window (default 30).
# Outputs: No stdout. Writes/updates one per-key counter file; on threshold crossing
#          writes an escalate marker JSON and prints one advisory line to stderr.
#          ALWAYS exits 0 — advisory only; a PostToolUse detector must never block or
#          fail the tool call.

# Deliberately NOT using `set -e`: any internal failure must fall through to exit 0
# rather than abort the hook (fail-open).
set -uo pipefail 2>/dev/null || true

# Default threshold: emit only after MORE than this many repeats of one key. Kept
# generous so ordinary short retry cycles do not trip; a runaway loop still crosses it.
DEFAULT_THRESHOLD=5

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
STATE_DIR="$RUNTIME_DIR/repeated-attempt"
COUNTER_DIR="$STATE_DIR/counters"
ESCALATE_DIR="$STATE_DIR/escalate"

# Resolve threshold; fall back to the default on any non-numeric / empty override.
THRESHOLD="${POLARIS_REPEATED_ATTEMPT_THRESHOLD:-$DEFAULT_THRESHOLD}"
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD="$DEFAULT_THRESHOLD" ;;
esac

# Extract the countable signal from the payload. Prints exactly four lines:
#   1 session_id  2 category (edit|command|none)  3 key_hash  4 key_display
# category is "edit" only for Edit/Write/MultiEdit with a file_path, and "command"
# only for a Bash call whose tool_response indicates failure; everything else is
# "none" (not counted). Any parse failure prints a safe "none" record.
# Captured into a single string, then split by line (portable to bash 3.2, which
# lacks `mapfile`).
FIELDS_RAW="$(printf '%s' "$INPUT" | python3 -c '
import sys, json, hashlib


def command_failed(tr):
    """Return True when a Bash tool_response indicates a failed command."""
    if not isinstance(tr, dict):
        return False
    if tr.get("is_error") is True or tr.get("interrupted") is True:
        return True
    for k in ("exit_code", "exitCode", "returncode", "code", "exit_status"):
        v = tr.get(k)
        if isinstance(v, bool):
            continue
        if isinstance(v, (int, float)) and int(v) != 0:
            return True
    return False


try:
    d = json.load(sys.stdin)
except Exception:
    print(); print("none"); print(); print()
    sys.exit(0)

sid = str(d.get("session_id", "") or "")
tool = str(d.get("tool_name", "") or "")
ti = d.get("tool_input")
if not isinstance(ti, dict):
    ti = {}

category = "none"
key = ""
if tool in ("Edit", "Write", "MultiEdit"):
    fp = ti.get("file_path") or ti.get("filePath") or ""
    if fp:
        category = "edit"
        key = str(fp)
elif tool == "Bash":
    cmd = ti.get("command") or ""
    if cmd and command_failed(d.get("tool_response")):
        category = "command"
        key = str(cmd)

key_hash = hashlib.sha256(key.encode("utf-8")).hexdigest()[:16] if key else ""
key_display = " ".join(key.split())[:200]
print(sid)
print(category)
print(key_hash)
print(key_display)
' 2>/dev/null || true)"

SESSION_ID="$(printf '%s\n' "$FIELDS_RAW" | sed -n '1p')"
CATEGORY="$(printf '%s\n' "$FIELDS_RAW" | sed -n '2p')"
KEY_HASH="$(printf '%s\n' "$FIELDS_RAW" | sed -n '3p')"
KEY_DISPLAY="$(printf '%s\n' "$FIELDS_RAW" | sed -n '4p')"

# Missing session_id -> nothing to key on; exit 0.
[ -n "$SESSION_ID" ] || exit 0
# Only edit / failing-command signals are countable; everything else is ignored.
case "$CATEGORY" in
  edit|command) ;;
  *) exit 0 ;;
esac
[ -n "$KEY_HASH" ] || exit 0

# Sanitize session_id into a filesystem-safe key (defensive; ids are normally uuids).
SAFE_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
[ -n "$SAFE_ID" ] || exit 0

# --- TTL prune of stale counters/markers -----------------------------------
# Prune files older than the retention window so dead / parallel sessions do not
# accumulate. Best-effort: any failure here must not block the hook.
TTL_DAYS="${POLARIS_REPEATED_ATTEMPT_TTL_DAYS:-30}"
case "$TTL_DAYS" in
  ''|*[!0-9]*) TTL_DAYS=30 ;;
esac
for d in "$COUNTER_DIR" "$ESCALATE_DIR"; do
  if [ -d "$d" ]; then
    find "$d" -maxdepth 1 -type f -name '*.json' -mtime "+$TTL_DAYS" -delete 2>/dev/null || true
  fi
done

# --- increment this key's count --------------------------------------------
mkdir -p "$COUNTER_DIR" 2>/dev/null || exit 0
COUNTER_FILE="$COUNTER_DIR/${SAFE_ID}__${CATEGORY}__${KEY_HASH}.json"

PREV=0
if [ -f "$COUNTER_FILE" ]; then
  PREV="$(python3 -c "import json;
try:
    print(int(json.load(open('$COUNTER_FILE')).get('count',0)))
except Exception:
    print(0)" 2>/dev/null || echo 0)"
  case "$PREV" in
    ''|*[!0-9]*) PREV=0 ;;
  esac
fi
NEXT=$((PREV + 1))

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"

# Atomic write via tmp + mv so a concurrent reader never sees a half-written file.
TMP_FILE="$COUNTER_FILE.tmp.$$"
if printf '{"session_id":"%s","category":"%s","key_hash":"%s","count":%s,"last_seen":"%s"}\n' \
     "$SESSION_ID" "$CATEGORY" "$KEY_HASH" "$NEXT" "$NOW" > "$TMP_FILE" 2>/dev/null; then
  mv -f "$TMP_FILE" "$COUNTER_FILE" 2>/dev/null || rm -f "$TMP_FILE" 2>/dev/null || true
fi

# --- threshold crossing: emit escalate marker + stderr advisory ------------
if [ "$NEXT" -gt "$THRESHOLD" ]; then
  mkdir -p "$ESCALATE_DIR" 2>/dev/null || exit 0
  MARKER_FILE="$ESCALATE_DIR/${SAFE_ID}__${CATEGORY}__${KEY_HASH}.json"
  MARKER_TMP="$MARKER_FILE.tmp.$$"
  # key_display is JSON-encoded via python to stay valid regardless of contents.
  KEY_JSON="$(printf '%s' "$KEY_DISPLAY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""')"
  if printf '{"session_id":"%s","category":"%s","key_hash":"%s","key":%s,"count":%s,"threshold":%s,"detected_at":"%s"}\n' \
       "$SESSION_ID" "$CATEGORY" "$KEY_HASH" "$KEY_JSON" "$NEXT" "$THRESHOLD" "$NOW" > "$MARKER_TMP" 2>/dev/null; then
    mv -f "$MARKER_TMP" "$MARKER_FILE" 2>/dev/null || rm -f "$MARKER_TMP" 2>/dev/null || true
  fi
  if [ "$CATEGORY" = "edit" ]; then
    printf '[REPEATED-ATTEMPT] escalate: same file re-edited %s times (threshold %s): %s — stop and ask for help instead of spinning.\n' \
      "$NEXT" "$THRESHOLD" "$KEY_DISPLAY" >&2
  else
    printf '[REPEATED-ATTEMPT] escalate: same failing command retried %s times (threshold %s): %s — stop and ask for help instead of spinning.\n' \
      "$NEXT" "$THRESHOLD" "$KEY_DISPLAY" >&2
  fi
fi

exit 0
