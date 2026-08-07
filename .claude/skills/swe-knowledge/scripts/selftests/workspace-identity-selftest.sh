#!/usr/bin/env bash
# Purpose: 驗這個領域印出來的工作區身分，是「一個 repo 一行、帶得出是哪個 repo」，
#          而且任何一個求不出來就整體不印。
# Inputs:  mktemp 底下的 hermetic git repo。
# Outputs: PASS 當單一 repo 印一行、多個 repo 印多行、同名分支不塌成一個、
#          detached HEAD 與非 repo 一律非 0 且 stdout 空的。

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/workspace-identity.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: 造一個 hermetic repo，停在指名的分支上。
# Args: $1 = 目錄名（會成為身分的前半），$2 = 分支名
new_repo() {
  local path="$WORK/$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.email selftest@example.com
  git -C "$path" config user.name selftest
  echo x > "$path/f"
  git -C "$path" add -A
  git -C "$path" commit -qm first
  git -C "$path" checkout -q -b "$2"
  printf '%s' "$path"
}

echo "workspace-identity selftest"

alpha="$(new_repo alpha feat/one)"
beta="$(new_repo beta feat/two)"

out="$(bash "$SCRIPT" --repo "$alpha")" || fail "單一 repo 求不出身分"
[[ "$out" == "alpha:feat/one" ]] || fail "身分沒帶 repo 目錄名；得到：$out"
echo "  ok  一個 repo 印一行，帶得出是哪個 repo"

out="$(bash "$SCRIPT" --repo "$alpha" --repo "$beta")" || fail "多個 repo 求不出身分"
[[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" == "1" ]] \
  && [[ "$out" == "alpha:feat/one"$'\n'"beta:feat/two" ]] \
  || fail "多個 repo 沒有一個一行；得到：$out"
echo "  ok  --repo 給幾次就印幾行"

# 帶 repo 目錄名的理由：兩個 repo 上同名的分支到處都是。只印分支名的話，兩個地方會塌成
# 集合裡的同一個成員，而「這張單涵蓋兩個地方」與「涵蓋一個」就分不出來。
same_a="$(new_repo same-a main-line)"
same_b="$(new_repo same-b main-line)"
out="$(bash "$SCRIPT" --repo "$same_a" --repo "$same_b")" || fail "同名分支求不出身分"
[[ "$(printf '%s\n' "$out" | sort -u | wc -l | tr -d ' ')" == "2" ]] \
  || fail "同名分支塌成了同一個成員；得到：$out"
echo "  ok  兩個 repo 上同名的分支不塌成一個"

# 印一半比不印糟：核心會記下一個比實際涵蓋範圍小的集合，而它之後每次比對都自洽。
out="$(bash "$SCRIPT" --repo "$alpha" --repo "$WORK/not-a-repo" 2>/dev/null)" \
  && fail "其中一個不在 repo 裡卻回了 0"
[[ -z "$out" ]] || fail "其中一個求不出來卻印了另一個；得到：$out"
echo "  ok  任何一個求不出來就整體非 0，一行都不印"

git -C "$alpha" checkout -q --detach
out="$(bash "$SCRIPT" --repo "$alpha" 2>/dev/null)" && fail "detached HEAD 卻回了 0"
[[ -z "$out" ]] || fail "detached HEAD 卻印了東西；得到：$out"
echo "  ok  detached HEAD 求不出來，stdout 保持空的"

# DP-482：要量哪些地方是被告知的。沒被指名時量 pwd 的那一版，對「單住在 A、程式碼落在 B」
# 的單永遠記下 A，而之後每一次比對都拿 A 跟 A 比、永遠自洽。
beta_only="$(new_repo gamma feat/three)"
out="$(cd "$beta_only" && bash "$SCRIPT" 2>/dev/null)" && fail "一個地方都沒被指名卻回了 0"
[[ -z "$out" ]] || fail "沒被指名卻量了 cwd；得到：$out"
echo "  ok  一個地方都沒被指名就不量，也不從 cwd 猜"

# 核心把宣告的那一組原樣接在宣告的命令後面，所以位置參數要跟 --repo 等價——核心不認得
# 這支腳本用什麼旗標收，它只是把當初被告知的那一組還回去。
out="$(cd / && bash "$SCRIPT" "$beta_only")" || fail "位置參數求不出身分"
[[ "$out" == "gamma:feat/three" ]] || fail "位置參數的結果跟 --repo 不一致；得到：$out"
echo "  ok  位置參數與 --repo 等價，而且結果不受 cwd 影響"

echo "PASS: workspace-identity"
