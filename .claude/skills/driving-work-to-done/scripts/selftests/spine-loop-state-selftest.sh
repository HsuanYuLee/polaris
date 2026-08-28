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
bash "$LOOP" init --state "$S1" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
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
bash "$LOOP" init --state "$S2" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
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
bash "$LOOP" init --state "$S3" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null   # default cap N=3
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
bash "$LOOP" init --state "$S5a" --pack none --why '量測用的暫存 fixture，不是一件真的工作' --max-rounds 2 >/dev/null
bash "$LOOP" record --state "$S5a" --outcome unconverged >/dev/null
[[ "$(next_action "$S5a")" == "continue" ]] || fail "N=2 escalated after 1 round"
bash "$LOOP" record --state "$S5a" --outcome unconverged >/dev/null
[[ "$(next_action "$S5a")" == "stop:unconverged_cap" ]] || fail "N=2 did not escalate at round 2"

S5b="$WORK/cap-5.json"
bash "$LOOP" init --state "$S5b" --pack none --why '量測用的暫存 fixture，不是一件真的工作' --max-rounds 5 >/dev/null
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
  bash "$LOOP" init --state "$WORK/bad-cap.json" --pack none --why '量測用的暫存 fixture，不是一件真的工作' --max-rounds 0

# --- Case 7: the flow knows where it is without being told ------------------
# One word from a human starts this and nobody names the next entry again, so
# the station has to come off disk. Asking is the symptom, not the fix.
S7="$WORK/station.json"
bash "$LOOP" init --state "$S7" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
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
bash "$LOOP" init --state "$S8" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
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
bash "$LOOP" init --state "$S9" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
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

# --- Case 10: 住在格子裡的單再記一輪，不可以把整棵樹搬歪 --------------------
# record 完會叫重算，而重算要知道 issues 根在哪。第一版從 state 往上數固定三層——
# 對活躍區的單剛好，對格子裡的單就少數一層，算出來的「根」其實是某個命名空間。
# 於是那個格子看起來像一個命名空間，它底下每一張單都被搬進 {格子}/{格子}/。
# 2026-08-03 真的發生了，103 個檔案，而且呼叫端接了 `|| true`，全程沒有一個字。
#
# 六格之後這個案例更該在：單本來就住在格子裡，往上數幾層永遠是錯的答案。
S10_ROOT="$WORK/issues10"
mkdir -p "$S10_ROOT/ns/backlog/T/.spine" "$S10_ROOT/ns/done/OTHER/.spine"
git -C "$S10_ROOT" init -q
git -C "$S10_ROOT" config user.email t@t
git -C "$S10_ROOT" config user.name t
bash "$LOOP" init --state "$S10_ROOT/ns/backlog/T/.spine/loop-state.json" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
printf '{"status":"converged","rounds":[]}\n' > "$S10_ROOT/ns/done/OTHER/.spine/loop-state.json"
git -C "$S10_ROOT" add -A
git -C "$S10_ROOT" commit -qm seed
# T 收斂了：它身上沒有釋出紀錄，所以該落 done/，不是 released/。
bash "$LOOP" record --state "$S10_ROOT/ns/backlog/T/.spine/loop-state.json" --outcome converged >/dev/null
[[ -d "$S10_ROOT/ns/done/T" ]] \
  || fail "收斂的單沒有落到 done/：$(find "$S10_ROOT/ns" -maxdepth 2 -type d | tr '\n' ' ')"
[[ ! -d "$S10_ROOT/ns/backlog/backlog" && ! -d "$S10_ROOT/ns/done/done" ]] \
  || fail "重算把某一個格子當成了整棵樹"
# 又沒收斂了：它該離開 done/，回到還在做的那一格。OTHER 收斂著，原地不動。
bash "$LOOP" record --state "$S10_ROOT/ns/done/T/.spine/loop-state.json" --outcome unconverged >/dev/null
[[ -d "$S10_ROOT/ns/in-progress/T" ]] \
  || fail "沒收斂的單沒有離開 done/"
