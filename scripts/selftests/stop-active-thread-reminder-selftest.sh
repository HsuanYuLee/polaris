#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/stop-active-thread-reminder.sh (DP-300 T2 + DP-314 T1).
#          Asserts the hook is a fail-closed Stop gate (no longer advisory-only) AND that the
#          DP-314 hardening holds:
#            D1 — per-session block-state: once the hook blocks it records a per-session
#                 block-state; on a later Stop in the SAME session, if the anchor was refreshed
#                 AFTER that block-state timestamp, the hook allows stop even when a concurrent
#                 session has since written a NEWER baseline (AC1 race). The block-state is NOT
#                 an unconditional pass: if the anchor was NOT refreshed after the block-state,
#                 the hook still blocks (AC-NEG3).
#            D2 — freshness window: a parked baseline whose mtime is OLDER than the freshness
#                 window (default 7 days, POLARIS_STOP_GATE_BASELINE_WINDOW_DAYS) does not count
#                 as an incomplete-work signal; an in-window baseline still does (AC2).
#          Plus the inherited DP-300 four-state contract and fail-open robustness:
#            - AC-NEG1 / state (a): in-window parked baseline + un-refreshed anchor -> BLOCK.
#            - state (b): no parked work -> exit 0 (allow stop).
#            - AC-NEG2 / state (c): explicit bypass (POLARIS_STOP_GATE_BYPASS=1) -> exit 0.
#            - state (d): parked work BUT anchor refreshed this session -> exit 0 (false-positive guard).
#            - AC4: bad Stop payload / missing runtime dir / corrupt block-state JSON -> fail-open exit 0.
#            - AC-NEG2 (prose): hook body carries no advisory-only prose; it emits a block decision.
#            - loop guard: stop_hook_active=true -> exit 0 (never re-block same turn).
# Inputs:  None (builds its own tmp git project + isolated POLARIS_RUNTIME_DIR per state).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/stop-active-thread-reminder.sh"

[[ -f "$HOOK" ]] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

TMP="$(mktemp -d -t dp314-stop-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

STOP_PAYLOAD='{"session_id":"deadbeefcafe0001","stop_hook_active":false}'

# Block-state path the hook owns, keyed by session id (D1).
blockstate_path() {
  # blockstate_path <project> <session_id>
  printf '%s/.polaris/runtime/stop-gate-block-state/%s.json' "$1" "$2"
}

# Build a fresh hermetic project per state so anchor/runtime state never leaks.
make_project() {
  local proj="$1"
  mkdir -p "$proj/.claude"
  mkdir -p "$proj/.polaris/runtime/skill-workflow-boundary"
}

# Write a parked skill-workflow-boundary baseline — the deterministic incomplete-work
# fallback signal per refinement R2/EC3 (boundary baseline exists but not closed out).
write_parked_baseline() {
  local proj="$1"
  cat >"$proj/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json" <<'JSON'
{
  "skill": "engineering",
  "session_id": "deadbeefcafe0001",
  "rel_container": "docs-manager/src/content/docs/specs/design-plans/DP-300-x",
  "head_sha": "0000000000000000000000000000000000000000",
  "dirty_at_start": [],
  "task_md": ""
}
JSON
}

baseline_file() {
  printf '%s/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json' "$1"
}

write_anchor() {
  local proj="$1"
  printf 'last-updated: 2026-06-09T00:00:00Z\n\n# 下一步\n\nDP-300-T2 parked.\n' \
    >"$proj/.claude/active-thread.md"
}

run_hook() {
  # run_hook <project> <payload> [extra env assignments...]
  local proj="$1"; local payload="$2"; shift 2
  printf '%s' "$payload" \
    | env CLAUDE_PROJECT_DIR="$proj" POLARIS_RUNTIME_DIR="$proj/.polaris/runtime" "$@" \
        bash "$HOOK"
}

# ---------------------------------------------------------------------------
# AC-NEG2: hook is a deterministic fail-closed gate, not advisory-only prose.
# ---------------------------------------------------------------------------
if grep -qiE 'advisory[ -]?only' "$HOOK"; then
  fail "AC-NEG2: hook still self-describes as advisory-only"
