#!/usr/bin/env bash
# check-swe-done.sh — 軟體工程那五條 DoD 裡，機器查得動的四條。
#
# 查什麼：不站在預設分支上、這條 branch 有 open 的 PR、工作區乾淨、reviewer 提的意見
#         都有處置回到那條意見上。
# 不查什麼：第 4 條（push 前跑完本機驗證）。那要看是哪個專案的哪一套指令，屬公司 pack。
#
# 第 5 條為什麼在這裡而不是自己一支：**「這張單做完了沒」只能有一個答案。** 分成兩支的
# 那一版，會出現「done 說可以、回覆檢查說不行」同時成立，而沒有人有辦法說出哪一份錯。
#
# 量不到就不是通過。沒裝 gh、沒 remote、gh 沒登入——這些都會讓「有沒有 PR」這個問題
# 得不到答案，而一個得不到答案的負向斷言天生會被讀成「沒問題」。所以查不了的一律說出
# 缺什麼並回非 0，由呼叫端決定要修環境還是明確豁免。
#
# Usage: check-swe-done.sh [--repo <path>] [--base <branch>]
# Exit:  0 四條都成立 / 2 有一條不成立，或有一條量不到

set -uo pipefail

PREFIX="[swe-done]"
REPO_PATH=""
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(pwd)"

TOPLEVEL="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PREFIX 量不到：$REPO_PATH 不在 git repo 裡。" >&2
  exit 2
}

failures=0
PR_NUMBER=""
PR_AUTHOR=""
note() { echo "$PREFIX $*" >&2; }
bad()  { note "$*"; failures=$((failures + 1)); }