[[ -d "$S10_ROOT/ns/done/OTHER" ]] \
  || fail "收斂著的單被動到了"

# 換站別也是換狀態，位置一樣要跟著換。只掛在 record 上的話，一張被推回 refinement 的單
# 會留在 in-progress/——而那正是「位置是狀態的投影」要消除的漂移。
#
# 這裡刻意不用「推到 verify-ac」當例子：T 是 `--pack none` 開的，不會動到 code 的工作
# 沒有 review 這一格，所以它走到 verify-ac 仍然落 in-progress——那是對的行為，拿它當
# 斷言會量到一個永遠不動的東西。
bash "$LOOP" advance --state "$S10_ROOT/ns/in-progress/T/.spine/loop-state.json" --to refinement >/dev/null
[[ -d "$S10_ROOT/ns/backlog/T" ]] \
  || fail "advance 把單推回 refinement，位置卻沒跟著換：$(find "$S10_ROOT/ns" -maxdepth 2 -type d -name T)"
echo "  ok  換站別之後位置跟著換"


# 單會被重算搬走，所以 fixture 裡的路徑不能寫死——照單名去問它現在住哪。
state_of() { find "$1" -path "*/$2/.spine/loop-state.json" | head -1; }

# Case 11：跨單。「手上有六張單，接下來做哪一張」原本只有人回答得出來，而每一次問人
# 就是連續退化成單步的那一刻。
S11="$WORK/issues11"
mkdir -p "$S11/nsA/EARLY/.spine" "$S11/nsB/LATE/.spine" "$S11/nsB/STOPPED/.spine" "$S11/nsA/DONE/.spine"
git -C "$S11" init -q
git -C "$S11" config user.email t@t
git -C "$S11" config user.name t
for s in nsA/EARLY nsB/LATE nsB/STOPPED nsA/DONE; do
  bash "$LOOP" init --state "$S11/$s/.spine/loop-state.json" --pack none --why '量測用的暫存 fixture，不是一件真的工作' >/dev/null
done
git -C "$S11" add -A && git -C "$S11" commit -qm seed

# EARLY 先動、LATE 後動：同一站時該推薦最近動過的那一張。
# 時間直接寫死，不用 sleep：兩次 record 落在同一秒的話這個 case 什麼都沒驗到，
# 而它剛好就是這樣第一次跑出假訊號的。
bash "$LOOP" record --state "$(state_of "$S11" EARLY)" --outcome unconverged >/dev/null
bash "$LOOP" record --state "$(state_of "$S11" LATE)" --outcome unconverged >/dev/null
python3 - "$S11" <<'PYSTAMP'
import glob, json, sys
for name, stamp in (("nsA/EARLY", "2020-01-01T00:00:00Z"), ("nsB/LATE", "2030-01-01T00:00:00Z")):
    path = glob.glob(f"{sys.argv[1]}/**/{name.split('/')[-1]}/.spine/loop-state.json",
                     recursive=True)[0]
    data = json.load(open(path, encoding="utf-8"))
    data["rounds"][-1]["recorded_at"] = stamp
    json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PYSTAMP
out="$(bash "$LOOP" next --across-issues "$S11")"
printf '%s' "$out" | grep -qE 'next:nsB/[a-z-]+/LATE' \
  || fail "同一站時沒有推薦最近動過的那一張：$out"
echo "  ok  跨單推薦最近動過的那一張"

# 往後站的先做：在製品不該堆高。名字排序會選 EARLY，站別排序該選 LATE。
bash "$LOOP" advance --state "$(state_of "$S11" EARLY)" --to verify-ac >/dev/null
out="$(bash "$LOOP" next --across-issues "$S11")"
printf '%s' "$out" | grep -qE 'next:nsA/[a-z-]+/EARLY' \
  || fail "站別沒有壓過最近動過的：$out"
