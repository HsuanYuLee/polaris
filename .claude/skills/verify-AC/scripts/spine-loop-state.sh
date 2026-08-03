#!/usr/bin/env bash
# Spine loop state: rounds advance, and the loop has an end.
#
# Two things this state machine has to hold at once.
#
# A round that produced no code is a legitimate result. "Tried route A, hit X,
# concluding route B, code discarded" is knowledge, and the flow continues from
# it. Treating an empty round as a failure creates an incentive to dress a
# failed exploration up as a delivery, which is worse than the empty round.
#
# The loop still ends. A round that produced nothing is a round that did not
# converge, so it counts toward the cap exactly like any other unconverged
# round. Without that, "keep exploring" would be an unbounded licence and the
# escalation would never fire.
#
# Once the cap is reached the loop stops turning by itself: further rounds are
# refused until a human resets it. The cap N starts at 3 and lives in the
# adjustable zone — it is a tuning parameter, not an acceptance condition, and
# moving it moves the boundary with it.
#
# This state also answers "where am I". Once one word from a human starts the
# flow and nobody names the next entry again, two questions have to be
# answerable off disk rather than out of a conversation: which station this
# source is at, and — if it is not moving — which of the four declared reasons
# it stopped for. A flow that can stop anywhere needs a human watching it, which
# is the same as not running by itself; a flow that can only stop in four named
# places can be left alone.
#
# The four are fixed here rather than passed in. An unnamed stop and a silent
# stop are the same thing to whoever comes back later, so the enum refuses
# anything it does not recognise instead of recording a free-text reason.
#
# Subcommands:
#   init  --state <path> [--max-rounds N]
#   record --state <path> --outcome converged|unconverged|zero_delta [--note <text>]
#   next  --state <path>          prints continue | escalate | done | stop:<kind>
#   where --state <path>          prints station, stop, rounds — the resume view
#   advance --state <path> --to refinement|engineering|verify-ac|delivered [--by <human>] [--authorization <人的原話>]
#   stop  --state <path> --kind <kind> [--note <text>]
#   reset --state <path> --by <human> --authorization <人的原話> [--max-rounds N]
#   show  --state <path>
#
# Signing without typing.
#   The two moves that need a human — clearing a stop and resetting the cap — used
#   to be a bash line only the author of this file could type. That put the flow's
#   resume path behind a skill nobody outside this repo has, which is the same as
#   having no resume path.
#
#   So the signature is no longer the act of typing. It is `--authorization`: the
#   human's own words, verbatim, stored in the state and therefore in git. An agent
#   can run the command on their behalf — that was always true and pretending
#   otherwise only made the ceremony longer — but what it has to produce is a quote
#   that can be checked against the conversation. A fabricated one is a fabricated
#   quote, which is a different and much more visible thing than a fabricated flag.
#
#   This is why reset refuses an empty authorization but cannot refuse a false one.
#   The mechanism makes the lie legible; it does not make it impossible.
#
# Exit codes:
#   0  the subcommand succeeded
#   2  refused (escalated loop, missing state, bad arguments)

set -uo pipefail

DEFAULT_MAX_ROUNDS=3

# The stations, in the order the flow walks them. `delivered` is the terminal:
# what happens after it — compressing a version, promoting a branch, cutting a
# release — belongs to whichever project this is, not to the spine.
STATIONS="refinement engineering verify-ac delivered"

# The four declared stops. Nothing else is a stop; anything else is "I do not
# know where I am", which is a state to be read off disk, not a reason to halt.
STOP_KINDS="assertion_wrong surfaced_concern unconverged_cap unauthorized_action"

usage() {
  cat >&2 <<'EOF'
Usage:
  spine-loop-state.sh init    --state <path> [--max-rounds N]
  spine-loop-state.sh record  --state <path> --outcome converged|unconverged|zero_delta [--note <text>]
  spine-loop-state.sh next    --state <path>
  spine-loop-state.sh where   --state <path>
  spine-loop-state.sh advance --state <path> --to refinement|engineering|verify-ac|delivered [--by <human>] [--authorization <人的原話>]
  spine-loop-state.sh stop    --state <path> --kind <kind> [--note <text>]
  spine-loop-state.sh reset   --state <path> --by <human> --authorization <人的原話> [--max-rounds N]
  spine-loop-state.sh show    --state <path>

Stop kinds: assertion_wrong | surfaced_concern | unconverged_cap | unauthorized_action
EOF
}

