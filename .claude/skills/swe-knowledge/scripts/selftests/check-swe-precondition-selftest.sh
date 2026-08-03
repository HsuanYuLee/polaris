#!/usr/bin/env bash
# Purpose: 證明開工條件不會把「量不到」讀成「沒問題」，而且它認的是 remote 說的預設分支，
#          不是寫死的 main。
# Inputs:  mktemp 底下的假 repo。
# Outputs: PASS 當站在預設分支上變紅、換到 branch 上變綠、解不出預設分支變紅、
#          detached HEAD 變紅、非 git 目錄變紅，而且預設分支叫 develop 時一樣判得出來。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-swe-precondition.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*" >&2; FAIL=$((FAIL + 1)); }

# Description: 造一個 repo，預設分支叫 $2，並把 origin/HEAD 指過去。
# Args: $1 = case 名字, $2 = 預設分支名
new_repo() {
  local repo="$WORK/$1" default="$2"
  mkdir -p "$repo"
  git init -q -b "$default" "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  echo x > "$repo/f.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" remote add origin "$repo"
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD "refs/heads/$default"
  printf '%s' "$repo"
}

run() { RC=0; OUT="$(bash "$CHECK" "$@" 2>&1)" || RC=$?; }

repo="$(new_repo on_default main)"
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "站在預設分支上卻放行"
elif printf '%s' "$OUT" | grep -q '開工條件不成立'; then
  ok "站在預設分支上被擋"
else
  bad "擋了但沒說清楚：$OUT"
fi
printf '%s' "$OUT" | grep -q 'git switch -c' \
  && ok "拒絕的訊息說得出修法" || bad "拒絕沒有說修法：$OUT"

git -C "$repo" switch -q -c feat/x
run --repo "$repo"
[[ "$RC" -eq 0 ]] && ok "換到 branch 上就放行" || bad "在 branch 上卻被擋：$OUT"

# 預設分支寫死 main 的話，這個 repo 會一路綠而其實一條都沒查。
repo="$(new_repo develop_default develop)"
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "預設分支叫 develop 時放行了——這一版把 main 寫死了"
else
  ok "預設分支叫 develop 一樣判得出來"
fi

# 解不出預設分支＝量不到。負向斷言的儀器天生會把它讀成沒問題。
repo="$(new_repo no_head main)"
git -C "$repo" symbolic-ref -d refs/remotes/origin/HEAD
run --repo "$repo"
if [[ "$RC" -eq 0 ]]; then
  bad "解不出預設分支卻放行——量不到被讀成沒問題了"
elif printf '%s' "$OUT" | grep -q '量不到'; then
  ok "解不出預設分支時說出自己量不到，並且不放行"
else
  bad "沒說出是量不到：$OUT"
fi

repo="$(new_repo detached main)"
git -C "$repo" switch -q -c tmp && git -C "$repo" switch -q --detach HEAD
run --repo "$repo"
[[ "$RC" -ne 0 ]] && ok "detached HEAD 不放行" || bad "detached HEAD 放行了"

mkdir -p "$WORK/not_a_repo"
run --repo "$WORK/not_a_repo"
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '不在 git repo'; then
  ok "不在 git repo 裡不放行，而且說得出原因"
else
  bad "非 git 目錄的處理不對：rc=$RC $OUT"
fi

echo "check-swe-precondition selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