# 預設分支是問 remote 的，不是寫死 main。寫死的那一版在 master / develop 的 repo 上
# 會一路綠，而它其實一條都沒查。
if [[ -z "$BASE" ]]; then
  BASE="$(git -C "$TOPLEVEL" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  BASE="${BASE#origin/}"
fi
if [[ -z "$BASE" ]]; then
  bad "量不到：解不出預設分支（origin/HEAD 沒設）。用 --base 指名，或跑 git remote set-head origin -a。"
fi

BRANCH="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  bad "量不到：現在是 detached HEAD，沒有 branch 可以判。"
elif [[ -n "$BASE" && "$BRANCH" == "$BASE" ]]; then
  bad "第 1 條不成立：改動躺在預設分支 ${BASE} 上。開一條 branch 再做。"
else
  echo "$PREFIX ✅ 第 1 條：在 ${BRANCH}，不是預設分支。" >&2
fi

if [[ -n "$(git -C "$TOPLEVEL" status --porcelain 2>/dev/null)" ]]; then
  bad "第 3 條不成立：工作區有沒 commit 的東西，PR 看不到它們。"
else
  echo "$PREFIX ✅ 第 3 條：工作區乾淨。" >&2
fi

# 有沒有 PR。這一段的每一種「答不出來」都要各自說出自己是什麼，不能收斂成一句
# 「沒有 PR」——沒裝 gh 跟沒開 PR 是完全不同的兩件事，混在一起的那一版會讓一個
# 沒裝 gh 的環境永遠讀成「你忘了開 PR」。
if ! command -v gh >/dev/null 2>&1; then
  bad "量不到第 2 條：找不到 gh。修法：裝好 GitHub CLI 再跑，或用 --base 之外的方式自己確認 PR。"
elif [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  : # 上面已經記過一次，不重複計數
else
  pr_origin="$(git -C "$TOPLEVEL" remote get-url origin 2>/dev/null || echo '')"
  # 一次問齊 state／number／author：第 5 條要後兩者，而分成兩次問會出現「兩次問到不同
  # 的 PR」——中間有人關掉又開了一個的話，第 2 條與第 5 條就在講兩件事。
  pr_facts="$(gh pr view "$BRANCH" --repo "$pr_origin" \
                --json state,number,author --jq '[.state, (.number|tostring), .author.login] | @tsv' 2>/dev/null || true)"
  pr_state="${pr_facts%%$'\t'*}"
  if [[ -n "$pr_facts" ]]; then
    PR_NUMBER="$(printf '%s' "$pr_facts" | cut -f2)"
    PR_AUTHOR="$(printf '%s' "$pr_facts" | cut -f3)"
  fi
  if [[ -z "$pr_state" ]]; then
    pr_state="$(gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null || true)"
    if [[ -z "$pr_state" ]]; then
      bad "量不到第 2 條：gh 問不到 PR（沒登入、沒 remote、或 repo 解不出來）。"
    elif [[ "$pr_state" == "0" ]]; then
      bad "第 2 條不成立：${BRANCH} 沒有 open 的 PR。PR 開出來才算實作完成。"
    else
      echo "$PREFIX ✅ 第 2 條：${BRANCH} 有 open 的 PR。" >&2
    fi
  elif [[ "$pr_state" == "OPEN" ]]; then
    echo "$PREFIX ✅ 第 2 條：${BRANCH} 有 open 的 PR。" >&2
  else
    bad "第 2 條不成立：${BRANCH} 的 PR 是 ${pr_state}，不是 OPEN。"
  fi
fi

# 第 5 條：reviewer 提的意見，處置有沒有回到那條意見上。
#
# 為什麼是「那條意見上」而不是「有沒有回」：一個修好了但沒有回到提出者那裡的處置，對提出者
# 等於沒修。回在別的地方（另一個系統的訊息、另一張單）提出者拿不到——他看的是他留言的地方。
#
# 誰的回覆算數：只有這個 PR 的作者。另一位 reviewer 在同一串裡接話不是作者的處置，而把
# 「這串有人回過」當成成立的那一版，會讓兩個 reviewer 互相討論就把作者放行。
#
# owner/name 用參數展開切，不用 sed：BSD 的 ERE 沒有 lazy quantifier，而
# `([^/]+?)(\.git)?$` 那個寫法在 GNU 上對、在這台機器上會把 `.git` 吃進 name 裡。
slug_src="${pr_origin:-}"
slug_src="${slug_src%.git}"
slug_src="${slug_src%/}"
repo_name="${slug_src##*/}"
owner_part="${slug_src%/*}"
owner_part="${owner_part##*[:/]}"
SLUG="${owner_part}/${repo_name}"

if [[ -z "$PR_NUMBER" ]]; then
  # 上面已經為「沒有 PR」或「問不到」記過一次了。沒有 PR 的時候這一條無從問起，不重複計數，
  # 但也不印一句✅——一句沒有量到任何東西的✅，下一次就會被當成查過了。
  :
elif [[ -z "${owner_part:-}" || -z "${repo_name:-}" || "${owner_part}" == "${slug_src}" ]]; then
  bad "量不到第 5 條：從 origin 的位址（${pr_origin:-空的}）解不出 owner/name。"
else
  # 沒有上層的那一欄吐 `-` 而不是空字串：`IFS=$'\t'` 底下連續的 tab 會被併成一個分隔符
  # （tab 是 IFS 的空白類），所以中間那一欄空著的話，`read a b c` 會把第三欄讀進 b。
  # 那一版把每一則都當成回覆，於是「有人沒回」永遠是綠的。
  replies_tsv="$(gh api "repos/${SLUG}/pulls/${PR_NUMBER}/comments" --paginate \
                   --jq '.[] | [(.id|tostring), ((.in_reply_to_id // "-")|tostring), .user.login] | @tsv' 2>/dev/null)" || replies_tsv="__UNREADABLE__"
  if [[ "$replies_tsv" == "__UNREADABLE__" ]]; then
    bad "量不到第 5 條：問不到 PR #${PR_NUMBER} 的 review 意見（遠端回非 0、沒登入、或沒有權限）。"
  else
    # 一串意見的所有回覆，in_reply_to_id 都指向那一串的第一則，所以「這串作者回過沒」
    # 就是「有沒有一則 in_reply_to_id = 串頭、而且作者是 PR 作者」。
    answered=" "
    while IFS=$'\t' read -r cid root who; do
      [[ "$root" != "-" && -n "$root" && "$who" == "$PR_AUTHOR" ]] && answered="${answered}${root} "
    done <<< "$replies_tsv"

    unanswered=0
    while IFS=$'\t' read -r cid root who; do
      [[ -z "$cid" ]] && continue
      [[ "$root" != "-" ]] && continue             # 不是串頭
      [[ "$who" == "$PR_AUTHOR" ]] && continue     # 自己開的串不是別人的意見
      case "$answered" in
        *" ${cid} "*) continue ;;
      esac
      unanswered=$((unanswered + 1))
      note "  沒回：#${cid}（${who} 提的）"
    done <<< "$replies_tsv"

    if [[ "$unanswered" -gt 0 ]]; then
      bad "第 5 條不成立：PR #${PR_NUMBER} 上有 ${unanswered} 條 reviewer 意見還沒有處置回到那條意見上。"
    else
      echo "$PREFIX ✅ 第 5 條：PR #${PR_NUMBER} 上 reviewer 的意見都回過了。" >&2
    fi
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$PREFIX SWE-DONE-INCOMPLETE ${failures} 條沒成立或量不到。" >&2
  exit 2
fi
echo "SWE-DONE-OK ${BRANCH} → ${BASE}"
exit 0
