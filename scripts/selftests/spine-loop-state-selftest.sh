#!/usr/bin/env bash
# Purpose: Verify the loop keeps turning on an empty round and still ends.
# Inputs: Hermetic loop-state fixtures under mktemp.
# Outputs: PASS when a zero-delta round continues and advances the round count,
#          the cap escalates to a human and stops self-turning, and moving N
#          moves the boundary with it.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$ROOT_DIR/scripts/spine-loop-state.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

next_action() {
  bash "$LOOP" next --state "$1"
}

rounds_recorded() {
  python3 -c '
import json, sys
print(len(json.load(open(sys.argv[1], encoding="utf-8"))["rounds"]))
' "$1"
}

assert_marker() {
  # Description: run a command expected to fail with a specific POLARIS marker.
  # Args: $1 = case name, $2 = expected marker, $3.. = command
  local name="$1" marker="$2"
  shift 2
  local out status
  out="$("$@" 2>&1)" && status=0 || status=$?
  [[ "$status" -ne 0 ]] || fail "$name unexpectedly succeeded"
  grep -Fq "$marker" <<<"$out" || fail "$name did not emit $marker; got: $out"
}

# --- Case 1: a zero-delta round continues, and the round still advances -----
S1="$WORK/zero-delta.json"
bash "$LOOP" init --state "$S1" >/dev/null
bash "$LOOP" record --state "$S1" --outcome zero_delta \
  --note "tried route A, hit X, concluding route B; code discarded" >/dev/null \
  || fail "a zero-delta round was rejected instead of continuing"
[[ "$(next_action "$S1")" == "continue" ]] \
  || fail "a zero-delta round did not leave the loop open, got $(next_action "$S1")"
[[ "$(rounds_recorded "$S1")" == "1" ]] \
  || fail "a zero-delta round did not advance the round count"

python3 - "$S1" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
round_ = data["rounds"][0]
assert round_["outcome"] == "zero_delta", round_["outcome"]
assert round_["produced_code_delta"] is False, "an empty round must be recorded as empty"
assert round_["note"], "the round's knowledge was dropped instead of recorded"
PY

# The empty round is recorded as empty — nothing is invented to make it look
# like a delivery, which is the incentive a fail-stop would create.
[[ "$(bash "$LOOP" show --state "$S1" | head -1)" == "status=open station=work stopped=no rounds=1 unconverged=1 max_rounds=3" ]] \
  || fail "show did not report the zero-delta round accurately: $(bash "$LOOP" show --state "$S1" | head -1)"

# --- Case 2: convergence closes the loop ------------------------------------
S2="$WORK/converges.json"
bash "$LOOP" init --state "$S2" >/dev/null
bash "$LOOP" record --state "$S2" --outcome zero_delta >/dev/null
bash "$LOOP" record --state "$S2" --outcome converged >/dev/null
[[ "$(next_action "$S2")" == "done" ]] \
  || fail "a converged loop did not close, got $(next_action "$S2")"
assert_marker "recording after convergence" POLARIS_SPINE_LOOP_CLOSED \
  bash "$LOOP" record --state "$S2" --outcome unconverged

# --- Case 3: the cap escalates and the loop stops turning itself ------------
S3="$WORK/cap.json"
bash "$LOOP" init --state "$S3" >/dev/null   # default cap N=3
bash "$LOOP" record --state "$S3" --outcome unconverged >/dev/null
[[ "$(next_action "$S3")" == "continue" ]] || fail "escalated after 1 of 3 rounds"
bash "$LOOP" record --state "$S3" --outcome zero_delta >/dev/null
[[ "$(next_action "$S3")" == "continue" ]] || fail "escalated after 2 of 3 rounds"
bash "$LOOP" record --state "$S3" --outcome unconverged >/dev/null
[[ "$(next_action "$S3")" == "stop:unconverged_cap" ]] \
  || fail "the loop did not escalate at its cap, got $(next_action "$S3")"

# "Stops self-turning" has to mean the next round is refused, not merely that a
# label changed.
assert_marker "recording past the cap" POLARIS_SPINE_LOOP_ESCALATED \
  bash "$LOOP" record --state "$S3" --outcome unconverged
[[ "$(rounds_recorded "$S3")" == "3" ]] \
  || fail "a refused round still mutated the state"

# --- Case 4: the reset is a human action ------------------------------------
assert_marker "unsigned reset" POLARIS_SPINE_LOOP_RESET_UNSIGNED \
  bash "$LOOP" reset --state "$S3"
bash "$LOOP" reset --state "$S3" --by tester >/dev/null
[[ "$(next_action "$S3")" == "continue" ]] || fail "reset did not reopen the loop"
python3 - "$S3" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["resets"][0]["by"] == "tester"
assert data["resets"][0]["rounds_cleared"] == 3
assert data["resets"][0]["previous_status"] == "escalated"
PY

# --- Case 5: N is adjustable and the boundary moves with it -----------------
S5a="$WORK/cap-2.json"
bash "$LOOP" init --state "$S5a" --max-rounds 2 >/dev/null
bash "$LOOP" record --state "$S5a" --outcome unconverged >/dev/null
[[ "$(next_action "$S5a")" == "continue" ]] || fail "N=2 escalated after 1 round"
bash "$LOOP" record --state "$S5a" --outcome unconverged >/dev/null
[[ "$(next_action "$S5a")" == "stop:unconverged_cap" ]] || fail "N=2 did not escalate at round 2"