echo "  ok  最靠近交付的先做"

# 停住的要逐張列名，不能混進「可以做」裡，也不能安靜消失。
bash "$LOOP" stop --state "$(state_of "$S11" STOPPED)" --kind surfaced_concern --note x >/dev/null
out="$(bash "$LOOP" next --across-issues "$S11")"
printf '%s' "$out" | grep -qE 'blocked:nsB/[a-z-]+/STOPPED .*stop=surfaced_concern' \
  || fail "停住的單沒有被列出來：$out"
printf '%s' "$out" | grep -qE 'next:nsB/[a-z-]+/STOPPED' \
  && fail "停住的單被推薦了：$out"
echo "  ok  停住的逐張列名，不會被推薦"

# 收斂完的算成數字，不列成清單——但那個數字必須在。收斂那一刻重算會把它搬進
# done/，所以這同時證明跨單掃描看得到格子底下那一層，不是只掃命名空間正下方。
bash "$LOOP" record --state "$(state_of "$S11" DONE)" --outcome converged >/dev/null
[[ -d "$S11/nsA/done/DONE" ]] || fail "收斂之後沒有落到 done/"
out="$(bash "$LOOP" next --across-issues "$S11")"
printf '%s' "$out" | grep -qE 'counted: .*settled=[1-9]' \
  || fail "收斂完的沒有被算進 settled：$out"
echo "  ok  收斂完的算成數字而不是安靜消失"

# 全部停住時要說 none，不可以硬挑一張停住的出來。
bash "$LOOP" stop --state "$(state_of "$S11" EARLY)" --kind assertion_wrong --note x >/dev/null
bash "$LOOP" stop --state "$(state_of "$S11" LATE)" --kind assertion_wrong --note x >/dev/null
out="$(bash "$LOOP" next --across-issues "$S11")"
printf '%s' "$out" | grep -q 'next:none' \
  || fail "全部停住時沒有回 none：$out"
echo "  ok  全部停住時回 none"


# Case 12：開工條件。核心不認得任何一個領域的條件，它只會去讀 pack 的宣告然後跑它——
# 所以這幾個 case 用一個假的 pack，整段不出現任何軟體工程的東西。
S12="$WORK/skills12"
mkdir -p "$S12/fakepack/scripts" "$S12/driving-work-to-done/scripts"
cp "$LOOP" "$S12/driving-work-to-done/scripts/spine-loop-state.sh"
LOOP12="$S12/driving-work-to-done/scripts/spine-loop-state.sh"
cat > "$S12/fakepack/scripts/gate.sh" <<'EOF'
#!/usr/bin/env bash
[[ -f "$WORK12/allowed" ]] || { echo "假條件不成立：$WORK12/allowed 不在" >&2; exit 2; }
echo "FAKE-PRECONDITION-OK"
EOF
chmod +x "$S12/fakepack/scripts/gate.sh"
printf '%s\n' '---' 'name: fakepack' '---' \
  "<!-- FAKE-PRECONDITION: bash $S12/fakepack/scripts/gate.sh -->" > "$S12/fakepack/SKILL.md"
export WORK12="$WORK"

# 沒帶 --pack：領域的決定是開工的一部分，不是之後補的欄位。
bash "$LOOP12" init --state "$WORK/p1.json" >/dev/null 2>&1 \
  && fail "init 沒帶 --pack 卻成功了"
[[ ! -f "$WORK/p1.json" ]] || fail "被拒的 init 還是留下了 state"
echo "  ok  init 沒帶 --pack 被拒，而且沒留下 state"

# 條件不成立：拒絕開輪次，而且不留下半個 state。
bash "$LOOP12" init --state "$WORK/p2.json" --pack fakepack >/dev/null 2>&1 \
  && fail "開工條件不成立卻開了輪次"
