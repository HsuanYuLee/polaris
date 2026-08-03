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

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
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
[[ "$(bash "$LOOP" show --state "$S1" | head -1)" == "status=open station=engineering stopped=no rounds=1 unconverged=1 max_rounds=3" ]] \
  || fail "show did not report the zero-delta round accurately: $(bash "$LOOP" show --state "$S1" | head -1)"

# --- Case 2: convergence closes the loop ------------------------------------
S2="$WORK/converges.json"
bash "$LOOP" init --state "$S2" >/dev/null
bash "$LOOP" record --state "$S2" --outcome zero_delta >/dev/null
bash "$LOOP" record --state "$S2" --outcome converged >/dev/null
[[ "$(next_action "$S2")" == "done" ]] \
  || fail "a converged loop did not close, got $(next_action "$S2")"
# A converged loop is a success signal, not a closed one. A source that ships one slice
# and keeps going must be able to record the next round, and judge's documented "回 work"
# after a non-PASS must work. Both were blocked while converged refused to record.
bash "$LOOP" record --state "$S2" --outcome unconverged --note "next slice" >/dev/null \
  || fail "a converged loop refused the next round; that gate pointed at a success signal"
[[ "$(next_action "$S2")" == "continue" ]] \
  || fail "loop did not reopen after recording past convergence, got $(next_action "$S2")"
python3 - "$S2" <<'PY' || fail "recording past convergence lost earlier rounds"
import json, sys
rounds = json.load(open(sys.argv[1], encoding="utf-8"))["rounds"]
# The point of not closing is that history survives; reset is what clears it.
sys.exit(0 if len(rounds) == 3 and rounds[1]["outcome"] == "converged" else 1)
PY

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
# The refusal is the message a human actually reads when the loop halts, so it
# has to say what they can do — not name a script they have never seen.
capmsg="$(bash "$LOOP" record --state "$S3" --outcome unconverged 2>&1 || true)"
grep -q '你可以做的' <<<"$capmsg" \
  || fail "the cap refusal does not say what the human can do: $capmsg"
[[ "$(rounds_recorded "$S3")" == "3" ]] \
  || fail "a refused round still mutated the state"

# --- Case 4: the reset is a human action, signed in their own words ---------
# The signature used to be "somebody typed this line", which an agent can do as
# easily as a person. What cannot be manufactured invisibly is a quote:
# --authorization stores what the human actually said, in git, where it can be
# read back against the conversation.
assert_marker "unsigned reset" POLARIS_SPINE_LOOP_RESET_UNSIGNED \
  bash "$LOOP" reset --state "$S3"
assert_marker "reset with a name but no words" POLARIS_SPINE_LOOP_UNQUOTED_AUTHORIZATION \
  bash "$LOOP" reset --state "$S3" --by tester
assert_marker "reset with blank words" POLARIS_SPINE_LOOP_UNQUOTED_AUTHORIZATION \
  bash "$LOOP" reset --state "$S3" --by tester --authorization "   "
bash "$LOOP" reset --state "$S3" --by tester --authorization "繼續，我授權" >/dev/null
[[ "$(next_action "$S3")" == "continue" ]] || fail "reset did not reopen the loop"

# The rounds survive the reset. E-P4 (pick it up after an interruption) is carried
# by that history, and the first version deleted it — so the only way past the cap
# was to destroy what the resume view reads.
[[ "$(rounds_recorded "$S3")" == "3" ]] \
  || fail "reset threw away the history: $(rounds_recorded "$S3") rounds left"
python3 - "$S3" <<'PYJSON'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["resets"][0]["by"] == "tester"
assert data["resets"][0]["authorization"] == "繼續，我授權"
assert data["resets"][0]["rounds_carried"] == 3
assert data["resets"][0]["previous_status"] == "escalated"
assert data["lineage"] == 2
PYJSON

# A new lineage releases the cap without erasing anything: three more unconverged
# rounds are needed to trip it again, and the old three are still on file.
bash "$LOOP" record --state "$S3" --outcome unconverged >/dev/null
bash "$LOOP" record --state "$S3" --outcome unconverged >/dev/null
[[ "$(next_action "$S3")" == "continue" ]] \
  || fail "the cap counted rounds from a lineage a human already released"
bash "$LOOP" record --state "$S3" --outcome unconverged >/dev/null
[[ "$(next_action "$S3")" == "stop:unconverged_cap" ]] \
  || fail "the cap stopped applying to the new lineage"
[[ "$(rounds_recorded "$S3")" == "6" ]] \
  || fail "the new lineage did not accumulate on top of the old history"

# The stop has to tell the person what they can do, in words they can say back.
# A resume line that is a bash invocation is a resume path only for whoever wrote
# this file — which is the same as no resume path.
where4="$(bash "$LOOP" where --state "$S3")"
grep -q '你可以做的' <<<"$where4" \
  || fail "the stop did not say what the human can do: $where4"
grep -q '等價指令' <<<"$where4" \
  || fail "the command should still be there, as a footnote: $where4"