die() {
  # Description: emit a POLARIS marker plus human message, then fail closed.
  # Args: $1 = marker, $2.. = message
  local marker="$1"
  shift
  echo "$marker" >&2
  echo "$*" >&2
  exit 2
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

issues_root_of() {
  # Description: resolve the issues root that owns a state file, for the archiver.
  # Args: $1 = path to a .spine/loop-state.json
  # Returns: absolute path on stdout, or empty when the state lives outside an issues repo.
  #
  # 不從 state 往上數固定層數。單在活躍區是三層、在 archive/ 裡是四層，數死的那一版會在
  # 收斂後的單上算出 issues/{命名空間} 當根——然後 `archive` 看起來就像一個命名空間，
  # 底下每一張已歸檔的單都會被搬進 archive/archive/。2026-08-03 就這樣一次搬了 103 個檔案，
  # 而且因為呼叫端接了 `|| true`，全程沒有一個字說出來。
  #
  # 用 repo 根當答案：`issues/` 本來就是它自己的 git repo（見 document-flow.md），所以
  # 「這張單屬於哪棵 issues 樹」有現成的權威，不需要從路徑深度推。解不出 repo 的（測試用的
  # 暫存 fixture）回空字串，呼叫端就不會去掃任何真實的樹。
  local dir top
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 0
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -n "$top" ]] && printf '%s\n' "$top"
}

STATE=""
OUTCOME=""
NOTE=""
BY=""
MAX_ROUNDS=""
TO=""
KIND=""
AUTHORIZATION=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) STATE="${2:-}"; shift 2 ;;
      --outcome) OUTCOME="${2:-}"; shift 2 ;;
      --note) NOTE="${2:-}"; shift 2 ;;
      --by) BY="${2:-}"; shift 2 ;;
      --max-rounds) MAX_ROUNDS="${2:-}"; shift 2 ;;
      --to) TO="${2:-}"; shift 2 ;;
      --kind) KIND="${2:-}"; shift 2 ;;
      --authorization) AUTHORIZATION="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [[ -n "$STATE" ]] || { usage; exit 2; }
}

in_list() {
  # Description: whether $1 appears as a whole word in the space-separated $2.
  # Args: $1 = needle, $2 = haystack
  # Returns: 0 when present, 1 otherwise.
  local needle="$1" item
  for item in $2; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

cmd_init() {
  parse_args "$@"
  [[ -n "$MAX_ROUNDS" ]] || MAX_ROUNDS="$DEFAULT_MAX_ROUNDS"
  [[ "$MAX_ROUNDS" =~ ^[1-9][0-9]*$ ]] \
    || die "POLARIS_SPINE_LOOP_BAD_CAP" "--max-rounds must be a positive integer (got '$MAX_ROUNDS')"
  [[ -e "$STATE" ]] \
    && die "POLARIS_SPINE_LOOP_STATE_EXISTS" "state already exists at $STATE; use reset to start a new lineage"

  require_python3
  python3 - "$STATE" "$MAX_ROUNDS" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

state, max_rounds = sys.argv[1], int(sys.argv[2])
payload = {
    "schema_version": 2,
    "producer": "spine-loop-state.sh",
    "max_rounds": max_rounds,
    "rounds": [],
    "status": "open",
    # This file is created at the end of the first gate, so the station it
    # opens at is the one after it.
    "station": "engineering",
    "stop": None,
    "stops": [],
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
os.makedirs(os.path.dirname(os.path.abspath(state)) or ".", exist_ok=True)
with open(state, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"INIT: {state} max_rounds={max_rounds}")
PY
}

cmd_record() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  case "$OUTCOME" in
    converged|unconverged|zero_delta) ;;
    *) die "POLARIS_SPINE_LOOP_BAD_OUTCOME" "--outcome must be converged|unconverged|zero_delta (got '$OUTCOME')" ;;
  esac

  require_python3
  # 這一輪寫不寫得下去由這段決定；下面的歸檔不可以影響它的結果，所以先接住 exit code。
  local rc=0
  python3 - "$STATE" "$OUTCOME" "$NOTE" <<'PY'
import json
import sys
from datetime import datetime, timezone