[[ ! -f "$WORK/p2.json" ]] || fail "條件沒過卻留下了 state"
echo "  ok  開工條件不成立時輪次不開，也不留下 state"

# 條件成立：照常開。
touch "$WORK/allowed"
bash "$LOOP12" init --state "$WORK/p3.json" --pack fakepack >/dev/null 2>&1 \
  || fail "開工條件成立卻開不了輪次"
echo "  ok  開工條件成立時照常開輪次"

# 沒有適用的領域：不施加任何條件——連條件不成立的時候都不該被擋到。
rm -f "$WORK/allowed"
bash "$LOOP12" init --state "$WORK/p4.json" --pack none --why '這是一份報告' >/dev/null 2>&1 \
  || fail "--pack none 被領域條件擋到了，那不是它的條件"
recorded="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["knowledge_pack"];print(d["pack"], d.get("why",""))' "$WORK/p4.json")"
[[ "$recorded" == "none 這是一份報告" ]] || fail "none 與理由沒有一起記下來：$recorded"
echo "  ok  沒有適用的領域時不施加條件，而且理由記下來了"

# none 沒帶理由：一個沒有理由的跳過不存在。
bash "$LOOP12" init --state "$WORK/p5.json" --pack none >/dev/null 2>&1 \
  && fail "--pack none 沒帶 --why 卻成功了"
echo "  ok  --pack none 沒帶理由被拒"

# 指名一個不存在的 pack：安靜的失敗是這整套最該防的東西。
bash "$LOOP12" init --state "$WORK/p6.json" --pack nosuchpack >/dev/null 2>&1 \
  && fail "解析不到的 pack 卻開了輪次"
echo "  ok  解析不到的 pack 被拒"

# pack 存在但沒有宣告開工條件：那是合法狀態，不是量不到。
mkdir -p "$S12/quietpack"
printf '%s\n' '---' 'name: quietpack' '---' 'no preconditions here' > "$S12/quietpack/SKILL.md"
bash "$LOOP12" init --state "$WORK/p7.json" --pack quietpack >/dev/null 2>&1 \
  || fail "沒有宣告開工條件的 pack 被當成量不到"
echo "  ok  pack 沒有宣告條件時照常開輪次"


# Case 13：工作區身分。開工條件問的是「有沒有站在對的一類地方」，對所有單都一樣；身分問的
# 是「這張單當初落在哪」，每張單不同。後者才抓得到「兩個 session 共用同一份 checkout」。
# 這一段一樣用假的 pack，核心不知道那個字串是什麼意思，它只比相不相等。
S13="$WORK/skills13"
mkdir -p "$S13/idpack/scripts" "$S13/driving-work-to-done/scripts"
cp "$LOOP" "$S13/driving-work-to-done/scripts/spine-loop-state.sh"
LOOP13="$S13/driving-work-to-done/scripts/spine-loop-state.sh"
cat > "$S13/idpack/scripts/who.sh" <<'EOF'
#!/usr/bin/env bash
[[ -f "$WORK13/whoami" ]] || { echo "求不出身分" >&2; exit 2; }
cat "$WORK13/whoami"
EOF
chmod +x "$S13/idpack/scripts/who.sh"
printf '%s\n' '---' 'name: idpack' '---' \
  "<!-- FAKE-WORKSPACE-IDENTITY: bash $S13/idpack/scripts/who.sh -->" > "$S13/idpack/SKILL.md"
export WORK13="$WORK"

# 求不出值就不開輪次：記不到值的話，之後每次比對都只能回「量不到」，那跟沒有這道檢查一樣。
bash "$LOOP13" init --state "$WORK/w0.json" --pack idpack --where anywhere >/dev/null 2>&1 \
  && fail "身分求不出值卻開了輪次"
[[ ! -f "$WORK/w0.json" ]] || fail "被拒的 init 還是留下了 state"
echo "  ok  身分求不出值時輪次不開，也沒留下 state"

