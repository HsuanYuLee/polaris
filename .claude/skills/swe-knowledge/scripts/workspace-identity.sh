#!/usr/bin/env bash
# workspace-identity.sh — 軟體工程的工作，「這個工作區現在是誰」印在 stdout。
#
# 印出來的是 `<repo 目錄名>:<分支名>`，**一個 repo 一行**。核心拿到的是一組不透明字串，
# 它不知道那是分支——比對相不相等不需要知道。所以換一個領域只要換這支腳本印什麼，核心
# 一行都不用動。
#
# 為什麼要帶 repo 目錄名：一件工作牽涉多個 repo 是這條開發鏈的前提，而兩個 repo 上同名的
# 分支（`main`、`develop`）到處都是。只印分支名的話，兩個地方會塌成集合裡的同一個成員，
# 而「這張單涵蓋兩個地方」與「涵蓋一個」就分不出來了。
#
# 為什麼要記下來再比對，而不是每次重跑一次開工條件：開工條件問的是「有沒有站在預設分支
# 上」，那是一個對所有單都一樣的判準，切到**另一張單**的分支照樣通過。2026-08-03 記下的
# 事故是兩個 session 互搶同一個 checkout，commit 落到別人的 feature 分支——那個情境下
# 開工條件全綠。要抓得到它，被比對的必須是**這張單自己**當初記下的值。
#
# Usage: workspace-identity.sh [--repo <path>]...   （--repo 可以給很多次）
# Exit:  0 每個 repo 印一行身分 / 2 任何一個求不出來（訊息進 stderr，stdout 保持空的）
#
# 任何一個求不出來就整體非 0，一行都不印。印一半的話，核心會記下一個比實際涵蓋範圍小的
# 集合，而那個集合之後每次比對都自洽——一個少了成員卻永遠回「一致」的比對，比沒有比對糟。

set -uo pipefail

PREFIX="[swe-workspace-identity]"
REPO_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATHS+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ ${#REPO_PATHS[@]} -gt 0 ]] || REPO_PATHS=("$(pwd)")

LINES=()
for REPO_PATH in "${REPO_PATHS[@]}"; do
  TOPLEVEL="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "$PREFIX 求不出身分：${REPO_PATH} 不在 git repo 裡。" >&2
    exit 2
  }

  NAME="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$NAME" || "$NAME" == "HEAD" ]]; then
    echo "$PREFIX 求不出身分：${TOPLEVEL} 現在是 detached HEAD，沒有名字可以記。" >&2
    echo "$PREFIX 求不出來不等於沒漂掉——這裡不印任何東西給人當成一致。" >&2
    exit 2
  fi

  LINES+=("$(basename "$TOPLEVEL"):$NAME")
done

printf '%s\n' "${LINES[@]}"
