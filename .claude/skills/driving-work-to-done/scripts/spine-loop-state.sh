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
#   init  --state <path> --pack <領域名>|none [--why <理由>] [--max-rounds N]
#   record --state <path> --outcome converged|unconverged|zero_delta [--note <text>]
#   next  --state <path>          prints continue | escalate | done | stop:<kind>
#   next  --across-issues <root>  prints which issue to work next, across the whole tree
#   where --state <path>          prints station, stop, rounds, and whether this
#                                 workspace is still the one the issue opened in
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
  spine-loop-state.sh init    --state <path> --pack <領域名>|none [--why <理由>] [--max-rounds N]
  spine-loop-state.sh record  --state <path> --outcome converged|unconverged|zero_delta [--note <text>]
  spine-loop-state.sh next    --state <path>
  spine-loop-state.sh next    --across-issues <issues root>
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
ACROSS_ISSUES=""
PACK=""
WHY=""

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
      --across-issues) ACROSS_ISSUES="${2:-}"; shift 2 ;;
      --pack) PACK="${2:-}"; shift 2 ;;
      --why) WHY="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [[ -n "$STATE" || -n "$ACROSS_ISSUES" ]] || { usage; exit 2; }
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

# Description: 解出 skill 根目錄（所有 pack 的家）。
# Prints: 絕對路徑；解不出來就印空字串。
skills_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd
}

# Description: 解出指名 pack 的 SKILL.md。
# Args: $1 = pack 名字
# Prints: 檔案路徑
# Returns: 0 找得到，1 找不到
#
# 這裡刻意不 die：它的呼叫者都在 `$( )` 裡，而 `die` 在 subshell 只殺得掉那個 subshell，
# 主流程照樣往下跑。第一版就是那樣寫的，於是「指名一個不存在的 pack」從拒絕變成安靜放行
# ——正好是這整套最該防的形狀。要不要 die 由呼叫者在它自己那一層決定。
pack_doc() {
  local root doc
  root="$(skills_root)" || return 1
  doc="$root/$1/SKILL.md"
  [[ -f "$doc" ]] || return 1
  printf '%s' "$doc"
}