printf 'lane-A\n' > "$WORK/whoami"
bash "$LOOP13" init --state "$WORK/w1.json" --pack idpack --where anywhere >/dev/null 2>&1 \
  || fail "身分求得出值卻沒開輪次"
grep -q '"lane-A"' "$WORK/w1.json" || fail "開輪次沒把身分記進 state"
grep -q '"values"' "$WORK/w1.json" || fail "身分沒被記成集合"
echo "  ok  身分在開輪次那一刻被記下來"

bash "$LOOP13" where --state "$WORK/w1.json" 2>&1 | grep -q '^workspace=ok  lane-A$' \
  || fail "身分沒變卻不是 ok"
echo "  ok  身分沒變時回 ok"

# 漂掉要說得出兩邊各是什麼，只說「不一致」等於要人自己去查。
printf 'lane-B\n' > "$WORK/whoami"
drift="$(bash "$LOOP13" where --state "$WORK/w1.json" 2>&1)"
grep -q 'workspace=DRIFTED' <<<"$drift" || fail "身分變了卻沒說漂掉：$drift"
grep -q 'lane-A' <<<"$drift" || fail "漂掉的訊息沒說出當初記的是什麼"
grep -q 'lane-B' <<<"$drift" || fail "漂掉的訊息沒說出現在是什麼"
echo "  ok  漂掉時說得出兩邊各是什麼"

# 量不到不得跟一致長得一樣。
rm -f "$WORK/whoami"
unmeasurable="$(bash "$LOOP13" where --state "$WORK/w1.json" 2>&1)"
grep -q 'workspace=unmeasurable' <<<"$unmeasurable" || fail "求不出值卻沒說量不到：$unmeasurable"
grep -q 'workspace=ok' <<<"$unmeasurable" && fail "求不出值卻回了 ok"
echo "  ok  求不出值時說量不到，不說一致"

# 沒有領域就沒有身分：不記、不比，流程照常走完。
bash "$LOOP13" init --state "$WORK/w2.json" --pack none --why '純文件' >/dev/null 2>&1 \
  || fail "--pack none 沒開成輪次"
grep -q '"kind": "none"' "$WORK/w2.json" || fail "--pack none 沒把「沒有領域」記下來"
bash "$LOOP13" where --state "$WORK/w2.json" 2>&1 | grep -q 'workspace=' \
  && fail "--pack none 卻施加了身分比對"
echo "  ok  沒有領域時不記身分也不比對"

# 那個領域沒有宣告身分：合法狀態，不是量不到。
mkdir -p "$S13/quietpack"
printf '%s\n' '---' 'name: quietpack' '---' 'nothing declared' > "$S13/quietpack/SKILL.md"
bash "$LOOP13" init --state "$WORK/w3.json" --pack quietpack >/dev/null 2>&1 \
  || fail "沒宣告身分的 pack 被當成量不到"
grep -q '"kind": "undeclared"' "$WORK/w3.json" || fail "沒宣告身分沒被記成 undeclared"
bash "$LOOP13" where --state "$WORK/w3.json" 2>&1 | grep -q 'workspace=' \
  && fail "沒宣告身分的 pack 卻施加了比對"
echo "  ok  領域沒宣告身分時不記也不比"

# Case 14：一個地方同時只交付一張單，而身分是一組不是一個。
#
# 2026-08-03 三張單疊在同一段歷史上、三份交付紀錄釘在同一個 head、最後一起出去——那個
# 局面不是誤操作，是 init 只看得到它自己那一張單，所以開得出來。這一段量的是它現在開不
# 出來了，而且拒絕的訊息說得出是哪一張、交集在哪、怎麼往下走。
#
# 一樣用假的 pack：核心不知道那些字串是什麼意思，它只算交集。
TREE="$WORK/tree14"
mkdir -p "$TREE/ns/older/.spine" "$TREE/ns/newer/.spine" "$TREE/ns/archive/settled/.spine"
git -C "$TREE" init -q
export WORK14="$WORK"
cat > "$S13/idpack/scripts/who14.sh" <<'EOF'
#!/usr/bin/env bash
[[ -f "$WORK14/whoami14" ]] || { echo "求不出身分" >&2; exit 2; }
cat "$WORK14/whoami14"
EOF
chmod +x "$S13/idpack/scripts/who14.sh"
mkdir -p "$S13/setpack"
printf '%s\n' '---' 'name: setpack' '---' \
  "<!-- FAKE-WORKSPACE-IDENTITY: bash $S13/idpack/scripts/who14.sh -->" > "$S13/setpack/SKILL.md"

