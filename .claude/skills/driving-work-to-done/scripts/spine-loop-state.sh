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
#   seed  --state <path> --note <前因後果>   開一張還沒簽斷言的種子單的狀態
#   init  --state <path> --pack <領域名>|none --where <工作區路徑>... [--why <理由>] [--max-rounds N]
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
  spine-loop-state.sh init    --state <path> --pack <領域名>|none --where <工作區路徑>... [--why <理由>] [--max-rounds N]
  spine-loop-state.sh record  --state <path> --outcome converged|unconverged|zero_delta [--note <text>]
  spine-loop-state.sh next    --state <path>
  spine-loop-state.sh seed    --state <path> --note <前因後果>
  spine-loop-state.sh close   --state <path> --note <為什麼不做了> [--by <human>]
  spine-loop-state.sh next    --across-issues <issues root>
  spine-loop-state.sh where   --state <path>
  spine-loop-state.sh advance --state <path> --to refinement|engineering|verify-ac|delivered [--by <human>] [--authorization <人的原話>]
  spine-loop-state.sh stop    --state <path> --kind <kind> [--note <text>]
  spine-loop-state.sh reset   --state <path> --by <human> --authorization <人的原話> [--max-rounds N]
  spine-loop-state.sh show    --state <path>
  spine-loop-state.sh find    <單名> [--root <單樹根>] [--relative]
  spine-loop-state.sh landing --state <path>
  spine-loop-state.sh land    --state <path> --where <工作區路徑>... [--authorization <人的原話>]

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

resolve_issues_root() {
  # Description: find the issues tree when nobody handed us a path into it.
  # Args: none. Reads --root via $FIND_ROOT when the caller set it.
  # Returns: 一行 `<推導方式><TAB><絕對路徑>`。
  #
  # 為什麼把兩個值擠在一行：呼叫端是 `$(...)`，那是子 shell，設在裡面的變數傳不回來。
  # 折進這支的第一版就是那樣寫的，於是「來源」永遠印成空的——而那正是 L-P5 要說出來的
  # 那一半。儀器抓到了，這裡記下來，因為下一個人很可能想「順手」改回兩個變數。
  #
  # 這**不是** issues_root_of 的重複，兩者問的問題不同：issues_root_of 拿一條樹內的路徑
  # 反推「這張單屬於哪棵樹」，而這一支手上只有一個名字，得先找到樹本身。合併不了，所以
  # 它們挨著住並在這裡講清楚差別——合不掉的兩件事被寫成同一件，下一個人會挑一個錯的用。
  #
  # 第三種推導是關鍵：量測命令跑在框架 worktree 裡，而 `issues/` 被 gitignore 成
  # versioned-elsewhere、在 worktree 裡不存在。git 的共用 .git 指得回主 checkout，所以
  # 單樹的位置推得出來，不必有人把它抄進命令。
  local d
  if [[ -n "${FIND_ROOT:-}" ]]; then
    printf '%s\t%s\n' "--root" "$FIND_ROOT"
    return 0
  fi
  d="$(pwd -P)"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/issues" ]]; then
      printf '%s\t%s\n' "從 cwd 往上找到的 issues/" "$d/issues"
      return 0
    fi
    d="$(dirname "$d")"
  done
  local common main_checkout
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  main_checkout="$(dirname "$common")"
  [[ -d "$main_checkout/issues" ]] || return 1
  printf '%s\t%s\n' "git 共用 .git 的上一層（在 worktree 裡跑）" "$main_checkout/issues"
}

