#!/usr/bin/env bash
# Purpose: 證明釋出自己記帳——寫完釋出紀錄的那一刻，那張單的位置就已經是對的，不需要等
#          任何其他單跑任何東西。
# Inputs:  mktemp 底下一棵只有一張單的假單樹。函式取自 spine-release.sh 本人，不抄第二份。
# Outputs: PASS 當「一張單自己就搬到 released/{今天}/」成立，而且**拿掉重算那一行之後它
#          真的不會搬**。
#
# 為什麼只取那兩個函式：這支腳本的 execute 路徑會碰 remote、template checkout 與 GitHub
# API，`spine-release-selftest.sh` 的檔頭已經把它畫在範圍外，理由今天依然成立。所以這裡量
# 的是「寫紀錄那一步自己會不會重算」，而「尾段真的會呼叫它」由 DP-508 自己那次釋出實跑
# 觀察——那是一次 dogfood 觀察，不是這支測出來的，兩者不混為一談。
#
# 取的方式是把真的那份文字 eval 進來，不是照著寫一份。抄第二份的話，這支會對著自己的副本
# 永遠是綠的，而那正是它要擋的東西。函式不見了就當量不到——不是通過。

set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SPINE_RELEASE="$ROOT_DIR/scripts/spine-release.sh"
PLACER_SRC="$(cd "$(dirname "$0")/../../../driving-work-to-done/scripts" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
unmeasurable() { echo "UNMEASURABLE: $*" >&2; exit 2; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# Description: 從 spine-release.sh 取出寫紀錄與重算那兩個函式的原文。
# Args: 無
# Prints: 兩個函式的定義
extract() {
  sed -n '/^write_release_record() {/,/^}/p;/^reproject_position() {/,/^}/p' "$SPINE_RELEASE"
}

# Description: 造一棵只有一張單的假單樹，回傳它的 repo 根。
# Args: $1 = 名字
new_tree() {
  local repo="$WORK/$1"
  mkdir -p "$repo/issues/framework/done/T-1/.spine"
  mkdir -p "$repo/.claude/skills/driving-work-to-done"
  cp -R "$PLACER_SRC" "$repo/.claude/skills/driving-work-to-done/scripts"
  printf '{"schema_version":2,"station":"verify-ac","status":"converged","rounds":[],"stops":[],"stop":null,"knowledge_pack":{"pack":"swe-knowledge"}}\n' \
    > "$repo/issues/framework/done/T-1/.spine/loop-state.json"
  printf '%s' "$repo"
}

# Description: 在一棵樹上跑寫紀錄那一步。$1 = 樹根，$2 = 要 eval 的函式原文。
land() {
  ( set -uo pipefail
    REPO_PATH="$1"; ISSUE_DIR="issues/framework/done/T-1"
    DESTINATION="workspace"; HEAD_SHA="0000000000000000000000000000000000000000"
    note() { echo "note: $*"; }
    eval "$2"
    declare -f write_release_record >/dev/null || exit 90
    declare -f reproject_position >/dev/null || exit 91
    write_release_record 4.27.2 ) 2>&1
}

echo "spine-release reprojects selftest"

SRC="$(extract)"
grep -q '^write_release_record() {' <<<"$SRC" \
  || unmeasurable "取不到 write_release_record——它被改名或搬走了，這支什麼都沒量到"
grep -q '^reproject_position() {' <<<"$SRC" \
  || unmeasurable "取不到 reproject_position——這支什麼都沒量到"

TODAY="$(date -u +%Y-%m-%d)"

# 一、一張單自己就走到位。樹裡只有它，所以位置對不對不可能是別人順手擺正的。
tree="$(new_tree solo)"
out="$(land "$tree" "$SRC")" || fail "寫釋出紀錄那一步失敗了：$out"
[[ -f "$tree/issues/framework/released/$TODAY/T-1/.spine/release.json" ]] \
  || fail "紀錄寫了，但單還沒到 released/${TODAY}/：$(find "$tree/issues" -name release.json)"$'\n'"$out"
ok "寫完釋出紀錄，這張單自己就在 released/${TODAY}/——樹裡沒有別人可以替它記帳"

# 二、紅控。拿掉重算那一行，同一套 fixture 必須留在原地——不然上面那一格綠得沒有意義：
# 一個從來沒有重算過的環境，跟一個重算過的環境，在「位置是對的」這件事上可以長得一樣。
tree="$(new_tree neutered)"
NEUTERED="$(grep -v '^  reproject_position$' <<<"$SRC")"
grep -q '^  reproject_position$' <<<"$SRC" \
  || unmeasurable "紅控沒有拿掉任何東西——呼叫那一行的樣子變了，這一格沒有意義"
out="$(land "$tree" "$NEUTERED")" || fail "紅控那一趟不該整個失敗：$out"
[[ -f "$tree/issues/framework/done/T-1/.spine/release.json" ]] \
  || fail "紅控應該仍然寫得下紀錄，只是不重算：$out"
[[ -d "$tree/issues/framework/released" ]] \
  && fail "拿掉重算之後它還是搬了——那表示搬動不是這一行做的，這支量的東西不對"
ok "拿掉重算那一行，同一張單就停在 done/——上面那一格量到的是它"

echo "PASS: spine-release reprojects（$PASS 項）"