# 身分是一組：宣告的命令印幾行就記幾個，不是只留第一行。
printf 'repo-A:lane-1\nrepo-B:lane-2\n' > "$WORK/whoami14"
bash "$LOOP13" init --state "$TREE/ns/older/.spine/loop-state.json" --pack setpack --where anywhere >/dev/null 2>&1 \
  || fail "多個身分卻沒開成輪次"
python3 -c '
import json, sys
v = json.load(open(sys.argv[1]))["workspace_identity"]["values"]
assert v == ["repo-A:lane-1", "repo-B:lane-2"], v
' "$TREE/ns/older/.spine/loop-state.json" || fail "印了兩個身分卻沒有兩個都被記下來"
echo "  ok  身分印幾行就記幾個"

# 那張單還沒到終局站別，所以這道關卡不參與——它擋的是「已經要出去的那張還佔著這裡」，
# 不是「這裡有另一張單」。
bash "$LOOP13" init --state "$TREE/ns/newer/.spine/loop-state.json" --pack setpack --where anywhere >/dev/null 2>&1 \
  || fail "同一個地方有一張還在施工的單，卻擋住了新輪次"
rm -f "$TREE/ns/newer/.spine/loop-state.json"
echo "  ok  還沒到終局站別的單不參與這道關卡"

# 走到終局站別之後，同一個地方開不出第二輪。
bash "$LOOP13" advance --state "$TREE/ns/older/.spine/loop-state.json" --to verify-ac >/dev/null 2>&1 \
  || fail "推不到 verify-ac"
bash "$LOOP13" advance --state "$TREE/ns/older/.spine/loop-state.json" --to delivered >/dev/null 2>&1 \
  || fail "推不到終局站別"
taken="$(bash "$LOOP13" init --state "$TREE/ns/newer/.spine/loop-state.json" --pack setpack --where anywhere 2>&1)" \
  && fail "已交付的單還佔著同一個地方，卻開出了新輪次"
grep -q 'POLARIS_SPINE_WORKSPACE_TAKEN' <<<"$taken" || fail "拒絕沒有帶 marker：$taken"
grep -q 'ns/older' <<<"$taken" || fail "拒絕沒有指名是哪一張單：$taken"
grep -q 'repo-A:lane-1' <<<"$taken" || fail "拒絕沒有說出交集落在哪：$taken"
[[ ! -f "$TREE/ns/newer/.spine/loop-state.json" ]] || fail "被拒的 init 還是留下了 state"
echo "  ok  同一個地方已有交付中的單時，新輪次開不出來"

# 拒絕要說得出往下走的路。只說不行的關卡，下一次就會被繞過去。
grep -q '釋出尾段' <<<"$taken" || fail "拒絕沒說出修法：$taken"
grep -q '換一個工作區' <<<"$taken" || fail "拒絕沒說出另一條路：$taken"
echo "  ok  拒絕帶著修法"

# 交集為空就不擋：這道關卡不會因為「這個地方交付過東西」就永久封鎖它。
printf 'repo-A:lane-9\nrepo-B:lane-9\n' > "$WORK/whoami14"
bash "$LOOP13" init --state "$TREE/ns/newer/.spine/loop-state.json" --pack setpack --where anywhere >/dev/null 2>&1 \
  || fail "交集為空卻擋住了新輪次"