cmd_find() {
  # Description: 吃單的名字，吐它現在住在哪。位置是狀態的投影，所以沒有人存它——
  #              要用的時候問這裡（DP-496）。
  # Args: <單名> [--root <單樹根>] [--relative]
  # Exit: 0 剛好一個／3 多於一個（全部印出）／4 一個都沒有／2 用法錯或推導不出單樹根。
  #
  # 刻意不讀 loop-state.json：位置解析只回答「這個名字的目錄在哪」，狀態判定是另一件事。
  # 現況有 39 張單從來沒開過輪次，它們一樣是單，一樣要找得到。
  local name="" relative=0
  FIND_ROOT=""
  ROOT_SOURCE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) FIND_ROOT="${2:-}"; shift 2 ;;
      --relative) relative=1; shift ;;
      -*) usage; exit 2 ;;
      *)
        [[ -z "$name" ]] || { usage; exit 2; }
        name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || { usage; exit 2; }

  local derived root
  derived="$(resolve_issues_root)" || {
    echo "[find] 推導不出單樹根：cwd 往上沒有 issues/，也問不到 git 的共用 .git。要嘛帶 --root，要嘛從單樹底下跑。" >&2
    exit 2
  }
  ROOT_SOURCE="${derived%%$'\t'*}"
  root="${derived#*$'\t'}"
  [[ -d "$root" ]] || {
    echo "[find] 單樹根不存在：${root}（來源：${ROOT_SOURCE}）" >&2
    exit 2
  }
  root="$(cd "$root" && pwd -P)"

  # 完整目錄名（單號＋slug）是唯一鍵，實測跨命名空間也不重複。只給單號時走前綴比對，
  # 因為單號自己不唯一——同一個號被開過兩次、或一張單有 slug 另一張沒有，都會撞。
  # 這不是假想：寫這一支的時候，這棵樹裡就有兩組同號的單。撞到時全部回傳並非 0 退出，
  # 因為呼叫端多半在做命令替換，兩行路徑不能被當成一條用。
  local match_kind pattern pattern_alt
  if [[ "$name" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
    match_kind="單號前綴"; pattern="$name"; pattern_alt="${name}-*"
  else
    match_kind="完整目錄名"; pattern="$name"; pattern_alt="$name"
  fi

  # while-read 而不是 mapfile：macOS 原廠 /bin/bash 是 3.2，沒有 mapfile。
  local hits=() line
  while IFS= read -r line; do
    hits+=("$line")
  done < <(find "$root" -path '*/.spine' -prune -o \
             -type d \( -name "$pattern" -o -name "$pattern_alt" \) -print 2>/dev/null | sort)

  echo "[find] 單樹根 ${root}（來源：${ROOT_SOURCE}）／比對方式 ${match_kind}／命中 ${#hits[@]} 個" >&2

  local p
  case "${#hits[@]}" in
    0)
      echo "[find] 找不到「${name}」。它不在這棵單樹裡，或者名字打錯了。" >&2
      exit 4 ;;
    1)
      p="${hits[0]}"
      if ((relative)); then printf '%s\n' "${p#$root/}"; else printf '%s\n' "$p"; fi
      ;;
    *)
      for p in "${hits[@]}"; do
        if ((relative)); then printf '%s\n' "${p#$root/}"; else printf '%s\n' "$p"; fi
      done
      echo "[find]「${name}」命中 ${#hits[@]} 張，這不是一個答案。用完整目錄名（單號＋slug）再問一次。" >&2
      exit 3 ;;
  esac
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
# 這張單宣告的落腳處，一個地方一個成員。核心把它們當不透明字串，只負責記下來、之後原樣
# 交還給領域的腳本去求值。
LANDING=()

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
      --where) LANDING+=("${2:-}"); shift 2 ;;
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
  shift
  [[ "$pack" != "none" ]] || return 0
  # 拒絕要說得出怎麼往下走。只說「它不在」的話，下一步只剩兩條路：亂猜一個名字，或者
  # 把這件工作記成沒有領域——而後者買到的是一個永遠不會被檢查的完成條件。
  doc="$(pack_doc "$pack")" || die "POLARIS_SPINE_PACK_UNRESOLVED" \
    "解析不到領域知識「${pack}」——找不到它的 SKILL.md。指名一個不存在的 pack 是安靜的失敗。
這個工作區還沒有這一份的話，現在就是凝聚它的時機：回閘一，照那一站〈有些答案每張單都
一樣〉問出這一類工作在這裡怎麼算 done，寫成那份知識自己的宣告行。做完再跑一次這個命令。
真的不適用的話用 --pack none --why '<理由>'——但那是一個要說出口的選擇，不是繞道。"
  declared="$(pack_declaration "$doc" PRECONDITION)"
  if [[ -z "$declared" ]]; then
    echo "[spine-loop-state] ${pack} 沒有宣告開工條件，直接開輪次。" >&2
    return 0
  fi

  # 條件要判的是**這張單的改動會落在哪**，不是「跑這個命令的人現在站在哪」。所以宣告的
  # 落腳處原樣接在命令後面，跟 pack_identity 同一條路——核心不認得那支腳本用什麼旗標收，
  # 它只是把當初被告知的那一組交出去。少了這一段的話，一張改三個產品 repo 的單，開工條件
  # 是拿 workspace 自己的分支判出來的：那個判定跟改動落在哪完全無關，綠或紅都不代表任何事。
  local arg
  for arg in "$@"; do
    declared+=" $(printf '%q' "$arg")"
  done

  echo "[spine-loop-state] ${pack} 宣告的開工條件：${declared}" >&2
  rc=0
  run_declared "$declared" >&2 || rc=$?
  [[ "$rc" -eq 0 ]] || die "POLARIS_SPINE_PRECONDITION_FAILED" \
    "${pack} 的開工條件沒過（exit ${rc}），輪次不開。上面那幾行說了缺什麼、怎麼修。
不打算滿足它的話，用 --pack none --why '<為什麼這件工作不適用這個領域>'——
跳過要有理由，一個沒有理由的跳過不存在。"
}

