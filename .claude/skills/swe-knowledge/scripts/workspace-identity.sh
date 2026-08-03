#!/usr/bin/env bash
# workspace-identity.sh — 軟體工程的工作，「這個工作區現在是誰」印在 stdout。
#
# 印出來的是分支名。核心拿到的是一個不透明字串，它不知道那是分支——比對相不相等不需要
# 知道。所以換一個領域只要換這支腳本印什麼，核心一行都不用動。
#
# 為什麼要記下來再比對，而不是每次重跑一次開工條件：開工條件問的是「有沒有站在預設分支
# 上」，那是一個對所有單都一樣的判準，切到**另一張單**的分支照樣通過。2026-08-03 記下的
# 事故是兩個 session 互搶同一個 checkout，commit 落到別人的 feature 分支——那個情境下
# 開工條件全綠。要抓得到它，被比對的必須是**這張單自己**當初記下的值。
#
# Usage: workspace-identity.sh [--repo <path>]
# Exit:  0 印出身分 / 2 求不出來（訊息進 stderr，stdout 保持空的）

set -uo pipefail

PREFIX="[swe-workspace-identity]"
REPO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(pwd)"

TOPLEVEL="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PREFIX 求不出身分：${REPO_PATH} 不在 git repo 裡。" >&2
  exit 2
}

NAME="$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$NAME" || "$NAME" == "HEAD" ]]; then
  echo "$PREFIX 求不出身分：現在是 detached HEAD，沒有名字可以記。" >&2
  echo "$PREFIX 求不出來不等於沒漂掉——這裡不印任何東西給人當成一致。" >&2
  exit 2
fi

printf '%s\n' "$NAME"
