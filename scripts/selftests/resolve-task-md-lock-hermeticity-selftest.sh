#!/usr/bin/env bash
# Purpose: DP-294 T6 / AC8 — assert resolve-task-md.sh's embedded selftest is
#          hermetic w.r.t. the session work-order lock. The embedded selftest
#          exercises --write-lock; its lock must land inside the selftest tmpdir
#          (cleaned by the tmpdir trap), never under the live /tmp lock path.
#          This selftest snapshots /tmp/polaris-work-order-lock-*.json before and
#          after running the embedded selftest and fails if any new lock leaks.
# Inputs:  none (runs scripts/resolve-task-md.sh --self-test as a subprocess).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTM="$ROOT/scripts/resolve-task-md.sh"
[[ -x "$RTM" ]] || { echo "FAIL: missing/not executable: $RTM" >&2; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

LOCK_GLOB="/tmp/polaris-work-order-lock-*.json"

# Snapshot of live /tmp lock files before the embedded selftest run.
snapshot_locks() {
  # shellcheck disable=SC2086
  ls -1 $LOCK_GLOB 2>/dev/null | sort || true
}

BEFORE="$(snapshot_locks)"

# Run the embedded selftest exactly as the framework does.
if RESOLVE_TASK_MD_SELFTEST=1 bash "$RTM" --self-test >/tmp/rtm-hermetic-st.out 2>&1; then
  ok
else
  bad "embedded resolve-task-md selftest should still PASS (see /tmp/rtm-hermetic-st.out)"
fi

AFTER="$(snapshot_locks)"

# No new /tmp lock file may appear: the embedded selftest must keep its lock
# inside its own tmpdir and clean it via trap.
NEW="$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed '/^$/d')"
if [[ -z "$NEW" ]]; then
  ok
else
  bad "embedded selftest leaked live work-order lock(s) to /tmp: $NEW"
  # Clean up the leak so repeated runs stay deterministic.
  while IFS= read -r leaked; do [[ -n "$leaked" ]] && rm -f "$leaked"; done <<<"$NEW"
fi

echo "[resolve-task-md-lock-hermeticity-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