# Description: 讀出某份 pack 知識裡宣告的某一行命令。
# Args: $1 = SKILL.md 路徑, $2 = 宣告的鍵（PRECONDITION、WORKSPACE-IDENTITY）
# Prints: 宣告的命令字串；沒有宣告這一項就印空字串。
#
# 兩種宣告共用這一支。抄成兩份剖析器的話，兩邊會各自長出自己的邊界情形——而其中一邊的
# 剖析錯誤會偽裝成一次失敗的檢查，那比檢查沒跑更難查（`--` 沒剝乾淨那次就是）。
pack_declaration() {
  local declared
  # 宣告寫在 HTML 註解裡，所以要把收尾的 `-->` 剝掉，再剝尾端空白。
  declared="$(sed -n "s/.*[A-Z-]*${2}:[[:space:]]*\(.*\)-->.*/\1/p" "$1" | head -1)"
  printf '%s' "${declared%"${declared##*[![:space:]]}"}"
}

# Description: 在 repo 根目錄跑一行宣告出來的命令。
# Args: $1 = 命令字串
# Prints: 該命令的 stdout（原樣）
# Returns: 該命令的 exit code
run_declared() {
  local root; root="$(skills_root)"
  ( cd "$root/../.." && eval "$1" )
}

# Description: 跑指名 pack 宣告的開工條件；不成立就 die。
# Args: $1 = pack 名字（none 代表沒有適用的領域）
#
# 核心不認得任何一個領域的條件。它只做三件事：找到那個 pack 的 SKILL.md、讀出宣告的那一
# 行、跑它。條件的內容寫在 pack 裡，改條件不用動這裡；而這裡不知道「branch」是什麼字，
# 所以一件寫報告的工作走這條路不會撞到任何 SWE 的東西。
#
# 宣告不見了不是通過，是量不到——pack 存在但沒有宣告，代表它沒有開工條件，那是一個
# 合法的狀態；pack 解析不到才是拒絕，而那個由 pack_declaration 擋。
run_pack_precondition() {
  local pack="$1" doc declared rc
  [[ "$pack" != "none" ]] || return 0
  doc="$(pack_doc "$pack")" || die "POLARIS_SPINE_PACK_UNRESOLVED" \
    "解析不到領域知識「${pack}」——找不到它的 SKILL.md。指名一個不存在的 pack 是安靜的失敗。"
  declared="$(pack_declaration "$doc" PRECONDITION)"
  if [[ -z "$declared" ]]; then
    echo "[spine-loop-state] ${pack} 沒有宣告開工條件，直接開輪次。" >&2
    return 0
  fi

  echo "[spine-loop-state] ${pack} 宣告的開工條件：${declared}" >&2
  rc=0
  run_declared "$declared" >&2 || rc=$?
  [[ "$rc" -eq 0 ]] || die "POLARIS_SPINE_PRECONDITION_FAILED" \
    "${pack} 的開工條件沒過（exit ${rc}），輪次不開。上面那幾行說了缺什麼、怎麼修。
不打算滿足它的話，用 --pack none --why '<為什麼這件工作不適用這個領域>'——
跳過要有理由，一個沒有理由的跳過不存在。"
}

# Description: 求一次「這個工作區現在是哪些」。
# Args: $1 = pack 名字
# Prints: 一行 `<狀態>\t<值>\t<值>…`，狀態是 none|undeclared|ok|unmeasurable；
#         unmeasurable 的第二欄是理由而不是值。
#
# 核心把每個值當**不透明字串**看待：它只會拿這一組跟先前記下的那一組比。所以換一個領域
# 只要換那個領域印什麼，這裡一行都不用動；而「求不出來」有自己的狀態，永遠不會跟
# 「求出來而且相等」走到同一個分支。
#
# **印幾行就是幾個身分。** 第一版在這裡 `head -1`，等於把「一件工作只落在一個地方」寫死
# 成核心的前提——而這條開發鏈從一開始就不是那樣：交付紀錄同時釘兩個 repo 的 head，
# assertions_hash 也早就是一個 map。窄口在這一行，不在設計裡。
pack_identity() {
  local pack="$1" doc declared value rc=0 joined
  [[ -n "$pack" && "$pack" != "none" ]] || { printf 'none\n'; return 0; }
  # 這裡解不到 pack 是「量不到」而不是「拒絕」：開輪次那一刻的拒絕由 run_pack_precondition
  # 負責，而事後比對時 pack 不在了，能說的只有「這一行沒有比對到任何東西」。
  doc="$(pack_doc "$pack")" || { printf 'unmeasurable\t解析不到領域知識「%s」\n' "$pack"; return 0; }
  declared="$(pack_declaration "$doc" WORKSPACE-IDENTITY)"
  [[ -n "$declared" ]] || { printf 'undeclared\n'; return 0; }
  value="$(run_declared "$declared" 2>/dev/null)" || rc=$?
  # 去尾空白、去空行、去重、排序。集合沒有順序，而一個順序會變的集合每次比對都會漂——
  # 那種漂看起來跟真的漂掉一模一樣。
  joined="$(printf '%s\n' "$value" | sed 's/[[:space:]]*$//' | grep -v '^$' | sort -u \
            | tr '\n' '\t' | sed 's/\t$//')"
  if [[ "$rc" -ne 0 || -z "$joined" ]]; then
    printf 'unmeasurable\t%s\n' "$declared"
    return 0
  fi
  printf 'ok\t%s\n' "$joined"
}

# Description: 把 pack_identity 那一行拆成一行一個值。
# Args: $1 = pack_identity 印出來的那一行
# Prints: 每個值一行；沒有值時什麼都不印。
identity_values() {
  local line="$1"
  [[ "$line" == *$'\t'* ]] || return 0
  printf '%s' "${line#*$'\t'}" | tr '\t' '\n'
}

# Description: 把「當初記下的工作區」與「現在的工作區」比一次，結果印出來。
# Args: $1 = state 檔路徑
#
# 這是 M-P2 的形狀：漂掉的時候要說得出兩邊各是什麼，只說「不一致」等於要人自己去查。
# 三種結果各自有自己的字首，`ok` 以外的都不得被讀成一致——特別是 `unmeasurable`，
# 一個求不出值來的比對什麼都沒比。
report_workspace_identity() {
  local state="$1" recorded_kind now_line now_kind pack
  recorded_kind="$(python3 - "$state" <<'PY'
import json, sys
w = json.load(open(sys.argv[1], encoding="utf-8")).get("workspace_identity")
print("unrecorded" if not w else w.get("kind", "unrecorded"))
PY
)"
  case "$recorded_kind" in
    none|undeclared) return 0 ;;   # 沒有領域、或那個領域沒有宣告身分：沒有東西該被比對
    unrecorded)
      echo "workspace=unrecorded  這張單開輪次時還沒有記下工作區身分，沒有東西可以比對。"
      return 0 ;;
  esac

  pack="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("knowledge_pack",{}).get("pack",""))' "$state")"
  now_line="$(pack_identity "$pack")"
  now_kind="${now_line%%$'\t'*}"

  if [[ "$now_kind" != "ok" ]]; then
    python3 - "$state" "$now_kind" <<'PY'
