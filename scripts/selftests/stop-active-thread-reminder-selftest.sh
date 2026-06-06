#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/stop-active-thread-reminder.sh (DP-290 T3).
#          Asserts the Stop advisory hook exits 0 (never blocks the session stop) and
#          prints the one-line reminder to refresh the active-thread anchor. Also asserts
#          settings.json registers the Stop hook (single canonical advisory source).
# Inputs:  None.
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/stop-active-thread-reminder.sh"
SETTINGS="$ROOT/.claude/settings.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$HOOK" ] || fail "Stop hook script not found: $HOOK"

# ---- Stop hook exits 0 (does not block) + prints advisory ----
OUT="$(printf '{"hook_event_name":"Stop"}' | bash "$HOOK" 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || fail "Stop hook did not exit 0 (rc=$rc) — must not block"
printf '%s' "$OUT" | grep -q 'stop-active-thread-reminder' \
  || fail "Stop hook did not print the advisory line"
printf '%s' "$OUT" | grep -q 'update-active-thread.sh' \
  || fail "Stop advisory does not point at the single canonical writer"

# Hook must NOT emit a block decision (no '"decision":"block"').
if printf '%s' "$OUT" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  fail "Stop hook emitted a block decision — advisory must never block"
fi

# ---- settings.json registers the Stop advisory hook ----
[ -f "$SETTINGS" ] || fail "settings.json not found: $SETTINGS"
if ! command -v jq >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:jq" >&2
  fail "jq required to assert settings.json Stop registration (run 'mise install')"
fi
CMD="$(jq -r '.hooks.Stop[]?.hooks[]?.command' "$SETTINGS" \
  | grep 'stop-active-thread-reminder.sh' | head -n1)"
[ -n "$CMD" ] || fail "settings.json hooks.Stop missing stop-active-thread-reminder.sh registration"

echo "PASS: stop-active-thread-reminder selftest (exit 0 advisory + settings registration)"