S5b="$WORK/cap-5.json"
bash "$LOOP" init --state "$S5b" --max-rounds 5 >/dev/null
for _ in 1 2 3; do
  bash "$LOOP" record --state "$S5b" --outcome unconverged >/dev/null
done
[[ "$(next_action "$S5b")" == "continue" ]] \
  || fail "N=5 escalated at the default boundary instead of its own"
for _ in 4 5; do
  bash "$LOOP" record --state "$S5b" --outcome unconverged >/dev/null
done
[[ "$(next_action "$S5b")" == "stop:unconverged_cap" ]] || fail "N=5 did not escalate at round 5"

# Reset may also carry a new N — the cap lives in the adjustable zone.
bash "$LOOP" reset --state "$S5b" --by tester --max-rounds 1 >/dev/null
bash "$LOOP" record --state "$S5b" --outcome zero_delta >/dev/null
[[ "$(next_action "$S5b")" == "stop:unconverged_cap" ]] \
  || fail "a reset-time cap change did not move the boundary"

# --- Case 6: bad inputs fail closed ------------------------------------------
assert_marker "unknown outcome" POLARIS_SPINE_LOOP_BAD_OUTCOME \
  bash "$LOOP" record --state "$S1" --outcome maybe
assert_marker "missing state" POLARIS_SPINE_LOOP_STATE_MISSING \
  bash "$LOOP" next --state "$WORK/never-created.json"
assert_marker "non-positive cap" POLARIS_SPINE_LOOP_BAD_CAP \
  bash "$LOOP" init --state "$WORK/bad-cap.json" --max-rounds 0

# --- Case 7: the flow knows where it is without being told ------------------
# One word from a human starts this and nobody names the next entry again, so
# the station has to come off disk. Asking is the symptom, not the fix.
S7="$WORK/station.json"
bash "$LOOP" init --state "$S7" >/dev/null
where7="$(bash "$LOOP" where --state "$S7")"
grep -q '^station=work$' <<<"$where7" || fail "a fresh loop does not open at work: $where7"
grep -q '^next_station=judge$' <<<"$where7" || fail "where does not say where to go next: $where7"
bash "$LOOP" advance --state "$S7" --to judge >/dev/null
grep -q '^station=judge$' <<<"$(bash "$LOOP" where --state "$S7")" \
  || fail "advancing did not move the station"
bash "$LOOP" advance --state "$S7" --to delivered >/dev/null
grep -q 'next_station=none' <<<"$(bash "$LOOP" where --state "$S7")" \
  || fail "delivered is not terminal: $(bash "$LOOP" where --state "$S7")"
assert_marker "unknown station" POLARIS_SPINE_LOOP_BAD_STATION \
  bash "$LOOP" advance --state "$S7" --to somewhere-else

# --- Case 8: it stops in four named places, and nowhere else ----------------
# A flow that can stop anywhere needs someone watching it, which is the same as
# not running by itself. The enum is what lets a person walk away.
S8="$WORK/stops.json"
bash "$LOOP" init --state "$S8" >/dev/null
for kind in assertion_wrong surfaced_concern unconverged_cap unauthorized_action; do
  bash "$LOOP" stop --state "$S8" --kind "$kind" --note "$kind case" >/dev/null \
    || fail "$kind is one of the four and must be recordable"
  [[ "$(next_action "$S8")" == "stop:$kind" ]] \
    || fail "next did not name the stop: got $(next_action "$S8")"
  bash "$LOOP" advance --state "$S8" --to work --by tester >/dev/null
done
assert_marker "undeclared stop" POLARIS_SPINE_LOOP_UNDECLARED_STOP \
  bash "$LOOP" stop --state "$S8" --kind because_i_felt_like_it

# A recorded stop is not decorative: walking past one is a human's move.
bash "$LOOP" stop --state "$S8" --kind surfaced_concern --note "pulling in a package" >/dev/null
assert_marker "unsigned resume" POLARIS_SPINE_LOOP_STOP_UNCLEARED \
  bash "$LOOP" advance --state "$S8" --to judge
where8="$(bash "$LOOP" where --state "$S8")"
grep -q '^stopped=surfaced_concern$' <<<"$where8" || fail "where hides the stop: $where8"
grep -q 'pulling in a package' <<<"$where8" || fail "where drops the reason: $where8"

# --- Case 9: a state written before stations says so ------------------------
# Reporting a default as though it were known would be an invention, and this
# state exists precisely so nobody has to guess.
S9="$WORK/legacy.json"
python3 - "$S9" <<'PY'
import json, sys
json.dump({"schema_version": 1, "producer": "spine-loop-state.sh", "max_rounds": 3,
           "rounds": [], "status": "open"}, open(sys.argv[1], "w"))
PY
grep -q 'predates stations' <<<"$(bash "$LOOP" where --state "$S9")" \
  || fail "a pre-stations state was reported as though its station were known"

echo "PASS: spine-loop-state-selftest.sh"
