#!/usr/bin/env bash
# check-swe-precondition.sh — 軟體工程的工作，開輪次之前要成立的條件。
#
# 只有一條：**不站在預設分支上**。
#
# 為什麼是開工前而不是交付前：`check-swe-done.sh` 也查這一條，但那時候已經來不及——改動
# 躺在預設分支上這件事，是在第一個 commit 落下的那一刻發生的，不是在交付那一刻。
# 2026-08-03 三張單的 commit 全部混在預設分支上，而當天寫下這條規矩的那個 commit 本身
# 也在預設分支上；規矩在寫下的一小時內失效四次。
#
# 為什麼只有一條：開工前成立得了的條件才放這裡。「有一個 PR」開工前不可能成立，
# 「push 前跑完本機驗證」那時候沒有東西可以驗——那些是交付前的事。一個開工前註定
# 不成立的前置條件，只會逼人學會繞過整道閘。
#
# 核心不呼叫這個檔名，它從 swe-knowledge/SKILL.md 的 SWE-PRECONDITION 那一行讀出要跑什麼。
# 所以改名字要改那一行；不改的話核心會說它量不到，而不是安靜地放行。
#
# Usage: check-swe-precondition.sh [--repo <path>] [--base <branch>]
# Exit:  0 成立 / 2 不成立，或量不到

set -uo pipefail

PREFIX="[swe-precondition]"
REPO_PATH=""
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(pwd)"

TOPLEVEL="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PREFIX 量不到：${REPO_PATH} 不在 git repo 裡。" >&2
  echo "$PREFIX 一件會進版控的工作卻找不到版控，這不是通過，是量不到。" >&2
  exit 2
}

# 預設分支問 remote，不寫死 main。寫死的那一版在 master / develop 的 repo 上會一路綠，
# 而它其實一條都沒查。
if [[ -z "$BASE" ]]; then
  BASE="$(git -C "$TOPLEVEL" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  BASE="${BASE#origin/}"
fi
if [[ -z "$BASE" ]]; then
  echo "$PREFIX 量不到：解不出預設分支（origin/HEAD 沒設）。" >&2
  echo "$PREFIX 修法：跑 git remote set-head origin -a，或用 --base 指名。" >&2
  echo "$PREFIX 量不到不等於沒問題——這裡不放行。" >&2
  exit 2
fi

BRANCH="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "$PREFIX 量不到：現在是 detached HEAD，沒有 branch 可以判。" >&2
  exit 2
fi

if [[ "$BRANCH" == "$BASE" ]]; then
  echo "$PREFIX 開工條件不成立：現在站在預設分支 ${BASE} 上。" >&2
  echo "$PREFIX 一個還沒開工的成功定義直接躺在預設分支上，等於它已經是既成事實。" >&2
  echo "$PREFIX 修法：git switch -c feat/{單的目錄名}   然後重跑一次。" >&2
  exit 2
fi

echo "SWE-PRECONDITION-OK ${BRANCH}（預設分支是 ${BASE}）"
exit 0
