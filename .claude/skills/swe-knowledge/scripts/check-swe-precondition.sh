#!/usr/bin/env bash
# check-swe-precondition.sh — 軟體工程的工作，開輪次之前要成立的條件。
#
# 兩條：**不站在預設分支上**，以及**那個工作區宣告的版控 hook 目錄真的被 git 在用**。
#
# 為什麼是開工前而不是交付前：`check-swe-done.sh` 也查第一條，但那時候已經來不及——改動
# 躺在預設分支上這件事，是在第一個 commit 落下的那一刻發生的，不是在交付那一刻。
# 2026-08-03 三張單的 commit 全部混在預設分支上，而當天寫下這條規矩的那個 commit 本身
# 也在預設分支上；規矩在寫下的一小時內失效四次。
#
# 第二條同一個時態問題更嚴重：hook 沒接上的 checkout，它的每一個 commit 與每一次 push
# 一道閘都不會跑，而且**不會有任何東西說**。發現的時候那些 commit 已經在歷史裡了。
#
# 第一條有三種結果，不是兩種。沒有任何 remote 的 repo，「大家共用的分支」不存在——那不是
# 量不到，是沒有那個東西可以量，所以這一條不適用，說出來並繼續（現在站在哪一條仍然印）。
# 有 remote 而解不出預設分支才是真的量不到，那一種擋，而且它的修法真的走得通。
#
# 第二條不認得任何一個 hook 目錄的位置，也不認得哪一支 skill 負責裝它。它掃那個工作區
# 自己的宣告：`{任意前綴}-GIT-HOOKS: {相對路徑} | {接上它的命令}`。沒有宣告的工作區（多數
# 產品 repo）這一條不適用，而且會把「不適用」印出來——一個安靜的第三態下一次就會被當成
# 查過了。
#
# 為什麼只有這兩條：開工前成立得了的條件才放這裡。「有一個 PR」開工前不可能成立，
# 「push 前跑完本機驗證」那時候沒有東西可以驗——那些是交付前的事。一個開工前註定
# 不成立的前置條件，只會逼人學會繞過整道閘。
#
# 核心不呼叫這個檔名，它從 swe-knowledge/SKILL.md 的 SWE-PRECONDITION 那一行讀出要跑什麼。
# 所以改名字要改那一行；不改的話核心會說它量不到，而不是安靜地放行。
#
# Usage: check-swe-precondition.sh <path>... | [--repo <path>]... [--base <branch>]
#        位置參數與 --repo 等價，可以給很多次；每一個都要成立才算成立。
# Exit:  0 全部成立 / 2 任何一個不成立、量不到，或一個地方都沒被指名

set -uo pipefail

PREFIX="[swe-precondition]"
REPO_PATHS=()
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATHS+=("${2:-}"); shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
    # 核心把這張單宣告的落腳處原樣接在宣告的命令後面，所以位置參數與 --repo 等價。
    # 核心因此不需要認得 `--repo` 這個旗標——它只是把當初被告知的那一組還回來。
    *) REPO_PATHS+=("$1"); shift ;;
  esac
done