fi
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' "$HOOK" \
  || fail "AC-NEG2: hook does not emit a fail-closed block decision (still prose-only)"

# ---------------------------------------------------------------------------
# State (a) / AC-NEG1: in-window parked baseline + un-refreshed anchor -> BLOCK.
# Anchor is OLDER than the parked baseline -> not refreshed this work session.
# Baseline mtime is recent (within freshness window) so D2 does not filter it out.
# ---------------------------------------------------------------------------
PA="$TMP/state-a"
make_project "$PA"
write_anchor "$PA"
touch -t 202606090000 "$PA/.claude/active-thread.md"
write_parked_baseline "$PA"
# Recent baseline (now) — well inside the freshness window.
touch "$(baseline_file "$PA")"

set +e
OUT_A="$(run_hook "$PA" "$STOP_PAYLOAD" 2>/dev/null)"
CODE_A=$?
set -e
[[ "$CODE_A" -ne 0 ]] || fail "state (a)/AC-NEG1: expected non-zero block exit, got 0"
printf '%s' "$OUT_A" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
  || fail "state (a)/AC-NEG1: expected decision:block JSON on stdout"
printf '%s' "$OUT_A" | grep -q 'update-active-thread.sh' \
  || fail "state (a)/AC-NEG1: block reason must include the refresh command hint"
# D1: blocking must persist a per-session block-state file.
[[ -f "$(blockstate_path "$PA" deadbeefcafe0001)" ]] \
  || fail "state (a)/D1: block must persist a per-session block-state file"

# ---------------------------------------------------------------------------
# State (b): no parked work -> exit 0 (allow stop).
# ---------------------------------------------------------------------------
PB="$TMP/state-b"
make_project "$PB"
write_anchor "$PB"
# No parked baseline written -> no incomplete-work signal.
set +e
run_hook "$PB" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_B=$?
set -e
[[ "$CODE_B" -eq 0 ]] || fail "state (b): no-parked-work session must exit 0, got $CODE_B"

# ---------------------------------------------------------------------------
# State (c) / AC-NEG2: explicit bypass -> exit 0 even with parked work, and
# emits no block decision on stdout.
# ---------------------------------------------------------------------------
PC="$TMP/state-c"
make_project "$PC"
write_anchor "$PC"
touch -t 202606090000 "$PC/.claude/active-thread.md"
write_parked_baseline "$PC"
touch "$(baseline_file "$PC")"
set +e
OUT_C="$(run_hook "$PC" "$STOP_PAYLOAD" POLARIS_STOP_GATE_BYPASS=1 2>/dev/null)"
CODE_C=$?
set -e
[[ "$CODE_C" -eq 0 ]] || fail "state (c)/AC-NEG2: explicit bypass must exit 0, got $CODE_C"
printf '%s' "$OUT_C" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
  && fail "state (c)/AC-NEG2: bypass must not emit a block decision" || true

# ---------------------------------------------------------------------------
# State (d): parked work BUT anchor refreshed this session
# (anchor NEWER than baseline) -> exit 0 (false-positive guard).
# ---------------------------------------------------------------------------
PD="$TMP/state-d"
make_project "$PD"
write_parked_baseline "$PD"
touch -t 202606090000 "$(baseline_file "$PD")"
write_anchor "$PD"
touch -t 202606091200 "$PD/.claude/active-thread.md"
set +e
run_hook "$PD" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_D=$?
set -e
[[ "$CODE_D" -eq 0 ]] || fail "state (d): refreshed anchor must not be blocked, got $CODE_D"