state, outcome, note = sys.argv[1:4]
data = json.load(open(state, encoding="utf-8"))

def fail(marker, *lines):
    print(marker, file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    sys.exit(2)

if data["status"] == "escalated":
    # The message a human actually reads when the loop halts. It used to be a bash
    # invocation, which told whoever hit it to go learn this script — the same
    # failure G-P2 names: saying what happened without saying what they can do.
    fail("POLARIS_SPINE_LOOP_ESCALATED",
         f"這個 loop 連續 {data['max_rounds']} 輪沒收斂，停下來等人看一眼。",
         "你可以做的：說一句「繼續」或「授權」，就會開新一輪，先前的紀錄全部保留。",
         "（等價指令：reset --by <你> --authorization '<你說的那句話>'）")
# A converged loop is NOT closed. converged means "this round settled, next stop is
# verify-ac" — it is a success signal, and refusing to record after a success signal was a
# gate pointed at the wrong thing. It blocked two flows the skills themselves document:
# verify-ac's "判非 PASS 之後回 engineering" (you return to engineering and cannot record), and a source
# that ships one slice and keeps going (DP-462 shipped v3.84.0 with its assertions still
# unverified, then could not record another round). Recording again simply continues the
# lineage; history is kept, not cleared.
#
# What still stops a runaway is the cap below, which is the only thing the cap was ever
# for: unconverged rounds piling up with no progress.

data["rounds"].append({
    "index": len(data["rounds"]) + 1,
    # Which run of the loop this round belongs to. reset opens a new lineage
    # instead of deleting the old rounds — see cmd_reset.
    "lineage": data.get("lineage", 1),
    "outcome": outcome,
    # A zero-delta round is knowledge, not delivery. It is recorded as such so
    # nobody has to dress it up as a deliverable to keep the loop alive.
    "produced_code_delta": outcome not in ("zero_delta",),
    "note": note or None,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
})

if outcome == "converged":
    data["status"] = "converged"
else:
    # A round that did not converge reopens the loop, including when the previous
    # round had converged: shipping a slice does not end a source whose assertions
    # are still unverified.
    data["status"] = "open"
    # zero_delta and unconverged both count: a round that did not converge is a
    # round that did not converge, whatever it produced. Only the current lineage
    # counts: a reset opens a new run of the loop, and rounds a human already
    # looked at and released must not keep the cap permanently tripped.
    current = data.get("lineage", 1)
    unconverged = sum(1 for r in data["rounds"]
                      if r["outcome"] != "converged" and r.get("lineage", 1) == current)
    if unconverged >= data["max_rounds"]:
        # Reaching the cap is one of the four declared stops, but it is not
        # written down as one: status == escalated already says it, and two
        # records of one fact drift apart. next and where derive it.
        data["status"] = "escalated"

with open(state, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"ROUND {len(data['rounds'])}: outcome={outcome} status={data['status']}")
PY
  rc=$?
  # 沒寫進去就沒有新狀態可以投影，直接把原因原封不動送回去。
  [[ "$rc" -eq 0 ]] || return "$rc"

  # 收斂那一刻，這張單就不再擋在路上了。位置跟著狀態走是流程的事，不是人要記得的事——
  # 靠人記得搬，遲早會有一張做完的單混在待辦裡。歸檔的判定住在 verify-ac（判定站），
  # 這裡跨 skill 取用而不複製一份：兩份會漂，而漂掉的那一刻正好是位置與狀態對不上的時候。
  local archiver
  archiver="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../verify-ac/scripts" 2>/dev/null && pwd)/archive-delivered-issues.sh"
  local root
  root="$(issues_root_of "$STATE")"
  if [[ -f "$archiver" && -n "$root" ]]; then
    bash "$archiver" --issues "$root" >/dev/null || true
  fi
  return 0
}

cmd_next() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  require_python3
  python3 - "$STATE" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
stop = data.get("stop")
# One way to ask "am I stopped, and which of the four" — including the cap,
# which is derived from status rather than stored. A flow told "continue" while
# it is halted would walk straight past the thing that halted it, and a flow
# told "escalate" has to already know that word is secretly one of the four.
if stop:
    print(f"stop:{stop['kind']}")
elif data["status"] == "escalated":
    print("stop:unconverged_cap")