echo "  ok  交集為空時照常開輪次"

# 只共用其中一個也算疊上去——比的是交集非空，不是相等。
rm -f "$TREE/ns/newer/.spine/loop-state.json"
printf 'repo-A:lane-1\nrepo-B:lane-9\n' > "$WORK/whoami14"
bash "$LOOP13" init --state "$TREE/ns/newer/.spine/loop-state.json" --pack setpack --where anywhere >/dev/null 2>&1 \
  && fail "只共用一個地方卻沒被擋"
echo "  ok  只共用其中一個也算佔著"

# 舊的形狀（單一個 value）仍然比對得動，也仍然擋得住。
python3 - "$TREE/ns/archive/settled/.spine/loop-state.json" <<'PY'
import json, sys
json.dump({"schema_version": 2, "producer": "selftest", "max_rounds": 3, "rounds": [],
           "status": "open", "station": "delivered", "stop": None, "stops": [],
           "knowledge_pack": {"pack": "setpack"},
           "workspace_identity": {"kind": "ok", "value": "repo-A:lane-1"}},
          open(sys.argv[1], "w"))
PY
old="$(bash "$LOOP13" init --state "$TREE/ns/newer/.spine/loop-state.json" --pack setpack --where anywhere 2>&1)" \
  && fail "以單一值記下的舊單沒有參與判定"
grep -q 'ns/archive/settled' <<<"$old" || fail "archive 那一層深度沒被掃到：$old"
echo "  ok  以單一值記下的舊單讀成單成員集合，照樣參與"

# 施工期間的比對是集合相等，而且要說出少了哪些、多了哪些。
printf 'repo-A:lane-1\n' > "$WORK/whoami14"
shrunk="$(bash "$LOOP13" where --state "$TREE/ns/older/.spine/loop-state.json" 2>&1)"
grep -q 'workspace=DRIFTED' <<<"$shrunk" || fail "少了一個成員卻沒說漂掉：$shrunk"
grep -q '少了：repo-B:lane-2' <<<"$shrunk" || fail "沒說出少了哪一個：$shrunk"
printf 'repo-A:lane-1\nrepo-B:lane-2\nrepo-C:lane-3\n' > "$WORK/whoami14"
grown="$(bash "$LOOP13" where --state "$TREE/ns/older/.spine/loop-state.json" 2>&1)"
grep -q 'workspace=DRIFTED' <<<"$grown" || fail "多了一個成員卻沒說漂掉：$grown"
grep -q '多了：repo-C:lane-3' <<<"$grown" || fail "沒說出多了哪一個：$grown"
echo "  ok  比對是集合相等，少了多了都說得出來"

# Case 15（DP-482）：落腳處是宣告的，不是從當下位置推的。
#
# 之前這裡不傳任何東西給領域的命令，於是那支命令只能量自己站的地方。對一張「單住在 A、
# 程式碼落在 B」的單，記下的永遠是 A——之後每次比對都拿 A 跟 A 比、永遠自洽，而 B 被別的
# session 切走時完全安靜。這一段量的是宣告真的被原樣送到、被記下來、之後拿它重求。
mkdir -p "$S13/echopack/scripts"
cat > "$S13/echopack/scripts/echo-where.sh" <<'EOF'
#!/usr/bin/env bash
# 把被告知的那一組原樣印回去，一個一行。核心不認得這些字串是什麼，這裡也不認得。
printf '%s\n' "$@"
EOF
chmod +x "$S13/echopack/scripts/echo-where.sh"
printf '%s\n' '---' 'name: echopack' '---' \
  "<!-- FAKE-WORKSPACE-IDENTITY: bash $S13/echopack/scripts/echo-where.sh -->" \
  > "$S13/echopack/SKILL.md"

unlanded="$(bash "$LOOP13" init --state "$WORK/w15.json" --pack echopack 2>&1)" \
  && fail "pack 宣告了身分、單卻沒說落在哪，輪次還是開了"