# ---------------------------------------------------------------------------
# AC1: concurrent-baseline race. Sequence in ONE session:
#   1. block (anchor older than baseline) -> persists block-state.
#   2. user refreshes anchor (anchor now newer than the block-state timestamp).
#   3. ANOTHER session writes a NEWER baseline (now newer than the refreshed anchor).
#   4. Stop again -> must exit 0, relying on the per-session block-state record, NOT on
#      anchor-mtime > baseline-mtime luck (which would FAIL here, since baseline is newer).
# ---------------------------------------------------------------------------
P1="$TMP/state-ac1"
make_project "$P1"
write_anchor "$P1"
# Anchor older than the (in-window) baseline so the first Stop blocks.
AC1_ANCHOR_OLD="$(date -v-1d '+%Y%m%d%H%M' 2>/dev/null || date -d '1 day ago' '+%Y%m%d%H%M')"
touch -t "$AC1_ANCHOR_OLD" "$P1/.claude/active-thread.md"
write_parked_baseline "$P1"
# Recent baseline (now) — well inside the freshness window.
touch "$(baseline_file "$P1")"
# Step 1: first Stop -> block, writes block-state.
set +e
run_hook "$P1" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_1A=$?
set -e
[[ "$CODE_1A" -ne 0 ]] || fail "AC1 step1: first Stop must block, got $CODE_1A"
[[ -f "$(blockstate_path "$P1" deadbeefcafe0001)" ]] \
  || fail "AC1 step1: block-state file not written"
sleep 1
# Step 2: user refreshes the anchor (now strictly newer than the block-state record).
write_anchor "$P1"
touch "$P1/.claude/active-thread.md"
# Step 3: a concurrent session writes a NEWER baseline (newer than the refreshed anchor).
sleep 1
write_parked_baseline "$P1"
touch "$(baseline_file "$P1")"
# Step 4: second Stop in same session -> must allow (block-state + anchor-refreshed-after).
set +e
run_hook "$P1" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_1B=$?
set -e
[[ "$CODE_1B" -eq 0 ]] \
  || fail "AC1 step4: same-session refreshed anchor + concurrent newer baseline must exit 0, got $CODE_1B"

# ---------------------------------------------------------------------------
# AC-NEG3: block-state exists but anchor was NOT refreshed after the block.
# A concurrent session writes a newer baseline; the anchor stays stale. The hook
# must still BLOCK — block-state is not an unconditional pass.
# ---------------------------------------------------------------------------
P3="$TMP/state-neg3"
make_project "$P3"
write_anchor "$P3"
# Anchor older than the (in-window) baseline so the first Stop blocks.
NEG3_ANCHOR_OLD="$(date -v-1d '+%Y%m%d%H%M' 2>/dev/null || date -d '1 day ago' '+%Y%m%d%H%M')"
touch -t "$NEG3_ANCHOR_OLD" "$P3/.claude/active-thread.md"
write_parked_baseline "$P3"
# Recent baseline (now) — well inside the freshness window.
touch "$(baseline_file "$P3")"
# Step 1: first Stop -> block, writes block-state.
set +e
run_hook "$P3" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_3A=$?
set -e
[[ "$CODE_3A" -ne 0 ]] || fail "AC-NEG3 step1: first Stop must block, got $CODE_3A"
# Step 2: DO NOT refresh anchor. A concurrent session writes a newer baseline.
sleep 1
write_parked_baseline "$P3"
touch "$(baseline_file "$P3")"
# Step 3: second Stop -> must still block (anchor never refreshed after block-state).
set +e
OUT_3B="$(run_hook "$P3" "$STOP_PAYLOAD" 2>/dev/null)"
CODE_3B=$?
set -e
[[ "$CODE_3B" -ne 0 ]] \
  || fail "AC-NEG3 step3: un-refreshed anchor must still block despite block-state, got $CODE_3B"
printf '%s' "$OUT_3B" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
  || fail "AC-NEG3 step3: expected decision:block JSON on stdout"

# ---------------------------------------------------------------------------
# AC2: freshness window filtering.
#   (a) out-of-window baseline (mtime older than window) -> no incomplete-work signal -> exit 0,
#       even with a stale anchor.
#   (b) in-window baseline + stale anchor -> still block.
# ---------------------------------------------------------------------------
# (a) out-of-window (8 days old, default window 7) -> allow stop.
P2A="$TMP/state-ac2-out"
make_project "$P2A"
write_anchor "$P2A"
touch -t 202606090000 "$P2A/.claude/active-thread.md"
write_parked_baseline "$P2A"
OUT_OF_WINDOW="$(date -v-8d '+%Y%m%d%H%M' 2>/dev/null || date -d '8 days ago' '+%Y%m%d%H%M')"
touch -t "$OUT_OF_WINDOW" "$(baseline_file "$P2A")"
set +e
run_hook "$P2A" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_2A=$?
set -e
[[ "$CODE_2A" -eq 0 ]] \
  || fail "AC2(a): out-of-window baseline must not trigger incomplete-work, got $CODE_2A"