else:
    print({"open": "continue", "converged": "done"}[data["status"]])
PY
}

cmd_where() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  require_python3
  python3 - "$STATE" <<'PY'
import json
import sys

# The resume view. Whoever picks this source up next — a new session, a
# different person, tomorrow's you — gets where it is and what is left without
# reconstructing it from a conversation that is gone.
data = json.load(open(sys.argv[1], encoding="utf-8"))
stations = ["refinement", "engineering", "verify-ac", "delivered"]
# States written before stations existed do not know where they are, and
# saying "engineering" as though they did would be an invention. Say which it is.
legacy = "station" not in data
station = data.get("station", "engineering")
current = data.get("lineage", 1)
unconverged = sum(1 for r in data["rounds"]
                  if r["outcome"] != "converged" and r.get("lineage", 1) == current)
stop = data.get("stop")
if not stop and data["status"] == "escalated":
    stop = {
        "kind": "unconverged_cap",
        "note": f"{unconverged} unconverged rounds reached the cap of {data['max_rounds']}",
        "at": data["rounds"][-1]["recorded_at"] if data["rounds"] else None,
    }

print(f"station={station}" + ("  (defaulted: this state predates stations)" if legacy else ""))
if stop:
    print(f"stopped={stop['kind']}")
    if stop.get("note"):
        print(f"  why: {stop['note']}")
    print(f"  since: {stop.get('at') or 'unknown'}")
    # G-P2: a stop has to say what the person can do, in words they can say back.
    # The command is the footnote, not the instruction — whoever is reading this
    # may have no idea what a --state path is, and should not need one.
    if stop["kind"] == "unconverged_cap":
        print("  你可以做的：說一句「繼續」或「授權」，就會開新一輪並保留先前所有紀錄。")
        print("  （等價指令：reset --by <你> --authorization '<你說的那句話>'）")
    else:
        print("  你可以做的：說一句同意，就會解掉這個停點並往下一站走。")
        print("  （等價指令：advance --to <station> --by <你> --authorization '<你說的那句話>'）")
else:
    print("stopped=no")
    nxt = stations[stations.index(station) + 1] if station in stations[:-1] else None
    print(f"next_station={nxt or 'none (terminal)'}")
print(f"rounds={len(data['rounds'])} unconverged={unconverged} "
      f"remaining={max(0, data['max_rounds'] - unconverged)} status={data['status']}")
PY
}

cmd_advance() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  in_list "$TO" "$STATIONS" \
    || die "POLARIS_SPINE_LOOP_BAD_STATION" \
         "--to must be one of: $STATIONS (got '${TO:-}')"

  require_python3
  python3 - "$STATE" "$TO" "$BY" "$AUTHORIZATION" <<'PY'
import json
import sys
from datetime import datetime, timezone

state, to, by, authorization = sys.argv[1:5]
data = json.load(open(state, encoding="utf-8"))

# Leaving a stop is a human's move, in the same shape as resetting the cap.
# Without this the flow could record a stop and then walk past it unaided,
# which would make the stop decorative.
if data.get("stop") and not by:
    print("POLARIS_SPINE_LOOP_STOP_UNCLEARED", file=sys.stderr)
    print(f"this source is stopped at '{data['stop']['kind']}'; "
          "advancing past a stop requires --by <human>", file=sys.stderr)
    sys.exit(2)

previous = data.get("station", "engineering")
data["station"] = to
if data.get("stop"):
    if not authorization.strip():
        print("POLARIS_SPINE_LOOP_UNQUOTED_AUTHORIZATION", file=sys.stderr)
        print("clearing a stop requires --authorization '<the human's own words>'; "
              "record what they actually said, verbatim", file=sys.stderr)
        sys.exit(2)
    data.setdefault("clearances", []).append({
        "by": by,
        "authorization": authorization,
        "kind": data["stop"]["kind"],
        "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    })
    data["stop"] = None
    data["cleared_by"] = by
data["schema_version"] = 2
with open(state, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"STATION: {previous} -> {to}")
PY
}

cmd_stop() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  in_list "$KIND" "$STOP_KINDS" \
    || die "POLARIS_SPINE_LOOP_UNDECLARED_STOP" \
         "--kind must be one of: $STOP_KINDS (got '${KIND:-}')." \
         "A stop that is not one of these is not a stop — it is 'I do not know where I am', which where reads off disk."

  require_python3
  python3 - "$STATE" "$KIND" "$NOTE" <<'PY'
import json
import sys
from datetime import datetime, timezone

state, kind, note = sys.argv[1:4]
data = json.load(open(state, encoding="utf-8"))
entry = {
    "kind": kind,
    "note": note or None,
    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "station": data.get("station", "engineering"),
}
data["stop"] = entry
data.setdefault("stops", []).append(entry)
data["schema_version"] = 2
with open(state, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"STOP: {kind} at station {entry['station']}")
# G-P2 again: a stop that only reports itself leaves the person holding it with
# nothing to do next.
print("你可以做的：說一句同意，就會解掉這個停點並往下走。")
print("（等價指令：advance --to <station> --by <你> --authorization '<你說的那句話>'）")
PY
}