import json, sys
w = json.load(open(sys.argv[1], encoding="utf-8")).get("workspace_identity") or {}
recorded = w.get("values") or ([w["value"]] if w.get("value") else [])
print(f"workspace=unmeasurable  當初記的是「{'、'.join(recorded)}」，現在求不出值來（{sys.argv[2]}）。")
print("  量不到不等於還在原地——這一行沒有比對到任何東西。")
PY
    return 0
  fi

  # 比的是集合相等，不是「有沒有交集」。少一個成員代表這張單原本涵蓋的某個地方現在不在
  # 手上了，那跟多一個一樣是漂——只要交集非空就當一致的話，涵蓋範圍會靜默縮小。
  local value
  local -a vals=()
  while IFS= read -r value || [[ -n "$value" ]]; do
    [[ -n "$value" ]] && vals+=("$value")
  done < <(identity_values "$now_line")

  python3 - "$state" "${vals[@]}" <<'PY'
import json, sys
w = json.load(open(sys.argv[1], encoding="utf-8")).get("workspace_identity") or {}
# 舊的形狀是單一個值。讀成只有一個成員的集合，比對照常進行——一張在這之前開的單
# 不會因為欄位換了形狀就變成量不到。
recorded = set(w.get("values") or ([w["value"]] if w.get("value") else []))
now = set(sys.argv[2:])
show = lambda s: "、".join(sorted(s)) if s else "（空）"
if now == recorded:
    print(f"workspace=ok  {show(now)}")
    sys.exit(0)
print(f"workspace=DRIFTED  當初記的是「{show(recorded)}」，現在是「{show(now)}」。")
missing, extra = recorded - now, now - recorded
if missing:
    print(f"  少了：{show(missing)}")
if extra:
    print(f"  多了：{show(extra)}")
print("  這張單的改動預期落在當初記下的那一組。可能是有人在這個工作區切走了，也可能是")
print("  另一個 session 正在共用同一份 checkout——先確認要落在哪一邊，再繼續動手。")
PY
}