# (b) in-window (1 day old) + stale anchor -> block.
P2B="$TMP/state-ac2-in"
make_project "$P2B"
write_anchor "$P2B"
write_parked_baseline "$P2B"
IN_WINDOW="$(date -v-1d '+%Y%m%d%H%M' 2>/dev/null || date -d '1 day ago' '+%Y%m%d%H%M')"
# Anchor must be older than the in-window baseline so it counts as un-refreshed.
TWO_DAYS_AGO="$(date -v-2d '+%Y%m%d%H%M' 2>/dev/null || date -d '2 days ago' '+%Y%m%d%H%M')"
touch -t "$TWO_DAYS_AGO" "$P2B/.claude/active-thread.md"
touch -t "$IN_WINDOW" "$(baseline_file "$P2B")"
set +e
run_hook "$P2B" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_2B=$?
set -e
[[ "$CODE_2B" -ne 0 ]] \
  || fail "AC2(b): in-window baseline + stale anchor must block, got $CODE_2B"

# ---------------------------------------------------------------------------
# AC4: fail-open robustness — internal errors never crash the Stop chain.
# ---------------------------------------------------------------------------
# (a) malformed Stop payload (not JSON) -> exit 0.
P4A="$TMP/state-ac4-payload"
make_project "$P4A"
write_anchor "$P4A"
touch -t 202606090000 "$P4A/.claude/active-thread.md"
write_parked_baseline "$P4A"
touch "$(baseline_file "$P4A")"
set +e
run_hook "$P4A" 'this is not json {{{' >/dev/null 2>&1
CODE_4A=$?
set -e
[[ "$CODE_4A" -eq 0 ]] || fail "AC4(a): malformed Stop payload must fail-open exit 0, got $CODE_4A"

# (b) missing runtime dir -> exit 0 (no baseline signal resolvable).
P4B="$TMP/state-ac4-noruntime"
mkdir -p "$P4B/.claude"
write_anchor "$P4B"
set +e
printf '%s' "$STOP_PAYLOAD" \
  | env CLAUDE_PROJECT_DIR="$P4B" POLARIS_RUNTIME_DIR="$P4B/.polaris/does-not-exist" \
      bash "$HOOK" >/dev/null 2>&1
CODE_4B=$?
set -e
[[ "$CODE_4B" -eq 0 ]] || fail "AC4(b): missing runtime dir must fail-open exit 0, got $CODE_4B"

# (c) corrupt block-state JSON -> exit 0 (must not crash; block-state parse fails gracefully).
P4C="$TMP/state-ac4-corrupt"
make_project "$P4C"
write_anchor "$P4C"
touch -t 202606090000 "$P4C/.claude/active-thread.md"
write_parked_baseline "$P4C"
touch "$(baseline_file "$P4C")"
mkdir -p "$P4C/.polaris/runtime/stop-gate-block-state"
printf '{ corrupt json not closed' >"$(blockstate_path "$P4C" deadbeefcafe0001)"
set +e
run_hook "$P4C" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_4C=$?
set -e
[[ "$CODE_4C" -eq 0 ]] || fail "AC4(c): corrupt block-state JSON must fail-open exit 0, got $CODE_4C"

# ---------------------------------------------------------------------------
# Loop guard: stop_hook_active=true -> exit 0 even with parked + stale anchor.
# ---------------------------------------------------------------------------
PE="$TMP/state-loop"
make_project "$PE"
write_anchor "$PE"
touch -t 202606090000 "$PE/.claude/active-thread.md"
write_parked_baseline "$PE"
touch "$(baseline_file "$PE")"
set +e
run_hook "$PE" '{"session_id":"deadbeefcafe0001","stop_hook_active":true}' >/dev/null 2>&1
CODE_E=$?
set -e
[[ "$CODE_E" -eq 0 ]] || fail "loop guard: stop_hook_active=true must exit 0, got $CODE_E"

echo "PASS: stop-active-thread-reminder selftest (AC1 race, AC2 window, AC4 fail-open, AC-NEG1 block, AC-NEG2 bypass/gate, AC-NEG3 block-state-not-pass, loop guard)"
