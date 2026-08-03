#!/usr/bin/env bash
# Purpose: 證明 SWE DoD 檢查不會把「量不到」讀成「沒問題」。
# Inputs:  mktemp 底下的假 repo。
# Outputs: PASS 當站在預設分支上變紅、工作區髒變紅、解不出預設分支變紅、
#          非 git 目錄變紅，而且每一種紅都說得出自己是哪一種。
#
# 為什麼這支的重點是紅而不是綠：這是一個負向斷言的儀器。這一類天生會把「我沒看到 PR」
# 跟「沒有 PR」混成同一件事，而混掉的那一版永遠是綠的。所以每一條「量不到」都要有自己的
# 出口，而且要能被指名。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-swe-done.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*" >&2; FAIL=$((FAIL + 1)); }

# Description: 造一個乾淨的 git repo，回傳路徑。
# Args: $1 = case 名字
new_repo() {
  local repo="$WORK/$1"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  echo base > "$repo/file.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  printf '%s' "$repo"
}

# Description: 跑一次檢查，把 stdout 與 stderr 併起來回傳；exit code 存進 RC。
run() {
  RC=0
  OUT="$(bash "$CHECK" "$@" 2>&1)" || RC=$?
}

# 站在預設分支上做事，是這四條裡最容易發生也最常被略過的一條。
repo="$(new_repo on_default)"
run --repo "$repo" --base main
if [[ "$RC" -eq 0 ]]; then
  bad "站在預設分支上卻判綠"
elif printf '%s' "$OUT" | grep -q '第 1 條不成立'; then
  ok "站在預設分支上會紅，而且指名是第 1 條"
else
  bad "紅了但沒指名是哪一條：$OUT"
fi

# 沒 commit 的東西，PR 看不到。
repo="$(new_repo dirty)"
git -C "$repo" checkout -q -b feat/x
echo more >> "$repo/file.txt"
run --repo "$repo" --base main
if [[ "$RC" -eq 0 ]]; then
  bad "工作區髒卻判綠"
elif printf '%s' "$OUT" | grep -q '第 3 條不成立'; then
  ok "工作區髒會紅，而且指名是第 3 條"
else
  bad "紅了但沒指名是哪一條：$OUT"
fi

# 解不出預設分支就是量不到，不是通過。寫死 main 的那一版在 master / develop 的 repo 上
# 會一路綠，而它其實一條都沒查。
repo="$(new_repo no_base)"
git -C "$repo" checkout -q -b feat/y
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "解不出預設分支卻判綠——量不到被讀成沒問題了"
elif printf '%s' "$OUT" | grep -q '解不出預設分支'; then
  ok "解不出預設分支會紅，而且說得出是量不到"
else
  bad "紅了但沒說出是量不到：$OUT"
fi

# 根本不在 git 裡：一條都查不了。
mkdir -p "$WORK/not_a_repo"
run --repo "$WORK/not_a_repo"
if [[ "$RC" -eq 0 ]]; then
  bad "不在 git repo 裡卻判綠"
elif printf '%s' "$OUT" | grep -q '不在 git repo'; then
  ok "不在 git repo 裡會紅，而且說得出原因"
else
  bad "紅了但沒說出原因：$OUT"
fi

# 「沒裝 gh」跟「沒開 PR」必須是兩句不同的話。混成一句的那一版，會讓一個沒裝 gh 的環境
# 永遠讀成「你忘了開 PR」，而那是一個沒有人修得掉的指控。
repo="$(new_repo no_gh)"
git -C "$repo" checkout -q -b feat/z
PATH="/usr/bin:/bin" run --repo "$repo" --base main
if [[ "$RC" -eq 0 ]]; then
  bad "問不到 PR 卻判綠"
elif printf '%s' "$OUT" | grep -qE '量不到第 2 條|第 2 條不成立'; then
  ok "問不到 PR 時，第 2 條有自己的說法"
else
  bad "第 2 條沒有出口：$OUT"
fi

echo "check-swe-done selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
