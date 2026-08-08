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

# 有幾個落腳處就判幾次。核心把這張單宣告的那幾個地方原樣接在宣告的命令後面，所以位置參數
# 與 --repo 等價。少了這一段的話，一張改三個產品 repo 的單會被拿 workspace 自己的分支去判
# ——那個判定跟改動落在哪裡完全無關（同事在一張跨 repo 的單上撞到）。
multi_a="$(new_repo multi_a main)"; git -C "$multi_a" switch -q -c feat/a
multi_b="$(new_repo multi_b main)"; git -C "$multi_b" switch -q -c feat/b

RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_b" 2>&1)" || RC=$?
if [[ "$RC" -eq 0 ]] && [[ "$(printf '%s\n' "$OUT" | grep -c 'SWE-PRECONDITION-OK')" -eq 2 ]]; then
  ok "指名幾個就判幾個，每一個各印一行"
else
  bad "多個落腳處沒有逐個判：rc=$RC $OUT"
fi

RC=0; OUT="$(bash "$CHECK" --repo "$multi_a" --repo "$multi_b" 2>&1)" || RC=$?
[[ "$RC" -eq 0 ]] && ok "--repo 給很多次與位置參數等價" \
  || bad "--repo 給很多次卻不通過：rc=$RC $OUT"

# 有一個站在預設分支上就要整體紅。放行「三個裡有兩個對」，等於第三個地方的改動從第一個
# commit 起就沒被任何條件管過。
multi_c="$(new_repo multi_c main)"
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_c" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "有一個站在預設分支上就整體不放行" \
  || bad "有一個站在預設分支上卻放行了：$OUT"

# 其中一個根本不是 repo，或處在 detached HEAD——都是「量不到」，而量不到不是通過。
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$WORK/not-a-repo-at-all" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "其中一個不是 git repo 就整體不放行" \
  || bad "其中一個不是 git repo 卻放行了：$OUT"

multi_d="$(new_repo multi_d main)"; git -C "$multi_d" checkout -q --detach
RC=0; OUT="$(bash "$CHECK" "$multi_a" "$multi_d" 2>&1)" || RC=$?
[[ "$RC" -ne 0 ]] && ok "其中一個是 detached HEAD 就整體不放行" \
  || bad "其中一個是 detached HEAD 卻放行了：$OUT"

# 一個地方都沒被指名時要說「量不到」，不得改用「我現在站在哪」當答案。退回 pwd 的那一版
# 對「單住在 A、程式碼落在 B」的單永遠在判 A，而 A 幾乎總是通過。
RC=0; OUT="$(bash "$CHECK" 2>&1)" || RC=$?
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q '沒有任何地方被指名'; then
  ok "一個地方都沒被指名就回非 0，不從 cwd 猜"
else
  bad "沒有指名任何地方卻自己找了一個來判：rc=$RC $OUT"
fi

echo "check-swe-precondition selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