grep -q 'POLARIS_SPINE_LANDING_UNDECLARED' <<<"$unlanded" || fail "拒絕沒有帶 marker：$unlanded"
grep -q -- '--where' <<<"$unlanded" || fail "拒絕沒說出修法：$unlanded"
[[ ! -f "$WORK/w15.json" ]] || fail "被拒的 init 還是留下了 state"
echo "  ok  沒宣告落腳處就不開輪次，也沒留下 state"

# 值是不透明字串，帶空白的不得被斷成兩個——斷詞的那一版會把一個地方變成兩個。
bash "$LOOP13" init --state "$WORK/w15.json" --pack echopack \
  --where 'place one' --where 'place two' >/dev/null 2>&1 \
  || fail "宣告了落腳處卻沒開成輪次"
python3 -c '
import json, sys
w = json.load(open(sys.argv[1]))["workspace_identity"]
assert w["declared_landing"] == ["place one", "place two"], w
assert w["values"] == ["place one", "place two"], w
' "$WORK/w15.json" || fail "宣告沒有原樣被記下來、或沒有拿它求值"
echo "  ok  宣告原樣記下並拿它求值，帶空白的值不被斷成兩個"

bash "$LOOP13" landing --state "$WORK/w15.json" | tr '\n' '|' \
  | grep -q '^place one|place two|$' || fail "landing 沒有印出宣告的那一組"
echo "  ok  landing 是唯一的解析器，下游讀它就好"

# DP-482 之前開的單：狀態裡沒有宣告，比對要說 unlanded，不得靜默拿當下的位置去比。
python3 - "$WORK/w16.json" <<'PY_OLD'
import json, sys
json.dump({"schema_version": 2, "producer": "selftest", "max_rounds": 3, "rounds": [],
           "status": "open", "station": "engineering", "stop": None, "stops": [],
           "knowledge_pack": {"pack": "echopack"},
           "workspace_identity": {"kind": "ok", "values": ["place one"]}},
          open(sys.argv[1], "w"))
PY_OLD
stale="$(bash "$LOOP13" where --state "$WORK/w16.json" 2>&1)"
grep -q 'workspace=unlanded' <<<"$stale" || fail "沒有宣告的舊單卻比對了：$stale"
grep -q 'workspace=ok' <<<"$stale" && fail "沒有宣告的舊單回了 ok"
echo "  ok  沒有宣告的舊單回 unlanded，不假裝比過"

bash "$LOOP13" land --state "$WORK/w16.json" --where 'place three' >/dev/null 2>&1 \
  || fail "補記落腳處失敗"
bash "$LOOP13" where --state "$WORK/w16.json" 2>&1 | grep -q '^workspace=ok  place three$' \
  || fail "補記之後沒有立刻有基準可以比"
echo "  ok  補記當場立起基準，不留一個永遠喊漂的空集合"

relanded="$(bash "$LOOP13" land --state "$WORK/w16.json" --where 'place four' 2>&1)" \
  && fail "已宣告過的落腳處被無聲改掉"
grep -q 'POLARIS_SPINE_LANDING_ALREADY_DECLARED' <<<"$relanded" || fail "拒絕沒有帶 marker：$relanded"
bash "$LOOP13" land --state "$WORK/w16.json" --where 'place four' --authorization '就改' >/dev/null 2>&1 \
  || fail "帶了原話卻改不動"
python3 -c '
import json, sys
entries = json.load(open(sys.argv[1]))["landings"]
assert entries[-1]["previous"] == ["place three"], entries
assert entries[-1]["authorization"] == "就改", entries
' "$WORK/w16.json" || fail "改記沒有把舊值與原話留在檔案裡"
echo "  ok  改記要帶人的原話，舊值與原話都留在檔案裡"

echo "PASS: spine-loop-state-selftest.sh"
