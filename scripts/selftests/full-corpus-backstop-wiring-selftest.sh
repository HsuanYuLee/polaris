#!/usr/bin/env bash
# Purpose: DP-360 T-backstop / AC-NF1 selftest. Asserts the three-layer gate model's
#          full-corpus backstop is wired correctly and stays OFF the commit/push hot
#          path:
#            (a) the W14 full-corpus run (run-aggregate-selftests.sh) is part of the
#                check-framework-pr-gate.sh aggregate AND that aggregate is wired into
#                BOTH the DP-iteration local entrypoint (--list-stages declares it) and
#                the release lane (framework-release-pr-lane.sh);
#            (b) the full corpus is NOT referenced by the push hot path
#                (pre-push-quality-gate.sh) — NF1 keeps it backstop-only;
#            (c) selftest-slow-inventory.sh produces a slow inventory list from a tier
#                manifest cache (REUSE of T1 manifest; never re-measures);
#            (d) the affected push-time baseline is recorded by slow-inventory.
#          Hermetic: never runs the slow full corpus — wiring is checked by static read
#          of real source + the gate's --list-stages introspection + a synthetic tier
#          manifest fixture for the slow-inventory path. Fail-closed on any miss.
# Inputs:  env DEBUG=1 for verbose. Run: bash scripts/selftests/full-corpus-backstop-wiring-selftest.sh
# Outputs: stdout assertions + summary; exit 0 if all pass, exit 1 on any assertion fail.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$ROOT_DIR/check-framework-pr-gate.sh"
AGGREGATE="$ROOT_DIR/run-aggregate-selftests.sh"
RELEASE_LANE="$ROOT_DIR/framework-release-pr-lane.sh"
RELEASE_BACKSTOPS="$ROOT_DIR/lib/release-gate-backstops.sh"
SLOW_INVENTORY="$ROOT_DIR/selftest-slow-inventory.sh"
PRE_PUSH_HOOK="$(cd "$ROOT_DIR/.." && pwd)/.claude/hooks/pre-push-quality-gate.sh"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — needle=%s\n' "$label" "$needle"
  fi
  return 0
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — unexpected needle=%s\n' "$label" "$needle"
  else
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s\n' "$label"
  fi
  return 0
}

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); [[ "$DEBUG" == "1" ]] && printf '  [ok] %s (got=%s)\n' "$label" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s — want=%s got=%s\n' "$label" "$want" "$got"
  fi
  return 0
}

# --- Preconditions: the three real source files exist ------------------------
for f in "$GATE" "$AGGREGATE" "$RELEASE_LANE" "$RELEASE_BACKSTOPS" "$SLOW_INVENTORY"; do
  if [[ ! -f "$f" ]]; then
    printf '  [FAIL] precondition: missing source file %s\n' "$f"
    FAIL=$((FAIL + 1))
  fi
done
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: full-corpus-backstop-wiring selftest (%d precondition failures)\n' "$FAIL"
  exit 1
fi

# --- (a) full corpus is part of the aggregate + DP-iteration + release wiring ----
# The gate's --list-stages introspection declares the W14 full-corpus backstop without
# running any gate. This is the DP-iteration local entrypoint declaration.
stages="$(bash "$GATE" --list-stages 2>/dev/null)"
list_rc=$?
assert_eq "$list_rc" "0" "(a) --list-stages exits 0 (no gate run)"
assert_contains "$stages" "W14 aggregate selftest run (full-corpus backstop)" \
  "(a) --list-stages declares W14 full-corpus backstop stage"

gate_src="$(cat "$GATE")"
# The aggregate actually invokes run-aggregate-selftests.sh as W14.
assert_contains "$gate_src" "run-aggregate-selftests.sh" \
  "(a) aggregate gate invokes run-aggregate-selftests.sh (W14 full corpus)"
assert_contains "$gate_src" "W14 aggregate selftest run" \
  "(a) aggregate gate runs W14 stage"
# The gate header declares it is the DP-iteration + release full-corpus backstop entry.
assert_contains "$gate_src" "DP-iteration" \
  "(a) gate header declares DP-iteration local entrypoint"