# Description: 求一次「這張單宣告的那幾個地方現在是誰」。
# Args: $1 = pack 名字, $2.. = 這張單宣告的落腳處（不透明字串，原樣傳給領域的腳本）
# Prints: 一行 `<狀態>\t<值>\t<值>…`，狀態是 none|undeclared|unlanded|ok|unmeasurable；
#         unmeasurable 與 unlanded 的第二欄是理由而不是值。
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
  shift
  [[ -n "$pack" && "$pack" != "none" ]] || { printf 'none\n'; return 0; }
  # 這裡解不到 pack 是「量不到」而不是「拒絕」：開輪次那一刻的拒絕由 run_pack_precondition
  # 負責，而事後比對時 pack 不在了，能說的只有「這一行沒有比對到任何東西」。
  doc="$(pack_doc "$pack")" || { printf 'unmeasurable\t解析不到領域知識「%s」\n' "$pack"; return 0; }
  declared="$(pack_declaration "$doc" WORKSPACE-IDENTITY)"
  [[ -n "$declared" ]] || { printf 'undeclared\n'; return 0; }
  # 要量哪些地方是這張單宣告的，不是從 cwd 推的。一個地方都沒被宣告時這裡就停——
  # DP-482 之前這一行不帶參數，於是領域的腳本只好量自己站的地方，而那對「單住在 A、
  # 程式碼落在 B」的單永遠是 A，比對永遠自洽、永遠抓不到 B 被切走。
  [[ $# -gt 0 ]] || { printf 'unlanded\t%s\n' "$declared"; return 0; }
  # 值原樣傳回領域的腳本，逐個做 shell 引用。核心不認得它們是路徑、也不認得那支腳本用
  # 什麼旗標收——它只是把當初被告知的那一組還回去。
  local arg
  for arg in "$@"; do
    declared+=" $(printf '%q' "$arg")"
  done
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

# Description: 讀出這張單當初宣告的落腳處，一行一個。
# Args: $1 = state 檔路徑
# Prints: 每個宣告值一行；沒有宣告過就什麼都不印。
#
# 這是「這張單落在哪裡」的**唯一解析器**。下游要知道這件事的時候讀這一支，不要自己再從
# cwd、從 remote url、或從任何當下的位置推一次——推出來的那一份就是第二個權威，而兩份
# 會漂（DP-482 的 delivering_repo 就是這樣長出來的）。
recorded_landing() {
  require_python3
  python3 - "$1" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)
for value in (data.get("workspace_identity") or {}).get("declared_landing") or []:
    print(value)
PY
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

  # 比對要拿當初宣告的那一組去求值，不是拿現在站在哪裡去求值。DP-482 之前這裡不傳任何
  # 東西，於是比的是「這個 session 現在的 cwd」對「開輪次那次的 cwd」——兩邊都不是這張
  # 單真正動手的地方，而它們相等時看起來跟真的沒漂一模一樣。
  local landing
  local -a landings=()
  while IFS= read -r landing || [[ -n "$landing" ]]; do
    [[ -n "$landing" ]] && landings+=("$landing")
  done < <(recorded_landing "$state")

  if [[ ${#landings[@]} -eq 0 ]]; then
    echo "workspace=unlanded  這張單沒有宣告改動會落在哪些地方，沒有東西可以求值。"
    echo "  兩種來源：一張還沒開工的種子（落腳處要到 init 才知道），"
    echo "  或是 DP-482 之前開的單。前者走 init，後者要恢復比對："
    echo "  spine-loop-state.sh land --state <這張單的 loop-state.json> --where <每一個工作區的路徑>"
    return 0
  fi

  pack="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("knowledge_pack",{}).get("pack",""))' "$state")"
  now_line="$(pack_identity "$pack" "${landings[@]}")"
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
import json
import os
import sys

def find_states(root):
    """這棵樹底下每一張單的 loop-state.json，**不預設它埋在第幾層**。

    以前這裡寫死兩種深度（`*/*/` 與 `*/*/*/`），對應「活躍區」與「archive/」兩格。多開一格
    資料夾就要回來各補一條，而漏掉的那一條不會爆炸——glob 掃不到只是少算，少算的方向還剛好
    是「看起來還有比較多事沒做」，沒有人會抱怨。所以改成問一個不含深度的問題：這棵樹底下
    哪些目錄裡有 .spine/loop-state.json。

    `.git` 要跳過：單樹自己是一個 git repo，而 .git 底下的東西不是單。
    """
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        if os.path.basename(dirpath) == ".spine" and "loop-state.json" in filenames:
            found.append(os.path.join(dirpath, "loop-state.json"))
    return sorted(found)


state, terminal, root = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
now = set(sys.argv[4:])

paths = find_states(root)

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

# Description: 開一張還沒簽斷言的種子單的狀態。
#
# 為什麼種子也要有狀態檔：問路的那一支只找得到帶著 loop-state.json 的目錄，所以一張只有
# 前因後果的單對它完全隱形——不是「列在後面」，是連數字都不算。這件事量過：540 張單裡
# 517 張沒有狀態檔，其中三張散在命名空間根、不在任何格子裡，而它們從來沒出現在任何一份
# 清單上。
#
# 它刻意**不**帶領域與落腳處。那兩件事是開工才知道的，而種子單存在的理由正是「現在還不
# 知道要怎麼做，但這件事不能消失」。要它們的是 init，不是這裡。
cmd_seed() {
  parse_args "$@"
  [[ -e "$STATE" ]] \
    && die "POLARIS_SPINE_LOOP_STATE_EXISTS" "state already exists at $STATE"
  [[ -n "$NOTE" ]] || die "POLARIS_SPINE_SEED_NO_CONTEXT" \
    "seed 要 --note '<前因後果>'。一張說不出自己為什麼存在的種子單，下一個人打開它只會刪掉它。"
  require_python3
  python3 - "$STATE" "$NOTE" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

state, note = sys.argv[1], sys.argv[2]
payload = {
    # 落腳處與領域都還不知道，而「還不知道」與「沒有」在檔案裡要長得不一樣。
    "workspace_identity": {"kind": "unlanded"},
    "schema_version": 2,
    "producer": "spine-loop-state.sh",
    "rounds": [],
    "status": "open",
    # 種子停在第一個閘之前：斷言還沒簽，所以它還不能開工。
    "station": "refinement",
    "stop": None,
    "stops": [],
    "seeded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "seed_note": note,
}
os.makedirs(os.path.dirname(os.path.abspath(state)) or ".", exist_ok=True)
with open(state, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"SEEDED: {state} station=refinement")
PY
}

# Description: 這個狀態檔是不是一張還沒開工的種子（station=refinement、沒輪次、沒領域）。
# Args: $1 = 狀態檔路徑
# Returns: 0 是種子 / 1 不是（或讀不動）
is_seed_state() {
  local state="$1"
  [[ -f "$state" ]] || return 1
  python3 - "$state" <<'PY'
import json
import sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
sys.exit(0 if (d.get("station") == "refinement"
               and not d.get("rounds")
               and not d.get("knowledge_pack")) else 1)
PY
}

cmd_close() {
  # 一張單有三種終點，不是兩種：做完了、出去了、以及不做了。第三種以前沒有地方放，
  # 於是它要嘛永遠躺在待辦裡，要嘛被人手動刪掉——而刪掉的那一張，下一次有人提出同一件事
  # 的時候沒有任何東西說得出「這個討論過，結論是不做」。
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE"
  [[ -n "$NOTE" ]] || die "POLARIS_SPINE_CLOSE_NO_REASON" \
    "close 要 --note '<為什麼不做了>'。一個沒有理由的關閉，跟把單刪掉的差別只有磁碟空間。"
  require_python3
  python3 - "$STATE" "$NOTE" "$BY" <<'PY'
import json
import sys
from datetime import datetime, timezone

state, reason, by = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(state, encoding="utf-8"))
if data.get("status") == "converged":
    print("POLARIS_SPINE_CLOSE_ALREADY_CONVERGED", file=sys.stderr)
    print("這張單已經收斂了——它是做完的，不是不做的。要改判就先說清楚哪一次收斂不算數。",
          file=sys.stderr)
    raise SystemExit(2)
data["status"] = "closed"
data["closed_reason"] = reason
data["closed_by"] = by or None
now = datetime.now(timezone.utc)
data["closed_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
# 決定不做的那一天。位置底下多一層用的是這個——終局要知道時間。
data["closed_on"] = now.strftime("%Y-%m-%d")
data["schema_version"] = 2
with open(state, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"CLOSED: {state}")
print(f"  理由：{reason}")
print("  它不再出現在待辦，但它還在，而且說得出自己為什麼不做。")
PY

  # 狀態改了，痕跡也要改。在這之前 close 只改狀態——DP-440 關單之後 branch 與 PR 活了兩天，
  # 而「這張單不做了」與「還有一條 branch 在等著被合」同時成立、沒有任何東西回報。
  # 核心不認得 branch 也不認得 PR：它讀那份知識宣告的收尾命令，跑它，把它印的話原樣轉出來。
  local cleanup_rc=0
  cleanup_traces || cleanup_rc=$?
  reproject_position
  # 收不乾淨不讓 close 失敗——單已經關了，那是對的，反悔它只會讓狀態與事實更遠。但它要被
  # 看見：一個沒有被列出來的殘留，下一次就會被當成沒有殘留。
  [[ "$cleanup_rc" -eq 0 ]] \
    || echo "[spine-loop-state] 有東西沒收乾淨（見上面），單本身已經關了。" >&2
  return 0
}

# Description: 跑這張單的 pack 宣告的收尾命令；沒有宣告就說出來並當作沒有東西要收。
# Returns: 收尾命令的 exit code（沒有 pack 或沒有宣告時回 0）
cleanup_traces() {
  local pack doc declared args out rc=0
  pack="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print((data.get("knowledge_pack") or {}).get("pack") or "")' "$STATE")"
  [[ -n "$pack" && "$pack" != "none" ]] || {
    echo "  沒有領域 pack，沒有版控上的痕跡要收。"; return 0; }
  doc="$(pack_doc "$pack")" || {
    echo "[spine-loop-state] 解析不到 ${pack}，痕跡沒收——這一趟沒問到，不是沒有東西。" >&2
    return 2; }
  declared="$(pack_declaration "$doc" CLOSE-CLEANUP)"
  [[ -n "$declared" ]] || {
    echo "  ${pack} 沒有宣告收尾（CLOSE-CLEANUP），沒有東西要收。"; return 0; }

  args="$(python3 -c '
import json, shlex, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
identity = data.get("workspace_identity") or {}
out = [shlex.quote(p) for p in (identity.get("declared_landing") or [])]
for value in identity.get("values") or []:
    out += ["--identity", shlex.quote(value)]
if data.get("closed_reason"):
    out += ["--reason", shlex.quote(data["closed_reason"].splitlines()[0])]
print(" ".join(out))' "$STATE")"
  [[ -n "$args" ]] || {
    echo "  這張單沒記下落腳處，痕跡收不了（DP-482 之前的單要先 land）。"; return 2; }

  echo "[spine-loop-state] ${pack} 宣告的收尾：${declared}" >&2
  out="$(run_declared "${declared} ${args}" 2>&1)" || rc=$?
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return "$rc"
}

cmd_init() {
  parse_args "$@"
  local note_seed_upgrade=0
  [[ -n "$MAX_ROUNDS" ]] || MAX_ROUNDS="$DEFAULT_MAX_ROUNDS"
  [[ "$MAX_ROUNDS" =~ ^[1-9][0-9]*$ ]] \
    || die "POLARIS_SPINE_LOOP_BAD_CAP" "--max-rounds must be a positive integer (got '$MAX_ROUNDS')"
  # 一張種子單被拿去開工時，它身上已經有一個狀態檔了。那不是「已經開過輪次」——它是
  # 這張單當初為了不消失而留下的痕跡，現在正要被升級成真的輪次。擋住它等於逼人先手動
  # 刪掉那個檔案，而那個動作沒有任何東西在看。
  if [[ -e "$STATE" ]]; then
    if is_seed_state "$STATE"; then
      note_seed_upgrade=1
    else
      die "POLARIS_SPINE_LOOP_STATE_EXISTS" "state already exists at $STATE; use reset to start a new lineage"
    fi
  fi

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
  run_pack_precondition "$PACK" ${LANDING+"${LANDING[@]}"}

  # 「這張單落在哪個工作區」跟開輪次是同一個動作。事後補記的話，補記的時候讀到的已經是
  # 漂掉之後的值，那個欄位就永遠自洽而永遠沒有用。
  local identity_line identity_kind
  require_python3
  identity_line="$(pack_identity "$PACK" ${LANDING+"${LANDING[@]}"})"
  identity_kind="${identity_line%%$'\t'*}"
  if [[ "$identity_kind" == "unlanded" ]]; then
    die "POLARIS_SPINE_LANDING_UNDECLARED" \
      "${PACK} 宣告了工作區身分（${identity_line#*$'\t'}），但這張單沒說改動會落在哪些地方，輪次不開。
落腳處是被宣告的，不是從現在站在哪裡推出來的：推出來的那一份對「單住在 A、程式碼落在 B」
的單永遠是 A，於是之後每一次比對都拿 A 跟 A 比，永遠自洽而永遠抓不到 B 被切走。
修法：--where <工作區路徑>，一個地方給一次。"
  fi
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

  # 宣告與求值結果分兩個 argv 區段送進去，中間用一個不會出現在值裡的分隔字串隔開。
  # 兩組都是不透明字串、都可以有空白，靠數量推邊界的話一個帶空白的值會把邊界推走。
  python3 - "$STATE" "$MAX_ROUNDS" "$PACK" "$WHY" "$identity_kind" \
    ${LANDING+"${LANDING[@]}"} -- ${identities+"${identities[@]}"} <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

state, max_rounds, pack, why = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
identity_kind = sys.argv[5]
rest = sys.argv[6:]
split = rest.index("--")
declared_landing, identities = rest[:split], rest[split + 1:]
knowledge_pack = {"pack": pack}
if why:
    knowledge_pack["why"] = why
# 「這個領域沒有宣告身分」與「有宣告、值是 X」在檔案裡長得不一樣。欄位空著跟被記為
# 沒有，是同一個安靜的第三態，而那正是這張單要拆掉的形狀。
#
# 存成陣列，即使只有一個成員。一張單牽涉幾個地方由領域決定，核心不預設是一個。
#
# declared_landing 是**宣告**（這張單的改動會落在哪些地方），values 是那次宣告**當下求出
# 的值**。兩者分開存，因為之後每一次比對都要拿同一份宣告重求一次——只存結果的話，重求
# 時只能拿當下的位置去求，而那正是 DP-482 要拆掉的形狀。
workspace = {"kind": identity_kind}
if declared_landing:
    workspace["declared_landing"] = declared_landing
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
  # 覆蓋一個已經存在的檔案要說出來。一個安靜的覆蓋跟一個安靜的漏，事後看起來一樣。
  [[ "$note_seed_upgrade" -eq 1 ]] \
    && echo "[spine-loop-state] 這張單原本是一張種子（還沒簽斷言），現在升級成真的輪次。"
  return 0
}

reproject_position() {
  # 狀態換了，位置就該跟著換。這件事是流程的，不是人要記得的——靠人記得搬，遲早會有
  # 一張做完的單混在待辦裡。`record` 與 `advance` 都叫它：只掛在 record 上的話，一張
  # 推進到 verify-ac 的單會留在 in-progress/，而那正是這套設計要消除的漂移。
  local placer
  placer="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/place-issues-by-state.sh"
  local root
  root="$(issues_root_of "$STATE")"
  if [[ -f "$placer" && -n "$root" ]]; then
    # `--spine-only`：剛動過的是一張走脊椎的單，它的答案在本機。讓記一輪去問別的命名空間
    # 宣告的解析器，等於每寫一次輪次就打幾十趟網路，而且 JIRA 掛掉的時候記不成輪次。
    #
    # 不吞它的話。`|| true` 曾經把一次「根解錯了、103 個目錄被搬進 archive/archive/」
    # 整段吃掉，record 照樣印 ROUND N 然後回 0。輪次已經寫進去了，所以重算失敗不該
    # 反過來讓 record 失敗；但它必須被看見——位置與狀態對不上正是要被看見的那件事。
    bash "$placer" --issues "$root" --execute --spine-only >/dev/null \
      || echo "[spine-loop-state] 位置沒重算完，可能與狀態對不上：$placer --issues $root" >&2

    # 剛剛那一步可能把這張單搬去別的格子，於是呼叫者手上的路徑當場失效——而下一個命令
    # 會回 POLARIS_SPINE_LOOP_STATE_MISSING，讀起來像「這張單不存在」。說出它去了哪裡。
    if [[ ! -f "$STATE" ]]; then
      local moved
      moved="$(find "$root" -path "*/$(basename "$(dirname "$(dirname "$STATE")")")/.spine/loop-state.json" 2>/dev/null | head -1)"
      [[ -n "$moved" ]] && echo "MOVED: $moved"
    fi
  fi
  return 0
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

  reproject_position
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
    local libdir
    libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
    python3 - "$ACROSS_ISSUES" "$STATIONS" "$libdir" <<'PY'
import json
import os
import sys

root, stations, libdir = sys.argv[1], sys.argv[2].split(), sys.argv[3]

# 「這棵樹有幾張單」不在這裡再推導一次。位置重算那一支是唯一知道版面長什麼樣的地方，
# 它認得的那組單就是分母——自己 os.walk 一次 `.spine/` 的話，這裡與那裡會各自演化，
# 而兩份答案漂開的那一刻，讀的人沒有辦法說出哪一份錯。
sys.path.insert(0, libdir)
try:
    import place_issues_by_state as placer
except ImportError:
    sys.stderr.write(
        f"POLARIS_SPINE_PLACER_UNAVAILABLE: {libdir} 底下找不到位置重算那一支。"
        "沒有它就數不出整棵樹有幾張單，而一個少算的答案跟一個完整的答案長得一模一樣。\n")
    raise SystemExit(2)

ticket_dirs = [issue_dir for _, issue_dir in placer.tickets(root)]
# 排序只靠狀態，不靠路徑：命名空間叫什麼、單號多大，都不參與判定。往後站的先做——
# 一張已經在 verify-ac 的單離交付最近，把它放著去開新的單，就是把在製品堆高。
rank = {name: index for index, name in enumerate(stations)}
rows, unreadable = [], 0
# 狀態不在這裡的那些單。它們不是壞掉的單，是狀態的權威在別的系統——重算問過那個系統、
# 把答案寫回 `{單}/.spine/placement.json`，所以這裡讀那一份就好。**不從資料夾名推**：
# 路徑是狀態的投影，投影不是第二個權威。
elsewhere, settled_elsewhere, unplaced = 0, 0, 0
for issue_dir in ticket_dirs:
    name = os.path.relpath(issue_dir, root)
    path = os.path.join(issue_dir, ".spine", "loop-state.json")
    if not os.path.isfile(path):
        try:
            slot = json.load(
                open(os.path.join(issue_dir, ".spine", "placement.json"),
                     encoding="utf-8")).get("slot")
        except (OSError, ValueError):
            slot = None
        if slot is None:
            unplaced += 1
        elif slot in placer.SETTLED_SLOTS:
            settled_elsewhere += 1
        else:
            elsewhere += 1
        continue
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        unreadable += 1
        continue
    station = data.get("station", "engineering")
    stop = data.get("stop")
    if data.get("status") == "escalated" and not stop:
        stop = {"kind": "unconverged_cap"}
    rounds = data.get("rounds") or []
    # 「還沒簽斷言」問單自己，不從狀態檔推：封條寫在 index.md 的 frontmatter，那是權威。
    # 從「有沒有領域欄位」之類的東西倒推，是在狀態檔裡養第二份答案，而兩份會漂。
    index = os.path.join(issue_dir, "index.md")
    sealed = False
    try:
        with open(index, encoding="utf-8") as handle:
            for lineno, line in enumerate(handle):
                if lineno and line.rstrip() == "---":   # frontmatter 收尾
                    break
                if line.startswith("assertions_hash:"):
                    sealed = True
                    break
    except OSError:
        pass
    rows.append({
        "name": name,
        "station": station,
        "sealed": sealed,
        "stopped": stop["kind"] if stop else None,
        "status": data.get("status"),
        # 最後一次記輪次的時間。它是「你剛剛在做哪一張」唯一寫在磁碟上的痕跡。
        "touched": rounds[-1].get("recorded_at", "") if rounds else "",
    })

# 「不做了」跟「做完了」一樣是有結論的，所以一樣不進待辦。差別在報告上——見 close。
live = [r for r in rows
        if r["station"] != "delivered" and r["status"] not in ("converged", "closed")]
movable = [r for r in live if not r["stopped"]]
blocked = [r for r in live if r["stopped"]]

# 最靠近交付的、沒停的那一張。同一站時取最近動過的——那是「你剛剛在做哪一張」寫在磁碟上
# 的唯一痕跡，而丟掉它就會在 session 中途把人推去另一張單。都沒動過才用名字，讓同一棵樹
# 每次問都得到同一個答案：一個會變的建議等於沒有建議。
movable.sort(key=lambda r: (-rank.get(r["station"], 0), r["touched"] == "",
                            [-ord(c) for c in r["touched"]], r["name"]))

if movable:
    pick = movable[0]
    seed = "" if pick["sealed"] else " 還沒簽斷言——先走 refinement"
    print(f"next:{pick['name']} station={pick['station']}{seed}")
else:
    print("next:none")

for row in blocked:
    print(f"blocked:{row['name']} station={row['station']} stop={row['stopped']}")
# 種子逐張列出來，不只算進數字。它們的整個用途是「拿給另一個 session 開工」，而另一個
# session 開場問的第一句就是這個——掉出這個答案的東西等於沒開。
for row in sorted((r for r in movable if not r["sealed"]), key=lambda r: r["name"]):
    print(f"seed:{row['name']} 還沒簽斷言——先走 refinement")
# 已交付與收斂的不列成清單，但要有數字。不被判定的第三態如果安靜，下一次就會有人
# 以為那些也被看過了。
settled = len(rows) - len(live)
print(f"counted: live={len(live)} movable={len(movable)} blocked={len(blocked)} "
      f"settled={settled} unreadable={unreadable}")
# 逐張的清單只有一份，在 OPEN.md——同一次重算產出的。這裡指過去，不抄第二遍：兩份清單
# 會漂，而這張單要修的正是「同一個問題有兩個答案」。
if elsewhere or settled_elsewhere:
    print(f"elsewhere: {elsewhere + settled_elsewhere} 張的狀態不在這裡"
          f"（其中 {elsewhere} 張還在中間態）——逐張看 {os.path.join(root, 'OPEN.md')}")
if unplaced:
    print(f"unplaced: {unplaced} 張既沒有輪次、重算也推導不出位置——兩層都問不到，等人歸位")
# 分母寫出來，讓「加起來對不對」不必靠讀的人自己算。少算的方向剛好是「看起來事情比較少」，
# 沒有人會抱怨，所以它必須是一個看得見的等式。
print(f"tree: {len(ticket_dirs)} 張＝live {len(live)}＋settled {settled}"
      f"＋讀不動 {unreadable}＋狀態在別處 {elsewhere}"
      f"＋狀態在別處而且已經有結論 {settled_elsewhere}＋兩層都問不到 {unplaced}"
      "（movable／blocked 是 live 的細分，不另計）")
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
if "max_rounds" in data:
    print(f"rounds={len(data['rounds'])} unconverged={unconverged} "
          f"remaining={max(0, data['max_rounds'] - unconverged)} status={data['status']}")
else:
    # 種子還沒開輪次，所以沒有上限可以扣。印一個編出來的數字比說「還沒有」糟。
    print(f"rounds=0 status={data['status']}（種子：還沒開輪次，沒有上限）")
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
  # 沒換成站別就沒有新狀態可以投影，把原因原封不動送回去。少了這一行，一個被拒絕的
  # advance 會被 reproject_position 的 0 蓋掉，於是拒絕變成了成功。
  local rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  reproject_position
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

# Description: 印出這張單宣告的落腳處，一行一個。下游要知道「這張單落在哪裡」時讀這一支。
# Args: --state <path>
#
# 存在的理由是「只有一個地方回答這個問題」。DP-482 之前沒有這支，於是每個需要答案的地方
# 都自己從當下的位置推一次——交付紀錄推出 delivering_repo、閘推出 THIS_REPO，兩份互相比對，
# 而第一次真的跨 repo 的單就把它們比爆了。
cmd_landing() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_NO_STATE" "no loop state at $STATE"
  recorded_landing "$STATE"
}

# Description: 補記或改記這張單的落腳處。
# Args: --state <path> --where <值>... [--authorization <人的原話>]
#
# 補記是給 DP-482 之前開的單用的：它們的狀態裡沒有宣告，比對只能回 unlanded。
# 已經有宣告的單要改，得帶人的原話——落腳處一改，之後的比對就換了對照組，而「把對照組
# 換掉」與「漂掉了」在結果上長得一樣。簽名擋不住假話，但它讓假話留在 git 裡看得見。
cmd_land() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_NO_STATE" "no loop state at $STATE"
  [[ ${#LANDING[@]} -gt 0 ]] || die "POLARIS_SPINE_LANDING_UNDECLARED" \
    "land 要 --where <工作區路徑>，一個地方給一次。"

  local existing
  existing="$(recorded_landing "$STATE")"
  if [[ -n "$existing" && -z "$AUTHORIZATION" ]]; then
    die "POLARIS_SPINE_LANDING_ALREADY_DECLARED" \
      "這張單已經宣告過落腳處了：
${existing}
改它要帶 --authorization '<那個人自己說的話>'——換掉對照組跟漂掉在結果上長得一樣，
所以換的理由要留在檔案裡。"
  fi

  # 補記完要當場求一次值，否則檔案裡只有宣告沒有基準，之後每一次比對都拿空集合去比——
  # 而空集合對上任何東西都是 DRIFTED，一個永遠喊漂的比對跟沒有比對一樣沒用。
  # 這個基準是事後才立的，這件事本身記在 landings[] 裡，看得見。
  local pack identity_line identity_kind value
  local -a identities=()
  require_python3
  pack="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("knowledge_pack",{}).get("pack",""))' "$STATE")"
  identity_line="$(pack_identity "$pack" "${LANDING[@]}")"
  identity_kind="${identity_line%%$'\t'*}"
  [[ "$identity_kind" != "unmeasurable" ]] || die "POLARIS_SPINE_IDENTITY_UNMEASURABLE" \
    "宣告的那一組現在求不出值來（${identity_line#*$'\t'}），不補記。
記不到基準的話，之後每一次比對都只能回「量不到」——那跟沒有這道檢查是同一件事。"
  while IFS= read -r value || [[ -n "$value" ]]; do
    [[ -n "$value" ]] && identities+=("$value")
  done < <(identity_values "$identity_line")

  python3 - "$STATE" "$AUTHORIZATION" "$identity_kind" \
    "${LANDING[@]}" -- ${identities+"${identities[@]}"} <<'PY_LAND'
import json
import sys
from datetime import datetime, timezone

state, authorization, identity_kind = sys.argv[1], sys.argv[2], sys.argv[3]
rest = sys.argv[4:]
split = rest.index("--")
landing, identities = rest[:split], rest[split + 1:]

data = json.load(open(state, encoding="utf-8"))
workspace = data.setdefault("workspace_identity", {})
previous = workspace.get("declared_landing")
workspace["kind"] = identity_kind
workspace["declared_landing"] = landing
workspace["values"] = identities
entry = {"at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "landing": landing}
if previous:
    entry["previous"] = previous
if authorization:
    entry["authorization"] = authorization
data.setdefault("landings", []).append(entry)
json.dump(data, open(state, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("LANDED: " + "、".join(landing) + " → " + "、".join(identities))
PY_LAND
}

# Description: 問這張單「它出去了沒有」，出去了就把釋出紀錄寫在單身上、重算位置。
#
# 核心不認得 PR、不認得 merge、不認得任何一種釋出。它做四件事：找到這張單的 pack、讀出
# 那份知識宣告的 DELIVERED 命令、把這張單記下的落腳處與身分原樣接上去跑、非 0 就把它印的
# 話原樣轉出來。**換一個領域只要換那份宣告，這裡一行都不用動。**
#
# 為什麼核心要有這一支：在這之前「這張單出去了」只有 framework-release 的釋出尾段寫得出
# 來，而那一段做的事（壓版、推 tag、同步 template）只對自己就是 owner 的 repo 成立。一張
# 落在別人 repo 的單於是永遠停在 done/：它的 PR 早就 merge 了，而本機沒有任何東西記得
# 下來。這件事在寫這一支的當天真的有一張單卡在那裡。**「出去了」不該只有一個來源說得出口。**
#
# 沒有宣告不是「出去了」，是問不到。一個 pack 沒宣告終局訊號，核心能說的只有「這一趟沒問
# 到」——寫下釋出紀錄等於替一個沒有人回答過的問題填答案。
cmd_released() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "no loop state at $STATE"
  require_python3

  local record; record="$(dirname "$STATE")/release.json"
  if [[ -f "$record" ]]; then
    # 已經有一份就不再寫。兩個地方都能宣稱「這張單出去了」的話，它們遲早給出不同的日期。
    echo "RELEASED: 已經有釋出紀錄了，不重寫 — $record"
    return 0
  fi

  local pack; pack="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print((data.get("knowledge_pack") or {}).get("pack") or "")' "$STATE")"
  [[ -n "$pack" && "$pack" != "none" ]] || die "POLARIS_SPINE_RELEASED_NO_PACK" \
    "這張單沒有領域 pack（$pack），沒有人回答得出「它出去了沒有」。" \
    "不改程式碼的工作走完就是走完，那一類的終局不在這裡判。"

  local doc; doc="$(pack_doc "$pack")" || die "POLARIS_SPINE_RELEASED_PACK_UNRESOLVED" \
    "解析不到 pack ${pack} 的 SKILL.md"
  local declared; declared="$(pack_declaration "$doc" DELIVERED)"
  [[ -n "$declared" ]] || die "POLARIS_SPINE_RELEASED_UNDECLARED" \
    "${pack} 沒有宣告終局訊號（DELIVERED），所以「它出去了沒有」這一趟問不到。" \
    "沒問到不是出去了——去那份知識裡寫下它，再跑一次。"

  # 落腳處與身分原樣交還給那份知識。核心兩樣都當不透明字串，它只負責記得與轉交。
  local args; args="$(python3 -c '
import json, shlex, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
identity = data.get("workspace_identity") or {}
out = [shlex.quote(p) for p in (identity.get("declared_landing") or [])]
for value in identity.get("values") or []:
    out += ["--identity", shlex.quote(value)]
print(" ".join(out))' "$STATE")"

  echo "[spine-loop-state] ${pack} 宣告的終局訊號：${declared}" >&2
  local out rc=0
  out="$(run_declared "${declared} ${args}")" || rc=$?
  [[ -n "$out" ]] && printf '%s\n' "$out"

  if [[ "$rc" -ne 0 ]]; then
    # 1 與 2 原樣往上傳：還沒出去與問不到是兩件事，塌成同一個 exit code 的那一刻，
    # 一次 API 逾時就跟一張還在 review 的單長得一樣。
    echo "[spine-loop-state] 沒有寫釋出紀錄（${pack} 回 ${rc}）。" >&2
    return "$rc"
  fi

  # `$out` 用參數傳，不內插進原始碼：那份輸出是領域知識寫的，裡面有一個引號就會讓這段
  # Python 變成另一段 Python。核心跑別人給的字串時，字串永遠是資料不是程式。
  python3 - "$record" "$pack" "$declared" "$BY" "$out" <<'PY_RELEASED'
import json
import sys
from datetime import datetime, timezone

record, pack, declared, by, signal_output = sys.argv[1:6]
now = datetime.now(timezone.utc)

# 釋出日由那份知識給，不由這裡填「今天」。一張上週就走完、今天才被問到的單，填今天會讓
# released/{日期}/ 把它歸進錯的那一天——而那一格是給人翻的，日期說謊比沒有日期更糟。
# 幾個落腳處就取**最晚**的那一天：全部走完才算走完，最後出去的那一個才是這張單出去的時候。
days = sorted(
    line.split("\t")[1]
    for line in signal_output.splitlines()
    if line.startswith("delivered\t") and len(line.split("\t")) > 1
       and line.split("\t")[1] not in ("", "-"))
released_on = days[-1] if days else now.strftime("%Y-%m-%d")
with open(record, "w", encoding="utf-8") as handle:
    json.dump({
        "schema_version": 1,
        "producer": "spine-loop-state.sh released",
        "released_on": released_on,
        # 沒問到日期就退回今天，而且說出來——一個安靜的退路，下一次會被當成量到的日期。
        "released_on_source": "signal" if days else "recorded-today (訊號沒說是哪一天)",
        "recorded_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        # 訊號是誰給的要記下來：一份不知道自己憑什麼成立的釋出紀錄，事後沒有辦法被質疑。
        "signal_pack": pack,
        "signal_command": declared,
        "recorded_by": by or None,
    }, handle, ensure_ascii=False, indent=1)
    handle.write("\n")
PY_RELEASED
  echo "RELEASED: $record"
  reproject_position
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    seed) cmd_seed "$@" ;;
    close) cmd_close "$@" ;;
    init) cmd_init "$@" ;;
    record) cmd_record "$@" ;;
    next) cmd_next "$@" ;;
    where) cmd_where "$@" ;;
    advance) cmd_advance "$@" ;;
    stop) cmd_stop "$@" ;;
    reset) cmd_reset "$@" ;;
    show) cmd_show "$@" ;;
    find) cmd_find "$@" ;;
    released) cmd_released "$@" ;;
    landing) cmd_landing "$@" ;;
    land) cmd_land "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