cmd_reset() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  [[ -n "$BY" ]] \
    || die "POLARIS_SPINE_LOOP_RESET_UNSIGNED" "reset requires --by <human>; the cap exists so a person looks at the loop"
  # The signature is the human's own words, not the act of typing this line. An
  # empty one is refused because a signature nobody said is not a signature.
  [[ -n "${AUTHORIZATION// /}" ]] \
    || die "POLARIS_SPINE_LOOP_UNQUOTED_AUTHORIZATION" \
         "reset requires --authorization '<the human's own words>'; record what they actually said, verbatim." \
         "A --by string is a name an agent can type. A quote is something that can be checked against the conversation."
  if [[ -n "$MAX_ROUNDS" && ! "$MAX_ROUNDS" =~ ^[1-9][0-9]*$ ]]; then
    die "POLARIS_SPINE_LOOP_BAD_CAP" "--max-rounds must be a positive integer (got '$MAX_ROUNDS')"
  fi

  require_python3
  python3 - "$STATE" "$BY" "$MAX_ROUNDS" "$AUTHORIZATION" <<'PY'
import json
import sys
from datetime import datetime, timezone

state, by, max_rounds, authorization = sys.argv[1:5]
data = json.load(open(state, encoding="utf-8"))
# A new run of the loop, not a new loop. The old rounds stay: E-P4 ("you can pick
# it up after an interruption") is carried by exactly that history, and the first
# version deleted it — so the only way past the cap was to destroy the thing the
# resume view reads. The cap counts the current lineage, so opening a new one
# releases it without losing anything.
data["lineage"] = data.get("lineage", 1) + 1
data.setdefault("resets", []).append({
    "by": by,
    "authorization": authorization,
    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "rounds_carried": len(data["rounds"]),
    "previous_status": data["status"],
    "lineage": data["lineage"],
})
data["status"] = "open"
if max_rounds:
    data["max_rounds"] = int(max_rounds)
with open(state, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"RESET: by={by} lineage={data['lineage']} rounds_kept={len(data['rounds'])} "
      f"max_rounds={data['max_rounds']}")
PY
}

cmd_show() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE; run init first"
  require_python3
  python3 - "$STATE" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
current = data.get("lineage", 1)
unconverged = sum(1 for r in data["rounds"]
                  if r["outcome"] != "converged" and r.get("lineage", 1) == current)
stop = data.get("stop")
print(f"status={data['status']} station={data.get('station', 'engineering')} "
      f"stopped={stop['kind'] if stop else 'no'} rounds={len(data['rounds'])} "
      f"unconverged={unconverged} max_rounds={data['max_rounds']}")
for round_ in data["rounds"]:
    print(f"  {round_['index']}: {round_['outcome']} "
          f"code_delta={round_['produced_code_delta']}")
# Who released this loop, and on the strength of what they said. Printed rather
# than left in the file: a signature nobody ever reads is decorative.
for reset in data.get("resets", []):
    print(f"  reset by {reset['by']} → lineage {reset.get('lineage', '?')}: "
          f"{reset.get('authorization') or '(未記錄原話)'}")
PY
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    init) cmd_init "$@" ;;
    record) cmd_record "$@" ;;
    next) cmd_next "$@" ;;
    where) cmd_where "$@" ;;
    advance) cmd_advance "$@" ;;
    stop) cmd_stop "$@" ;;
    reset) cmd_reset "$@" ;;
    show) cmd_show "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