# Description: 同一棵單樹裡，有沒有一張已走到終局站別的單正佔著現在這一組身分；有就 die。
# Args: $1 = 這張新單的 state 檔路徑, $2 = pack_identity 印出來的那一行
#
# 比法是**交集非空**，不是相等——共用其中任何一個地方，新的一輪就疊在別人的歷史上了。
# 這跟 report_workspace_identity 的相等比法問的不是同一件事，所以刻意不共用一支。
#
# 2026-08-03 這一天三張單就是這樣疊起來的：三份交付紀錄釘在同一個 head，最後一起出去，
# 而中間沒有任何一步說過話——init 只看得到它自己那一張單。
refuse_if_workspace_taken() {
  local state="$1" line="$2" terminal report value rc=0
  local -a vals=()
  terminal="${STATIONS##* }"
  # 值走 argv，不走 stdin：`python3 -` 的程式本身就是 stdin，heredoc 會把管線蓋掉，
  # 於是要比對的那一組靜默變成空集合——一道永遠比不到東西的閘，看起來跟一道通過的閘一樣。
  while IFS= read -r value || [[ -n "$value" ]]; do
    [[ -n "$value" ]] && vals+=("$value")
  done < <(identity_values "$line")
  [[ ${#vals[@]} -gt 0 ]] || return 0

  # 單樹的根用 repo 根解，不從路徑往上數層數——單在活躍區是三層、在 archive/ 裡是四層，
  # 數死的那一版會在收斂後的單上算出錯的根。這支已經有一個解得對的：issues_root_of。
  local root; root="$(issues_root_of "$state")"
  [[ -n "$root" ]] || return 0   # 解不出樹就沒有別張單可以比，不是「通過」也不是「拒絕」

  report="$(python3 - "$state" "$terminal" "$root" "${vals[@]}" <<'PY'
import glob
import json
import os
import sys

state, terminal, root = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
now = set(sys.argv[4:])

# 兩種深度，跟 next --across-issues 掃的是同一棵樹：活躍的單在 {命名空間}/{單}/，
# 收斂後被流程搬進 {命名空間}/archive/{單}/。
paths = sorted(glob.glob(os.path.join(root, "*", "*", ".spine", "loop-state.json"))
               + glob.glob(os.path.join(root, "*", "*", "*", ".spine", "loop-state.json")))

hits = []
for path in paths:
    if os.path.abspath(path) == state:
        continue
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if data.get("station") != terminal:
        continue
    w = data.get("workspace_identity") or {}
    theirs = set(w.get("values") or ([w["value"]] if w.get("value") else []))
    shared = theirs & now
    if shared:
        name = os.path.relpath(os.path.dirname(os.path.dirname(path)), root)
        hits.append((name, shared))

if not hits:
    sys.exit(0)
for name, shared in hits:
    print(f"{name} 已經走到終局站別，而它落在「{'、'.join(sorted(shared))}」——跟現在這裡同一個。")
print("在同一個地方再開一輪，兩張單就疊在同一段歷史上，最後只能一起出去。")
print("往下走的路有兩條：把那張單的釋出尾段走完（走完之後這裡就不再是它的了），")
print("或是換一個工作區再開這一輪。")
sys.exit(3)
PY
)" || rc=$?
  [[ "$rc" -eq 0 ]] || die "POLARIS_SPINE_WORKSPACE_TAKEN" "$report"
}

cmd_init() {
  parse_args "$@"
  [[ -n "$MAX_ROUNDS" ]] || MAX_ROUNDS="$DEFAULT_MAX_ROUNDS"
  [[ "$MAX_ROUNDS" =~ ^[1-9][0-9]*$ ]] \
    || die "POLARIS_SPINE_LOOP_BAD_CAP" "--max-rounds must be a positive integer (got '$MAX_ROUNDS')"
  [[ -e "$STATE" ]] \
    && die "POLARIS_SPINE_LOOP_STATE_EXISTS" "state already exists at $STATE; use reset to start a new lineage"

  # 領域的決定跟開輪次是同一個動作。分成兩步的那一版要人記得補第二步，而「需要什麼知識」
  # 沒被回答就往下走，正是 K-N1 禁止的形狀。
  [[ -n "$PACK" ]] || die "POLARIS_SPINE_PACK_UNDECLARED" \
    "init 要 --pack <領域名>|none。這件工作屬於哪個領域是開工的一部分，不是之後補的欄位。
會改到程式碼、要進版控 → --pack swe-knowledge
不會改程式碼（報告、調查、文件、資料分析） → --pack none --why '<理由>'"
  if [[ "$PACK" == "none" ]]; then
    [[ -n "$WHY" ]] || die "POLARIS_KNOWLEDGE_PACK_NONE_UNJUSTIFIED" \
      "--pack none 要帶 --why。「沒有適用的領域」是一個被記下來的選擇，不是欄位空著。"
  fi
  run_pack_precondition "$PACK"

  # 「這張單落在哪個工作區」跟開輪次是同一個動作。事後補記的話，補記的時候讀到的已經是
  # 漂掉之後的值，那個欄位就永遠自洽而永遠沒有用。
  local identity_line identity_kind
  require_python3
  identity_line="$(pack_identity "$PACK")"
  identity_kind="${identity_line%%$'\t'*}"
  if [[ "$identity_kind" == "unmeasurable" ]]; then
    die "POLARIS_SPINE_IDENTITY_UNMEASURABLE" \
      "${PACK} 宣告了工作區身分（${identity_line#*$'\t'}），但現在求不出值來，輪次不開。
記不到值的話，之後每一次比對都只能回「量不到」——那跟沒有這道檢查是同一件事。
上面那幾行說了缺什麼。"
  fi

  # 求得出值來才有東西可以比。求不出來的情形上面已經拒絕過了，所以這裡不會有
  # 「比不到就當沒事」的分支——那個分支是這道閘唯一有意義的失效方式。
  [[ "$identity_kind" != "ok" ]] || refuse_if_workspace_taken "$STATE" "$identity_line"

  # 一個一個讀進陣列，不靠展開時的斷詞。核心把每個值當不透明字串，而不透明的字串裡
  # 可以有空白——靠斷詞的話，一個帶空白的身分會靜默變成兩個。
  local value
  local -a identities=()
  while IFS= read -r value || [[ -n "$value" ]]; do
    [[ -n "$value" ]] && identities+=("$value")
  done < <(identity_values "$identity_line")

  python3 - "$STATE" "$MAX_ROUNDS" "$PACK" "$WHY" "$identity_kind" \
    ${identities+"${identities[@]}"} <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

state, max_rounds, pack, why = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
identity_kind, identities = sys.argv[5], sys.argv[6:]
knowledge_pack = {"pack": pack}
if why:
    knowledge_pack["why"] = why
# 「這個領域沒有宣告身分」與「有宣告、值是 X」在檔案裡長得不一樣。欄位空著跟被記為
# 沒有，是同一個安靜的第三態，而那正是這張單要拆掉的形狀。
#
# 存成陣列，即使只有一個成員。一張單牽涉幾個地方由領域決定，核心不預設是一個。
workspace = {"kind": identity_kind}
if identities:
    workspace["values"] = identities
payload = {
    "workspace_identity": workspace,
    # 領域的決定跟輪次同時落地。分成兩個檔案／兩個動作的那一版，「有沒有記」變成一個
    # 要人記得去查的東西，而沒記跟記了 none 在檔案裡長得一樣。
    "knowledge_pack": knowledge_pack,
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
  # 靠人記得搬，遲早會有一張做完的單混在待辦裡。
  local archiver
  archiver="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/archive-delivered-issues.sh"
  local root
  root="$(issues_root_of "$STATE")"
  if [[ -f "$archiver" && -n "$root" ]]; then
    # 不吞它的話。`|| true` 曾經把一次「根解錯了、103 個目錄被搬進 archive/archive/」
    # 整段吃掉，record 照樣印 ROUND N 然後回 0。輪次已經寫進去了，所以歸檔失敗不該
    # 反過來讓 record 失敗；但它必須被看見——位置與狀態對不上正是要被看見的那件事。
    bash "$archiver" --issues "$root" >/dev/null \
      || echo "[spine-loop-state] 歸檔沒跑完，位置可能與狀態對不上：$archiver --issues $root" >&2
  fi
  return 0
}

cmd_next() {
  parse_args "$@"
  # 跨單那一層。單一張單內部的推進早就有機制（輪次、四種停點、where）；缺的一直是
  # 「手上有六張單，接下來做哪一張」——那個問題只有人回答得出來，所以每一次都要問人，
  # 而每一次問人就是連續退化成單步的那一刻。
  #
  # 它是這支腳本多一個模式，不是一支新 skill：一支新 skill 就是第二個回答「下一步」的
  # 地方，正是這張單在拆的形狀。
  if [[ -n "$ACROSS_ISSUES" ]]; then
    require_python3
    python3 - "$ACROSS_ISSUES" "$STATIONS" <<'PY'
import glob
import json
import os
import sys

root, stations = sys.argv[1], sys.argv[2].split()
# 排序只靠狀態，不靠路徑：命名空間叫什麼、單號多大，都不參與判定。往後站的先做——
# 一張已經在 verify-ac 的單離交付最近，把它放著去開新的單，就是把在製品堆高。
rank = {name: index for index, name in enumerate(stations)}
rows, unreadable = [], 0
for path in sorted(glob.glob(os.path.join(root, "*", "*", ".spine", "loop-state.json"))
                   + glob.glob(os.path.join(root, "*", "*", "*", ".spine", "loop-state.json"))):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        unreadable += 1
        continue
    issue_dir = os.path.dirname(os.path.dirname(path))
    name = os.path.relpath(issue_dir, root)
    station = data.get("station", "engineering")
    stop = data.get("stop")
    if data.get("status") == "escalated" and not stop:
        stop = {"kind": "unconverged_cap"}
    rounds = data.get("rounds") or []
    rows.append({
        "name": name,
        "station": station,
        "stopped": stop["kind"] if stop else None,
        "status": data.get("status"),
        # 最後一次記輪次的時間。它是「你剛剛在做哪一張」唯一寫在磁碟上的痕跡。
        "touched": rounds[-1].get("recorded_at", "") if rounds else "",
    })

live = [r for r in rows if r["station"] != "delivered" and r["status"] != "converged"]
movable = [r for r in live if not r["stopped"]]
blocked = [r for r in live if r["stopped"]]

# 最靠近交付的、沒停的那一張。同一站時取最近動過的——那是「你剛剛在做哪一張」寫在磁碟上
# 的唯一痕跡，而丟掉它就會在 session 中途把人推去另一張單。都沒動過才用名字，讓同一棵樹
# 每次問都得到同一個答案：一個會變的建議等於沒有建議。
movable.sort(key=lambda r: (-rank.get(r["station"], 0), r["touched"] == "",
                            [-ord(c) for c in r["touched"]], r["name"]))

if movable:
    pick = movable[0]
    print(f"next:{pick['name']} station={pick['station']}")
else:
    print("next:none")

for row in blocked:
    print(f"blocked:{row['name']} station={row['station']} stop={row['stopped']}")
# 已交付與收斂的不列成清單，但要有數字。不被判定的第三態如果安靜，下一次就會有人
# 以為那些也被看過了。
print(f"counted: live={len(live)} movable={len(movable)} blocked={len(blocked)} "
      f"settled={len(rows) - len(live)} unreadable={unreadable}")
PY
    return 0
  fi
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
  # 站別是「走到哪」，這一行是「還在不在原地」。兩件事都屬於 resume view：接手的人要知道
  # 的不只是下一步做什麼，還有他手上這個工作區是不是這張單當初落腳的那一個。
  report_workspace_identity "$STATE"
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
