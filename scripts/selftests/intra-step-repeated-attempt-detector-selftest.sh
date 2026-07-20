#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/intra-step-repeated-attempt-detector.sh
#          (DP-417 T7 / AC7 + AC-N1). Drives the PostToolUse detector via stdin
#          payloads and asserts the "打轉偵測器" (intra-step repeated-attempt)
#          contract:
#            AC7(a) same target file re-edited > N times      -> escalate marker.
#            AC7(b) same failing command retried > N times     -> escalate marker.
#            AC-N1  diverse edits across N distinct files       -> NO marker.
#          Plus: threshold boundary (exactly N -> no marker), succeeding commands
#          never counted, and fail-open (malformed / missing session_id -> exit 0,
#          no marker, never a block decision).
# Inputs:  None (builds its own tmp project dir; overrides CLAUDE_PROJECT_DIR and
#          POLARIS_RUNTIME_DIR so the run is hermetic, independent of the live
#          workspace). Threshold pinned via POLARIS_REPEATED_ATTEMPT_THRESHOLD.
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/intra-step-repeated-attempt-detector.sh"
TMP="$(mktemp -d -t dp417-repeated-attempt.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
RUNTIME="$PROJECT/.polaris/runtime"
ESCALATE_DIR="$RUNTIME/repeated-attempt/escalate"
mkdir -p "$PROJECT"

# Pin the threshold so the test is independent of the shipped default.
THRESHOLD=5

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$HOOK" ]] || fail "hook not found at $HOOK"

# feed <json-payload> — run the hook with a payload; assert it always exits 0 and
# never emits a block decision (a PostToolUse hook must not block the tool call).
feed() {
  local payload="$1" rc out
  set +e
  out="$(printf '%s' "$payload" \
    | CLAUDE_PROJECT_DIR="$PROJECT" \
      POLARIS_RUNTIME_DIR="$RUNTIME" \
      POLARIS_REPEATED_ATTEMPT_THRESHOLD="$THRESHOLD" \
      bash "$HOOK" 2>/dev/null)"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "hook exited $rc (must always exit 0) for payload: $payload"
  if grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<< "$out"; then
    fail "hook emitted a block decision — a PostToolUse detector must never block"
  fi
}

# marker_count — number of escalate marker files currently present.
marker_count() {
  find "$ESCALATE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

# reset_state — wipe all detector state between independent scenarios.
reset_state() {
  rm -rf "$RUNTIME/repeated-attempt"
}

edit_payload() {
  # edit_payload <session> <file_path>
  printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"},"tool_response":{}}' \
    "$1" "$2"
}

failing_bash_payload() {
  # failing_bash_payload <session> <command>
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"is_error":true}}' \
    "$1" "$2"
}

ok_bash_payload() {
  # ok_bash_payload <session> <command>
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"is_error":false}}' \
    "$1" "$2"
}

# ---- AC7(a): same target file re-edited > N times -> marker ----
reset_state
# First N edits (== threshold) must NOT trip (count > N required).
for _ in $(seq 1 "$THRESHOLD"); do
  feed "$(edit_payload sess-A /repo/src/same.ts)"
done
[[ "$(marker_count)" == "0" ]] || fail "AC7a boundary: marker emitted at exactly N=$THRESHOLD edits (should require > N)"
# The (N+1)th edit to the SAME file crosses the threshold -> marker.
feed "$(edit_payload sess-A /repo/src/same.ts)"
[[ "$(marker_count)" -ge 1 ]] || fail "AC7a: no escalate marker after $((THRESHOLD + 1)) edits to same file"

# ---- AC7(b): same failing command retried > N times -> marker ----
reset_state
for _ in $(seq 1 $((THRESHOLD + 1))); do
  feed "$(failing_bash_payload sess-B 'pnpm test failing-suite')"
done
[[ "$(marker_count)" -ge 1 ]] || fail "AC7b: no escalate marker after $((THRESHOLD + 1)) retries of same failing command"

# ---- AC7(b) negative: succeeding command repeats are NOT counted ----
reset_state
for _ in $(seq 1 $((THRESHOLD + 3))); do
  feed "$(ok_bash_payload sess-B2 'pnpm test passing-suite')"
done
[[ "$(marker_count)" == "0" ]] || fail "AC7b-neg: succeeding command repeats wrongly tripped the detector"

# ---- AC-N1: diverse edits across N+1 distinct files -> NO marker ----
reset_state
for i in $(seq 1 $((THRESHOLD + 1))); do
  feed "$(edit_payload sess-C "/repo/src/file_$i.ts")"
done
[[ "$(marker_count)" == "0" ]] || fail "AC-N1: diverse edits across distinct files falsely tripped the detector"

# ---- AC-N1 corollary: distinct failing commands do NOT accumulate on one key ----
reset_state
for i in $(seq 1 $((THRESHOLD + 1))); do
  feed "$(failing_bash_payload sess-C2 "cmd_number_$i")"
done
[[ "$(marker_count)" == "0" ]] || fail "AC-N1: distinct failing commands falsely tripped the detector"

# ---- fail-open: malformed / missing-session / non-tracked tool -> exit 0, no marker ----
reset_state
feed 'not-json-at-all'
feed ''
feed '{"tool_name":"Edit","tool_input":{"file_path":"/repo/x.ts"}}'          # no session_id
feed '{"session_id":"sess-D","tool_name":"Read","tool_input":{"file_path":"/repo/x.ts"}}'  # non-tracked tool
# Even repeating a read many times must never trip (Read is not an edit/command).
for _ in $(seq 1 $((THRESHOLD + 3))); do
  feed '{"session_id":"sess-D","tool_name":"Read","tool_input":{"file_path":"/repo/same.ts"}}'
done
[[ "$(marker_count)" == "0" ]] || fail "fail-open: malformed/non-tracked payloads emitted a marker"

# ---- isolation: crossing on sess-A must not create markers for a fresh session ----
reset_state
for _ in $(seq 1 $((THRESHOLD + 1))); do
  feed "$(edit_payload sess-E /repo/src/hot.ts)"
done
E_COUNT="$(marker_count)"
[[ "$E_COUNT" -ge 1 ]] || fail "isolation: expected marker for sess-E"
# A single edit on a different session/file must not add markers.
feed "$(edit_payload sess-F /repo/src/cold.ts)"
[[ "$(marker_count)" == "$E_COUNT" ]] || fail "isolation: unrelated session edit changed marker count"

echo "PASS: intra-step-repeated-attempt-detector-selftest (AC7 + AC-N1 + fail-open)"