# The release lane wires the same full corpus (run-aggregate-selftests.sh) as a gate.
release_src="$(cat "$RELEASE_LANE")"
assert_contains "$release_src" "run-aggregate-selftests.sh" \
  "(a) release lane wires the full-corpus aggregate runner"
release_default="$(bash -c '
  source "$1"
  FULL_BACKSTOP=0
  info() { :; }
  run_aggregate_selftests_release_gate() { echo MANDATORY-PRE-PROMOTION-FULL; }
  run_upstream_backstop_gates_if_requested
' _ "$RELEASE_BACKSTOPS")"
assert_contains "$release_default" "MANDATORY-PRE-PROMOTION-FULL" \
  "(a) default release path executes the pre-promotion full backstop without an opt-in flag"

# --- (b) NF1: full corpus is NOT on the push hot path ------------------------
# The pre-push gate (affected-scoped per T3) must not reference the full-corpus aggregate
# or this aggregate gate. If the file does not exist yet (T3 not landed on this branch),
# absence is itself proof the full corpus is not wired there.
if [[ -f "$PRE_PUSH_HOOK" ]]; then
  prepush_src="$(cat "$PRE_PUSH_HOOK")"
  assert_not_contains "$prepush_src" "run-aggregate-selftests.sh" \
    "(b) NF1: pre-push hot path does NOT run the full corpus"
  assert_not_contains "$prepush_src" "check-framework-pr-gate.sh" \
    "(b) NF1: pre-push hot path does NOT invoke the full-corpus backstop gate"
  assert_contains "$prepush_src" "POLARIS_AFFECTED_FULL_CORPUS" \
    "(b) NEG2: pre-push recognizes the affected selector full-corpus sentinel"
  assert_contains "$prepush_src" "PR/pre-promotion backstop" \
    "(b) NEG2: shared/self-reference escalation is routed to a blocking backstop lane"
else
  # No push hot-path file → full corpus is trivially absent from it.
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf '  [ok] (b) NF1: no pre-push hook present; full corpus trivially off hot path\n'
fi
# The gate itself documents the hot-path exclusion (NF1 contract pointer in prose).
assert_contains "$gate_src" "MUST NOT be wired onto the commit/push hot path" \
  "(b) NF1: gate header documents commit/push hot-path exclusion"

# --- (c) slow-inventory produces a list from a tier manifest cache -----------
FIX="$(mktemp -d -t slow-inventory-fix-XXXXXX)"
trap 'rm -rf "$FIX" "${STATE_FIX:-}"' EXIT
cat >"$FIX/manifest.json" <<'JSON'
{
  "schema_version": 1,
  "measured_speed_threshold_ms": 5000,
  "count": 3,
  "selftests": [
    {"path": "scripts/selftests/fast-x-selftest.sh", "wall_clock_ms": 250, "scope": "narrow", "last_exit_code": 0},
    {"path": "scripts/selftests/slow-x-selftest.sh", "wall_clock_ms": 60000, "scope": "shared", "last_exit_code": 0},
    {"path": "scripts/selftests/midslow-x-selftest.sh", "wall_clock_ms": 8000, "scope": "shared", "last_exit_code": 0}
  ]
}
JSON

inv_out="$(bash "$SLOW_INVENTORY" --manifest "$FIX/manifest.json" 2>/dev/null)"
inv_rc=$?
assert_eq "$inv_rc" "0" "(c) slow-inventory exits 0 with a valid manifest"
assert_contains "$inv_out" "SLOW_SELFTEST_INVENTORY:" "(c) slow-inventory prints inventory header"
assert_contains "$inv_out" "slow-x-selftest.sh" "(c) slow-inventory lists the slow selftest"
assert_contains "$inv_out" "midslow-x-selftest.sh" "(c) slow-inventory lists the mid-slow selftest"
assert_not_contains "$inv_out" "fast-x-selftest.sh" "(c) slow-inventory excludes the fast selftest"

# JSON shape is machine-consumable (slow_count present).
inv_json="$(bash "$SLOW_INVENTORY" --manifest "$FIX/manifest.json" --format json 2>/dev/null)"
assert_contains "$inv_json" '"slow_count": 2' "(c) slow-inventory JSON reports slow_count=2"

