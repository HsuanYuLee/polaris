#!/usr/bin/env bash
# check-swe-done.sh — 軟體工程那四條 DoD 裡，機器查得動的三條。
#
# 查什麼：不站在預設分支上、這條 branch 有 open 的 PR、工作區乾淨。
# 不查什麼：第 4 條（push 前跑完本機驗證）。那要看是哪個專案的哪一套指令，屬公司 pack。
#
# 量不到就不是通過。沒裝 gh、沒 remote、gh 沒登入——這些都會讓「有沒有 PR」這個問題
# 得不到答案，而一個得不到答案的負向斷言天生會被讀成「沒問題」。所以查不了的一律說出
# 缺什麼並回非 0，由呼叫端決定要修環境還是明確豁免。
#
# Usage: check-swe-done.sh [--repo <path>] [--base <branch>]
# Exit:  0 三條都成立 / 2 有一條不成立，或有一條量不到

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
  pr_state="$(gh pr view "$BRANCH" --repo "$(git -C "$TOPLEVEL" remote get-url origin 2>/dev/null || echo '')" \
                --json state --jq .state 2>/dev/null || true)"
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

if [[ "$failures" -gt 0 ]]; then
  echo "$PREFIX SWE-DONE-INCOMPLETE ${failures} 條沒成立或量不到。" >&2
  exit 2
fi
echo "SWE-DONE-OK ${BRANCH} → ${BASE}"
exit 0
