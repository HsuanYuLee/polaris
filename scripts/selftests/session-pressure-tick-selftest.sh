#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/session-pressure-tick.sh (DP-291 T1).
#          AC4 coverage: PostToolUse tick hook session-keyed tool-call counting —
#          distinct session_id values accumulate into separate state files
#          (.polaris/runtime/session-pressure/{session_id}.json) and never
#          cross-contaminate each other's counts; TTL cleanup removes stale files.
#          AC-NEG1 coverage: the hook always exits 0 (exit 2 would block the prompt) —
#          across missing state, corrupt state, missing session_id, and non-git dir
#          branches it must still exit 0 and never block.
# Inputs:  None (builds its own tmp project dir as CLAUDE_PROJECT_DIR).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/session-pressure-tick.sh"
TMP="$(mktemp -d -t dp291-session-pressure-tick.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name "Session Pressure Test"

STATE_DIR="$PROJECT/.polaris/runtime/session-pressure"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$HOOK" ]] || fail "hook not found at $HOOK"

# tick <session_id> <tool_name> — feed a PostToolUse JSON payload and assert exit 0.
tick() {
  local sid="$1" tool="$2" rc
  set +e
  printf '{"session_id":"%s","tool_name":"%s","tool_input":{},"tool_response":{}}' \
    "$sid" "$tool" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "hook exited $rc (must always exit 0) for session=$sid tool=$tool"
}

# read_count <session_id> — echo the recorded count for a session's state file (0 if missing).
read_count() {
  local sid="$1" f="$STATE_DIR/$1.json"
  if [[ ! -f "$f" ]]; then
    echo 0
    return
  fi
  python3 -c "import sys,json;
try:
    print(int(json.load(open('$f')).get('count',0)))
except Exception:
    print(-1)"
}

# ---- AC4: session-keyed counting + isolation ----
# Session A: 5 counted tool calls. Session B: 2 counted tool calls.
for _ in 1 2 3 4 5; do tick "sess-A" "Bash"; done
for _ in 1 2; do tick "sess-B" "Read"; done

CA="$(read_count sess-A)"
CB="$(read_count sess-B)"
[[ "$CA" == "5" ]] || fail "AC4: session A count expected 5, got $CA"
[[ "$CB" == "2" ]] || fail "AC4: session B count expected 2, got $CB"

# Distinct state files exist (no shared global counter).
[[ -f "$STATE_DIR/sess-A.json" ]] || fail "AC4: session A state file missing"
[[ -f "$STATE_DIR/sess-B.json" ]] || fail "AC4: session B state file missing"

# Incrementing A again must not change B (isolation).
tick "sess-A" "Edit"
CA2="$(read_count sess-A)"
CB2="$(read_count sess-B)"
[[ "$CA2" == "6" ]] || fail "AC4: session A count expected 6 after extra tick, got $CA2"
[[ "$CB2" == "2" ]] || fail "AC4: session B count changed to $CB2 — cross-session contamination"

# ---- AC4: TTL cleanup of stale session files ----
STALE="$STATE_DIR/sess-OLD.json"
printf '{"session_id":"sess-OLD","count":99}' > "$STALE"
# Backdate well beyond the TTL window (30 days).
touch -t 202001010000 "$STALE" 2>/dev/null || true
tick "sess-C" "Bash"
[[ ! -f "$STALE" ]] || fail "AC4: stale session file (>TTL) was not cleaned up by tick"
# A fresh file must survive cleanup.
[[ -f "$STATE_DIR/sess-A.json" ]] || fail "AC4: fresh session file wrongly removed by TTL cleanup"

# ---- AC-NEG1: exit 0 across error branches ----
# (1) Missing session_id in payload.
set +e
printf '{"tool_name":"Bash","tool_input":{}}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC-NEG1: missing session_id branch exited $rc, expected 0"

# (2) Corrupt / non-JSON payload.
set +e
printf 'not-json-at-all' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC-NEG1: corrupt payload branch exited $rc, expected 0"

# (3) Empty stdin.
set +e
printf '' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC-NEG1: empty stdin branch exited $rc, expected 0"

# (4) Corrupt existing state file — tick must reset/recover, not crash.
printf 'GARBAGE{{{' > "$STATE_DIR/sess-D.json"
set +e
printf '{"session_id":"sess-D","tool_name":"Bash"}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC-NEG1: corrupt existing state file branch exited $rc, expected 0"
CD="$(read_count sess-D)"
[[ "$CD" == "1" ]] || fail "AC-NEG1: corrupt state file not recovered (count reset to 1), got $CD"

# (5) Non-git directory (no CLAUDE_PROJECT_DIR, cwd not a repo).
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
set +e
printf '{"session_id":"sess-E","tool_name":"Bash"}' | \
  ( cd "$NONGIT" && unset CLAUDE_PROJECT_DIR && bash "$HOOK" >/dev/null 2>&1 )
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC-NEG1: non-git directory branch exited $rc, expected 0"

# ---- AC-NEG1 corollary: hook never blocks (no decision=block emitted) ----
out="$(printf '{"session_id":"sess-F","tool_name":"Bash"}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" 2>/dev/null || true)"
if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  fail "AC-NEG1: hook emitted a block decision — PostToolUse tick must never block"
fi

echo "PASS: session-pressure-tick-selftest (AC4 + AC-NEG1)"