# 要判哪些地方是被告知的，不是猜的。沒有人指名任何一個地方時這裡回非 0——那是「量不到」，
# 不是「通過」。退回 `pwd` 的那一版對「單住在 A、程式碼落在 B」的單永遠在判 A，而 A 幾乎
# 總是通過：一張改三個產品 repo 的單，開工條件是拿 workspace 自己的分支判出來的。
if [[ ${#REPO_PATHS[@]} -eq 0 ]]; then
  echo "$PREFIX 量不到：沒有任何地方被指名。" >&2
  echo "$PREFIX 這張單的改動會落在哪些地方，是開輪次時宣告的事，不是這支腳本從 cwd 猜的事。" >&2
  echo "$PREFIX 修法：spine-loop-state.sh init --where <每一個工作區的路徑>（可以給很多次）" >&2
  exit 2
fi

# Description: 這個工作區有沒有宣告一個版控的 hook 目錄。宣告掃的是它自己的 skill，核心
#              與這支腳本都不認得那個目錄叫什麼、由誰裝。
# Args: $1 = repo toplevel
# Outputs: `{相對路徑}|{接上它的命令}`；沒有宣告就什麼都不印。
hooks_declaration() {
  local top="$1" line
  [[ -d "$top/.claude/skills" ]] || return 0
  line="$(grep -rhoE '[A-Za-z0-9_-]+-GIT-HOOKS:[^>]*' "$top/.claude/skills" \
    --include=SKILL.md 2>/dev/null | head -1)"
  [[ -n "$line" ]] || return 0
  printf '%s' "${line#*-GIT-HOOKS:}" | sed 's/^ *//; s/ *$//; s/ *| */|/'
}

# Description: 判「宣告出來的那個 hook 目錄，git 真的在用嗎」。
# Args: $1 = repo toplevel
# Exit:  0 成立或不適用 / 2 不成立、量不到（訊息進 stderr，成立的一句話進 stdout）
check_hooks() {
  local top="$1" decl dir fix actual rc=0 f
  decl="$(hooks_declaration "$top")"
  if [[ -z "$decl" ]]; then
    echo "  hook：這個工作區沒有宣告版控 hook 目錄，這一條不適用。"
    return 0
  fi
  dir="${decl%%|*}"; fix="${decl#*|}"
  if [[ ! -d "$top/$dir" ]]; then
    echo "$PREFIX 量不到：${top} 宣告的 hook 目錄 ${dir} 不存在。" >&2
    echo "$PREFIX 宣告與現況對不上時這裡不放行——一個指向空氣的宣告，跟沒有宣告在出事的時候長得一樣。" >&2
    return 2
  fi
  # 沒有執行位元的 hook，git 是安靜地不跑它：沒有警告，commit 與 push 一樣過。所以「接上了」
  # 不只是 config 指對地方，還要那裡的東西真的跑得起來。
  for f in "$top/$dir"/*; do
    [[ -f "$f" ]] || continue
    if [[ ! -x "$f" ]]; then
      echo "$PREFIX 開工條件不成立：${dir}/$(basename "$f") 沒有執行位元，git 會安靜地不跑它。" >&2
      echo "$PREFIX 修法：chmod +x 它，並且讓版控也記得（git update-index --chmod=+x）。" >&2
      return 2
    fi
  done
  actual="$(git -C "$top" config --get core.hooksPath 2>/dev/null)" || rc=$?
  # git config 對「沒設」回 1，其餘非 0 才是真的讀不出來。把兩者混成一個，會讓一個壞掉的
  # config 被讀成「沒接上」——而那是一個看起來有答案的錯答案。
  if [[ "$rc" -gt 1 ]]; then
    echo "$PREFIX 量不到：${top} 的 core.hooksPath 讀不出來（git config 回 ${rc}）。" >&2
    echo "$PREFIX 問不到閘的狀態不是通過。" >&2
    return 2
  fi
  if [[ "$actual" == "$dir" || "$actual" == "$top/$dir" ]]; then
    echo "  hook：已接上 ${dir}。"
    return 0
  fi
  echo "$PREFIX 開工條件不成立：${top} 宣告了版控 hook 目錄 ${dir}，但 git 沒有在用它。" >&2
  if [[ -z "$actual" ]]; then
    echo "$PREFIX 現在 core.hooksPath 沒設，git 在用 .git/hooks——那裡沒有這套閘。" >&2
  else
    echo "$PREFIX 現在 core.hooksPath = ${actual}。" >&2
  fi
  echo "$PREFIX 沒接上的話，這個 checkout 的每個 commit 與每次 push 一道閘都不會跑，而且不會有任何東西說。" >&2
  echo "$PREFIX 修法：${fix}   然後重跑一次。" >&2
  return 2
}

# Description: 對一個 repo 判「有沒有站在預設分支上」。
# Args: $1 = repo 路徑
# Exit:  0 成立 / 2 不成立或量不到（訊息進 stderr）
check_one() {
  local REPO_PATH="$1" TOPLEVEL BRANCH LOCAL_BASE="$BASE"

TOPLEVEL="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PREFIX 量不到：${REPO_PATH} 不在 git repo 裡。" >&2
  echo "$PREFIX 一件會進版控的工作卻找不到版控，這不是通過，是量不到。" >&2
  exit 2
}

# 預設分支問 remote，不寫死 main。寫死的那一版在 master / develop 的 repo 上會一路綠，
# 而它其實一條都沒查。
if [[ -z "$LOCAL_BASE" ]]; then
  LOCAL_BASE="$(git -C "$TOPLEVEL" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  LOCAL_BASE="${LOCAL_BASE#origin/}"
fi
if [[ -z "$LOCAL_BASE" ]]; then
  # 「沒有任何 remote」與「有 remote 但 origin/HEAD 沒設」不是同一件事，而它們的下一步相反。
  # 判準跟第二條（hook）用的是同一個，不是另外發明的：**它守的那個後果在這裡存不存在**。
  #
  # 沒有任何 remote 的 repo，沒有人從這裡拉，所以「大家共用的分支」不存在——這不是量不到，
  # 是沒有那個東西可以量。拿它擋人等於用一個跟「這件事該不該做」無關的條件擋住工作：
  # 2026-08-25 一張單的兩個落腳處，因此只有一個進得了輪次，另一個整輪都沒被漂移比對看過。
  # 而且那時候給的兩條修法在那個情境下都走不通（沒有 origin 可以 set-head；--base 傳不進來）。
  if [[ -z "$(git -C "$TOPLEVEL" remote 2>/dev/null)" ]]; then
    BRANCH="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    # 不適用不等於不報告——現在站在哪一條上仍然印出來，讓讀的人自己看得到。
    echo "SWE-PRECONDITION-OK $(basename "$TOPLEVEL"):${BRANCH:-?}（沒有任何 remote，「不站在預設分支上」這一條不適用）"
    local HOOKS_LINE_NR
    HOOKS_LINE_NR="$(check_hooks "$TOPLEVEL")" || exit 2
    echo "$HOOKS_LINE_NR"
    return 0
  fi
  echo "$PREFIX 量不到：${TOPLEVEL} 有 remote，但解不出預設分支（origin/HEAD 沒設）。" >&2
  echo "$PREFIX 修法：跑 git remote set-head origin -a，或用 --base 指名。" >&2
  echo "$PREFIX 量不到不等於沒問題——這裡不放行。" >&2
  exit 2
fi

BRANCH="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "$PREFIX 量不到：${TOPLEVEL} 現在是 detached HEAD，沒有 branch 可以判。" >&2
  exit 2
fi

if [[ "$BRANCH" == "$LOCAL_BASE" ]]; then
  echo "$PREFIX 開工條件不成立：${TOPLEVEL} 站在預設分支 ${LOCAL_BASE} 上。" >&2
  echo "$PREFIX 一個還沒開工的成功定義直接躺在預設分支上，等於它已經是既成事實。" >&2
  echo "$PREFIX 修法：git switch -c feat/{單的目錄名}   然後重跑一次。" >&2
  exit 2
fi

  local HOOKS_LINE
  HOOKS_LINE="$(check_hooks "$TOPLEVEL")" || exit 2

  echo "SWE-PRECONDITION-OK $(basename "$TOPLEVEL"):${BRANCH}（預設分支是 ${LOCAL_BASE}）"
  echo "$HOOKS_LINE"
}

# 每一個都要成立。有一個不成立就整體不成立——放行一個「三個地方裡有兩個對」的開工，
# 等於那第三個地方的改動從第一個 commit 起就沒有被任何條件管過。
for REPO_PATH in "${REPO_PATHS[@]}"; do
  check_one "$REPO_PATH"
done
exit 0