# Fail-closed: missing manifest must exit 2 (never silent-pass).
set +e
bash "$SLOW_INVENTORY" --manifest "$FIX/does-not-exist.json" >/dev/null 2>&1
miss_rc=$?
set -e 2>/dev/null || true
assert_eq "$miss_rc" "2" "(c) slow-inventory fail-closed (exit 2) on missing manifest"

# --- (d) affected push-time baseline is recorded -----------------------------
assert_contains "$inv_out" "AFFECTED_PUSH_TIME_BASELINE:" \
  "(d) slow-inventory records the affected push-time baseline block"
assert_contains "$inv_out" "affected_push_time_budget_class=tens-of-seconds" \
  "(d) baseline records the affected push-time budget class"
assert_contains "$inv_out" "hot_path_excluded=pre-commit,pre-push" \
  "(d) baseline records the full corpus is excluded from the hot path"
assert_contains "$inv_out" "backstop_lanes=dp-iteration,release" \
  "(d) baseline records the backstop lanes (dp-iteration, release)"

# baseline-only mode works without any manifest (durable artifact, NF1).
base_only="$(bash "$SLOW_INVENTORY" --baseline-only 2>/dev/null)"
base_rc=$?
assert_eq "$base_rc" "0" "(d) slow-inventory --baseline-only exits 0 without a manifest"
assert_contains "$base_only" "AFFECTED_PUSH_TIME_BASELINE:" \
  "(d) --baseline-only emits the baseline block"

# --- (e) a successful full run refreshes durable 48h state, red does not ----
STATE_FIX="$(mktemp -d -t full-state-fix-XXXXXX)"
mkdir -p "$STATE_FIX/scripts/selftests"
cp "$AGGREGATE" "$STATE_FIX/scripts/run-aggregate-selftests.sh"
cat >"$STATE_FIX/scripts/selftests/green-selftest.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$STATE_FIX/scripts/selftests/green-selftest.sh"
git -C "$STATE_FIX" init -q
git -C "$STATE_FIX" add .
git -C "$STATE_FIX" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm green
state_file="$STATE_FIX/last-full-corpus-run.json"
POLARIS_SELFTEST_STATE_FILE="$state_file" \
  bash "$STATE_FIX/scripts/run-aggregate-selftests.sh" --root "$STATE_FIX" --base-ref HEAD >/dev/null 2>&1
state_rc=$?
assert_eq "$state_rc" "0" "(e) green full corpus exits 0"
if [[ -f "$state_file" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1)); printf '  [FAIL] (e) green full corpus did not write staleness state\n'
fi
state_head="$(python3 -c "import json; print(json.load(open('$state_file'))['head_sha'])" 2>/dev/null)"
assert_eq "$state_head" "$(git -C "$STATE_FIX" rev-parse HEAD)" \
  "(e) staleness state is bound to the successful full-run head"
state_ts="$(python3 -c "import json; print(json.load(open('$state_file'))['last_full_corpus_run_ts'])" 2>/dev/null)"
if [[ "$state_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1)); printf '  [FAIL] (e) staleness state timestamp malformed: %s\n' "$state_ts"
fi
state_before="$(cksum "$state_file")"
cat >"$STATE_FIX/scripts/selftests/head-red-selftest.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$STATE_FIX/scripts/selftests/head-red-selftest.sh"
git -C "$STATE_FIX" add .
git -C "$STATE_FIX" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm head-red
set +e
POLARIS_SELFTEST_STATE_FILE="$state_file" \
  bash "$STATE_FIX/scripts/run-aggregate-selftests.sh" --root "$STATE_FIX" --base-ref HEAD^ >/dev/null 2>&1
red_state_rc=$?
set -e 2>/dev/null || true
assert_eq "$red_state_rc" "1" "(e) head-only red full corpus remains blocking"
assert_eq "$(cksum "$state_file")" "$state_before" \
  "(e) red full corpus cannot refresh last-green staleness state"

# --- Summary -----------------------------------------------------------------
printf '\nfull-corpus-backstop-wiring selftest: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: full-corpus-backstop-wiring selftest\n'
  exit 1
fi
printf 'PASS: full-corpus-backstop-wiring selftest\n'
exit 0
