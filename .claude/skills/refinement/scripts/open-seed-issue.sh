#!/usr/bin/env bash
# open-seed-issue.sh — 開發途中長出來的東西，一個命令就有載體。
#
# 為什麼要有這一支：開發途中會問出、查出、撞出一些只有當下知道的東西。那個東西現在沒有
# 地方住——它要嘛被寫進一個進不了主線的角落，要嘛消失。而「開一張正式的單」在那個
# 當下太貴：assertion 還簽不出來，因為怎麼算成功還沒想清楚。
#
# 所以這一支只做一件事：把前因後果變成一張找得到的單，然後就結束。它**不**簽 assertion、
# **不**決定領域、**不**開 worktree、**不**碰你現在正在做的那張單。assertion 是下一個 session
# 在 refinement 的事，而那時候才有人真的想過怎麼算成功。
#
# Usage:
#   open-seed-issue.sh --issues <單的根目錄> --namespace <命名空間> --slug <名字> --note <前因後果>
#                      [--prefix <前綴>] [--no-commit]
#
# 號自己會算：`--slug the-thing` 開出來的是 `DP-488-the-thing`。號從哪裡來由那個命名空間
# 現有的東西決定，不需要另外宣告——細節見 next-ticket-number.sh 的檔頭。
# Exit:
#   0 開好了，印出單的路徑 / 2 參數不對或那張單已經在了

set -euo pipefail

PREFIX="[open-seed-issue]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_STATE="$SCRIPT_DIR/../../driving-work-to-done/scripts/spine-loop-state.sh"
NEXT_NUMBER="$SCRIPT_DIR/../../driving-work-to-done/scripts/next-ticket-number.sh"

ISSUES=""
NAMESPACE=""
SLUG=""
NOTE=""
COMMIT=1
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues) ISSUES="${2:-}"; shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --no-commit) COMMIT=0; shift ;;
    --prefix) PREFIX_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

for pair in "--issues:$ISSUES" "--namespace:$NAMESPACE" "--slug:$SLUG" "--note:$NOTE"; do
  if [[ -z "${pair#*:}" ]]; then
    echo "$PREFIX 缺 ${pair%%:*}。" >&2
    echo "  用法：open-seed-issue.sh --issues <單的根目錄> --namespace <命名空間> --slug <名字> --note <前因後果>" >&2
    exit 2
  fi
done

# 名字只吃這些字元：它會變成目錄名，而目錄名之後會被別的東西拿去接。
[[ "$SLUG" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
  # 訊息裡不用反引號：雙引號底下它是命令替換，而這一行正好在講一個不合法的輸入。
  echo "$PREFIX --slug 只能用字母、數字、連字號、底線、點，而且要從字母或數字開頭（收到「${SLUG}」）。" >&2
  exit 2
}

[[ -d "$ISSUES" ]] || { echo "$PREFIX 單的根目錄不存在：$ISSUES" >&2; exit 2; }
[[ -f "$LOOP_STATE" ]] || { echo "$PREFIX 找不到 $LOOP_STATE" >&2; exit 2; }
[[ -f "$NEXT_NUMBER" ]] || { echo "$PREFIX 找不到 $NEXT_NUMBER" >&2; exit 2; }

# 號在名字裡。沒有號的單排不進待辦、也沒有一個穩定的東西給別的單引用——而它會一直長出來，
# 到某次盤點才被發現。2026-08-08 就這樣一次找到五個。
number_args=(--issues "$ISSUES" --namespace "$NAMESPACE")
[[ -n "$PREFIX_OVERRIDE" ]] && number_args+=(--prefix "$PREFIX_OVERRIDE")
if ! NUMBER="$(bash "$NEXT_NUMBER" "${number_args[@]}")"; then
  # 那一支已經把原因與往下走的路印在 stderr 上了，不要在這裡改寫成另一句話。
  exit 2
fi
SLUG="${NUMBER}-${SLUG}"

# backlog 是「立案了，還沒開工」，而一張種子單正是那個狀態。位置本來就是狀態的投影，
# 所以之後的重算會把它放回它該在的那一格——這裡只是給它一個合理的起點。
ISSUE_DIR="$ISSUES/$NAMESPACE/backlog/$SLUG"
[[ -e "$ISSUE_DIR" ]] && { echo "$PREFIX 那張單已經在了：$ISSUE_DIR" >&2; exit 2; }

mkdir -p "$ISSUE_DIR"

# frontmatter 只有 destination 一格是先填的，而且填的是最保守的那一個：一張還沒有人想過
# 的單不該預設它會被推到別人的 repo 去。計劃那四格與 assertion 都留白——它們要人回答，而這一支
# 存在的理由正是「現在還沒有人能回答」。填一個編出來的答案比空著糟：空著看得出來。
{
  printf -- '---\n'
  printf 'destination: workspace\n'
  printf -- '---\n\n'
  printf '# %s\n\n' "$SLUG"
  printf '## 前因後果\n\n'
  printf '%s\n\n' "$NOTE"
  printf '## 還沒有的東西\n\n'
  printf '這是一張種子單：它記下了一件不能消失的事，但還沒有人簽過「怎麼算成功」。\n\n'
  printf '接手的人從 `refinement` 開始——填計劃那四格、寫 assertion、算校驗值、開輪次。\n'
} > "$ISSUE_DIR/index.md"

bash "$LOOP_STATE" seed --state "$ISSUE_DIR/.spine/loop-state.json" --note "$NOTE" >/dev/null

if [[ "$COMMIT" -eq 1 ]]; then
  # 單的目錄樹是它自己的 git repo。沒 commit 的單只存在於這台機器上，而這一支的整個用途是
  # 「拿給另一個 session 開工」——另一個 session 讀的是 commit 過的那一份。
  if git -C "$ISSUES" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ISSUES" add "$NAMESPACE/backlog/$SLUG" >/dev/null
    git -C "$ISSUES" commit -q -m "seed: $NAMESPACE/$SLUG" -m "$NOTE"
  else
    echo "$PREFIX 單的目錄樹不是 git repo，這張單只留在磁碟上（沒有 commit）。" >&2
  fi
fi

echo "$PREFIX 開好了：$ISSUE_DIR"
echo "  接手的人：先走 refinement 簽 assertion，再 init 開輪次。"