# show prints who released it and on the strength of what. A signature nobody
# ever reads is decorative.
grep -q '繼續，我授權' <<<"$(bash "$LOOP" show --state "$S3")" \
  || fail "show does not surface the authorization"

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
bash "$LOOP" reset --state "$S5b" --by tester --authorization "換上限，我同意" --max-rounds 1 >/dev/null
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
grep -q '^station=engineering$' <<<"$where7" || fail "a fresh loop does not open at work: $where7"
grep -q '^next_station=verify-ac$' <<<"$where7" || fail "where does not say where to go next: $where7"
bash "$LOOP" advance --state "$S7" --to verify-ac >/dev/null
grep -q '^station=verify-ac$' <<<"$(bash "$LOOP" where --state "$S7")" \
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
  assert_marker "clearing a stop with a name but no words" POLARIS_SPINE_LOOP_UNQUOTED_AUTHORIZATION \
    bash "$LOOP" advance --state "$S8" --to engineering --by tester
  bash "$LOOP" advance --state "$S8" --to engineering --by tester --authorization "好，繼續" >/dev/null
done
# Every clearance is on file with the words that bought it.
python3 - "$S8" <<'PYJSON'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["clearances"]) == 4, data.get("clearances")
assert all(c["authorization"] == "好，繼續" for c in data["clearances"])
PYJSON
assert_marker "undeclared stop" POLARIS_SPINE_LOOP_UNDECLARED_STOP \
  bash "$LOOP" stop --state "$S8" --kind because_i_felt_like_it

# --- Case 9: a failed verdict can walk back ---------------------------------
# G-P4. verify-ac's own recovery path says "judged not PASS → back to
# engineering", and engineering's says "recording a round is how you continue".
# A converged loop that refused the next round broke that path in the middle,
# and the only escape was the reset that deleted the history.
S9="$WORK/verdict.json"
bash "$LOOP" init --state "$S9" >/dev/null
bash "$LOOP" record --state "$S9" --outcome converged >/dev/null
bash "$LOOP" advance --state "$S9" --to verify-ac --by tester >/dev/null
bash "$LOOP" advance --state "$S9" --to engineering --by tester >/dev/null
bash "$LOOP" record --state "$S9" --outcome unconverged --note "judged not PASS" >/dev/null \
  || fail "a loop that converged once cannot take the next round after a failed verdict"
[[ "$(rounds_recorded "$S9")" == "2" ]] \
  || fail "the round after the failed verdict was not recorded"
[[ "$(next_action "$S9")" == "continue" ]] \
  || fail "the loop did not reopen after a failed verdict: $(next_action "$S9")"
echo "  ok  a failed verdict walks back into engineering without a reset"

# A recorded stop is not decorative: walking past one is a human's move.
bash "$LOOP" stop --state "$S8" --kind surfaced_concern --note "pulling in a package" >/dev/null
assert_marker "unsigned resume" POLARIS_SPINE_LOOP_STOP_UNCLEARED \
  bash "$LOOP" advance --state "$S8" --to verify-ac
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

# --- Case 10: 已歸檔的單再記一輪，不可以把整棵樹搬歪 ------------------------
# record 完會叫歸檔器，而歸檔器要知道 issues 根在哪。第一版從 state 往上數固定三層——
# 對活躍區的單剛好，對 archive/ 裡的單就少數一層，算出來的「根」其實是某個命名空間。
# 於是 archive 看起來像一個命名空間，它底下每一張單都被搬進 archive/archive/。
# 2026-08-03 真的發生了，103 個檔案，而且呼叫端接了 `|| true`，全程沒有一個字。
S10_ROOT="$WORK/issues10"
mkdir -p "$S10_ROOT/ns/archive/T/.spine" "$S10_ROOT/ns/archive/OTHER/.spine"
git -C "$S10_ROOT" init -q
git -C "$S10_ROOT" config user.email t@t
git -C "$S10_ROOT" config user.name t
bash "$LOOP" init --state "$S10_ROOT/ns/archive/T/.spine/loop-state.json" >/dev/null
bash "$LOOP" record --state "$S10_ROOT/ns/archive/T/.spine/loop-state.json" --outcome converged >/dev/null
printf '{"status":"converged","rounds":[]}\n' > "$S10_ROOT/ns/archive/OTHER/.spine/loop-state.json"
git -C "$S10_ROOT" add -A
git -C "$S10_ROOT" commit -qm seed
# T 沒收斂了，它該回到活躍區；OTHER 收斂著，該原地不動。
bash "$LOOP" record --state "$S10_ROOT/ns/archive/T/.spine/loop-state.json" --outcome unconverged >/dev/null
[[ ! -d "$S10_ROOT/ns/archive/archive" ]] \
  || fail "歸檔器把命名空間當成了整棵樹：$S10_ROOT/ns/archive/archive 被建出來"
[[ -d "$S10_ROOT/ns/T" ]] \
  || fail "沒收斂的單沒有從 archive/ 回到活躍區"
[[ -d "$S10_ROOT/ns/archive/OTHER" ]] \
  || fail "收斂著的單被動到了"

echo "PASS: spine-loop-state-selftest.sh"
