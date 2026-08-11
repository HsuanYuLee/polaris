#!/usr/bin/env bash
# attach-pr-ticket.sh — 批次補上每個 PR 屬於哪一張單。
#
# Usage: echo '<pr_json>' | ./attach-pr-ticket.sh
# Input (stdin): 前一段的 JSON array，每筆要有 org / repo / number / title / head
# Output (stdout): 同一批 PR，每筆附加 ticket 欄位
# Progress (stderr): 每個 org 的答對數；**認不出來的逐筆指名**
#
# 附加欄位 ticket：
#   - {key, url}  認得出來的
#   - null        認不出來的
#
# **核心不認得任何一家公司的單號長什麼樣。** 它把「repo、編號、標題、分支名」交給認領那個
# org 的宣告，收回「哪幾個對應到哪張單」。所以換一家公司只要換那一行宣告，這支腳本不用動。
#
# 認不出來的那幾筆由這裡算差集並指名——宣告那一層只回答它答得出的，而「哪幾個沒答案」是
# 核心才知道的事（它知道自己送了哪幾筆進去）。一個安靜的 null 下一次就會被當成「這個 PR
# 本來就沒有單」，而真正的原因可能是那個 org 根本沒有人宣告。

set -euo pipefail

PREFIX="[attach-pr-ticket]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_CONTEXT="${SCRIPT_DIR}/resolve-pr-context.sh"

if [[ ! -x "$PR_CONTEXT" ]]; then
  echo "POLARIS_TOOL_MISSING:resolve-pr-context.sh (expected at ${PR_CONTEXT})" >&2
  exit 1
fi

SKILLS_ARGS=()

# --skills 原樣轉交給宣告解析器；selftest 用它指向一棵假的宣告樹，才量得到「宣告驅動」
# 本身，而不是順便量到某一家公司真的那一份宣告。空陣列在 bash 3.2 + set -u 下展開會炸，
# 所以取值一律用 ${SKILLS_ARGS[@]+...} 這個安全形式。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills) SKILLS_ARGS=(--skills "${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "${PREFIX} 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

prs="$(cat)"
total="$(printf '%s' "$prs" | jq 'length')"

if [[ "$total" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

echo "🎫 查 ${total} 個 PR 屬於哪張單..." >&2

answers="$(mktemp)"
trap 'rm -f "$answers"' EXIT
: > "$answers"

for org in $(printf '%s' "$prs" | jq -r '[.[].org] | map(select(. != null)) | unique | .[]'); do
  batch="$(printf '%s' "$prs" | jq -r --arg org "$org" \
    '.[] | select(.org == $org) | [.repo, (.number|tostring), .title, (.head // "")] | @tsv')"

  # 宣告答不出來時不讓整批停下來：那個 org 的每一筆會落成 null，並在下面被逐筆指名。
  if org_answers="$(printf '%s\n' "$batch" | "$PR_CONTEXT" ticket --org "$org" ${SKILLS_ARGS[@]+"${SKILLS_ARGS[@]}"})"; then
    printf '%s\n' "$org_answers" >> "$answers"
  else
    echo "  ⚠️ ${org} 答不出單號——這個 org 的 PR 會是 null，不是「沒有單」。" >&2
  fi
done

# TSV 轉成 "repo#number" → {key,url} 的查表。核心自己組這個形狀，宣告那一層不必認得它。
lookup="$(jq -R -s '
  split("\n") | map(select(length > 0) | split("\t")) | map(select(length >= 4))
  | map({key: (.[0] + "#" + .[1]), value: {key: .[2], url: .[3]}}) | from_entries
' "$answers")"

printf '%s' "$prs" | jq --argjson lookup "$lookup" \
  'map(. + {ticket: ($lookup[(.repo + "#" + (.number|tostring))] // null)})'

resolved="$(printf '%s' "$lookup" | jq 'length')"
echo "✅ 認得出單號的：${resolved}/${total}" >&2

if [[ "$resolved" -lt "$total" ]]; then
  echo "${PREFIX} 查不出屬於哪張單的：" >&2
  printf '%s' "$prs" | jq -r --argjson lookup "$lookup" \
    '.[] | select($lookup[(.repo + "#" + (.number|tostring))] == null)
     | "  \(.repo) #\(.number) — \(.title)"' >&2
fi
