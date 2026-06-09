#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/stop-active-thread-reminder.sh (DP-300 T2).
#          Asserts the hook is a fail-closed Stop gate (no longer advisory-only):
#            - AC2 / state (a): incomplete work (parked skill-workflow-boundary baseline)
#              + un-refreshed anchor -> BLOCK (non-zero exit + decision:block reason).
#            - AC3 / state (b): no parked work -> exit 0 (allow stop).
#            - AC3 / state (c): explicit bypass (POLARIS_STOP_GATE_BYPASS=1) -> exit 0.
#            - AC-NEG1 / state (d): parked work BUT anchor refreshed this session
#              (anchor newer than baseline) -> exit 0 (false-positive guard).
#            - AC-NEG2: hook body carries no advisory-only prose; the trigger is a
#              deterministic fail-closed gate decision, not a prose reminder.
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

TMP="$(mktemp -d -t dp300-stop-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

STOP_PAYLOAD='{"session_id":"deadbeefcafe0001","stop_hook_active":false}'

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
# State (a) / AC2: incomplete work (parked baseline) + un-refreshed anchor -> BLOCK.
# Anchor is OLDER than the parked baseline -> not refreshed this work session.
# ---------------------------------------------------------------------------
PA="$TMP/state-a"
make_project "$PA"
write_anchor "$PA"
touch -t 202606090000 "$PA/.claude/active-thread.md"
write_parked_baseline "$PA"
touch -t 202606091200 "$PA"/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json

set +e
OUT_A="$(run_hook "$PA" "$STOP_PAYLOAD" 2>/dev/null)"
CODE_A=$?
set -e
[[ "$CODE_A" -ne 0 ]] || fail "state (a)/AC2: expected non-zero block exit, got 0"
printf '%s' "$OUT_A" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
  || fail "state (a)/AC2: expected decision:block JSON on stdout"
printf '%s' "$OUT_A" | grep -q 'update-active-thread.sh' \
  || fail "state (a)/AC2: block reason must include the refresh command hint"

# ---------------------------------------------------------------------------
# State (b) / AC3: no parked work -> exit 0 (allow stop).
# ---------------------------------------------------------------------------
PB="$TMP/state-b"
make_project "$PB"
write_anchor "$PB"
# No parked baseline written -> no incomplete-work signal.
set +e
run_hook "$PB" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_B=$?
set -e
[[ "$CODE_B" -eq 0 ]] || fail "state (b)/AC3: no-parked-work session must exit 0, got $CODE_B"

# ---------------------------------------------------------------------------
# State (c) / AC3: explicit bypass -> exit 0 even with parked work.
# ---------------------------------------------------------------------------
PC="$TMP/state-c"
make_project "$PC"
write_anchor "$PC"
touch -t 202606090000 "$PC/.claude/active-thread.md"
write_parked_baseline "$PC"
touch -t 202606091200 "$PC"/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json
set +e
run_hook "$PC" "$STOP_PAYLOAD" POLARIS_STOP_GATE_BYPASS=1 >/dev/null 2>&1
CODE_C=$?
set -e
[[ "$CODE_C" -eq 0 ]] || fail "state (c)/AC3: explicit bypass must exit 0, got $CODE_C"

# ---------------------------------------------------------------------------
# State (d) / AC-NEG1: parked work BUT anchor refreshed this session
# (anchor NEWER than baseline) -> exit 0 (false-positive guard).
# ---------------------------------------------------------------------------
PD="$TMP/state-d"
make_project "$PD"
write_parked_baseline "$PD"
touch -t 202606090000 "$PD"/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json
write_anchor "$PD"
touch -t 202606091200 "$PD/.claude/active-thread.md"
set +e
run_hook "$PD" "$STOP_PAYLOAD" >/dev/null 2>&1
CODE_D=$?
set -e
[[ "$CODE_D" -eq 0 ]] || fail "state (d)/AC-NEG1: refreshed anchor must not be blocked, got $CODE_D"

# ---------------------------------------------------------------------------
# Loop guard: stop_hook_active=true -> exit 0 even with parked + stale anchor.
# ---------------------------------------------------------------------------
PE="$TMP/state-loop"
make_project "$PE"
write_anchor "$PE"
touch -t 202606090000 "$PE/.claude/active-thread.md"
write_parked_baseline "$PE"
touch -t 202606091200 "$PE"/.polaris/runtime/skill-workflow-boundary/engineering-deadbeefcafe0001.json
set +e
run_hook "$PE" '{"session_id":"deadbeefcafe0001","stop_hook_active":true}' >/dev/null 2>&1
CODE_E=$?
set -e
[[ "$CODE_E" -eq 0 ]] || fail "loop guard: stop_hook_active=true must exit 0, got $CODE_E"

echo "PASS: stop-active-thread-reminder selftest (AC2 block, AC3 no-work/bypass exit0, AC-NEG1 refreshed-anchor not blocked, AC-NEG2 deterministic gate, loop guard)"
