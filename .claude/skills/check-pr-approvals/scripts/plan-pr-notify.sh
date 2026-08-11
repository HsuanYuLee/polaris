#!/usr/bin/env bash
# plan-pr-notify.sh — 這批 PR 各自該通知哪裡，逐個 repo 給出建議。
#
# Usage: echo '<pr_json>' | ./plan-pr-notify.sh
# Input (stdin): PR JSON array（通常是使用者選中的那些），每筆要有 org / repo
# Output (stdout): 一行一個 repo，"repo⇥狀態⇥這個 repo 有幾個 PR⇥目的地"
#                  狀態 known → 目的地是宣告那一層給的答案，**原樣轉交**
#                  狀態 unknown → 目的地欄不存在
# Progress (stderr): 逐個 repo 的建議；問不到的連同「要人給什麼」一起說出來
# Exit: 0 全部問得到 / 4 有 repo 問不到（其餘照常，不是失敗）
#
# 目的地排在最後一欄，因為它對核心是不透明的：宣告那一層想印什麼格式都可以，而現行的宣告
# 真的回了一個含 tab 的值。把一個形狀未知的東西放在中間，讀的人就得先知道它有幾欄。
#
# **問不到不是錯誤，是一個要人回答的問題。** 所以退出碼跟「壞掉」分開：4 的意思是
# 「我答完我答得出的，剩下這幾個要你給」，呼叫端該去問人，不是該中止。
#
# 這一步在送出之前跑，讓人先看到「要送去哪」再決定送不送——目的地是通知的一半，一個沒被
# 看過的目的地跟沒選過一樣。

set -euo pipefail

PREFIX="[plan-pr-notify]"
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
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "${PREFIX} 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

prs="$(cat)"
total="$(printf '%s' "$prs" | jq 'length')"

if [[ "$total" -eq 0 ]]; then
  echo "${PREFIX} 沒有 PR，沒有要通知的地方。" >&2
  exit 0
fi

unknown_count=0
why="$(mktemp)"
trap 'rm -f "$why"' EXIT

# 逐個 (org, repo) 問一次，不是逐個 PR：同一個 repo 的 PR 送去同一個地方，問 N 次只會讓
# 同一個答案出現 N 遍。
while IFS=$'\t' read -r org repo count; do
  [[ -n "$repo" ]] || continue

  if [[ -z "$org" || "$org" == "null" ]]; then
    printf '%s\tunknown\t%s\n' "$repo" "$count"
    echo "  ❓ ${repo}（${count} 個）— 這批 PR 沒有 org，問不到該通知誰。" >&2
    unknown_count=$((unknown_count + 1))
    continue
  fi

  # 一次呼叫同時拿走答案與說明：問兩次是同一個問題問兩遍，而兩遍的答案可以不一樣。
  # 宣告那一層的說明（缺什麼、怎麼補）原樣留給人看，核心不重寫它——重寫就是第二份說明。
  if destination="$("$PR_CONTEXT" notify --org "$org" --repo "$repo" ${SKILLS_ARGS[@]+"${SKILLS_ARGS[@]}"} 2>"$why")"; then
    printf '%s\tknown\t%s\t%s\n' "$repo" "$count" "$destination"
    echo "  ✅ ${repo}（${count} 個）→ ${destination}" >&2
  else
    printf '%s\tunknown\t%s\n' "$repo" "$count"
    unknown_count=$((unknown_count + 1))
    echo "  ❓ ${repo}（${count} 個）— 不知道要通知誰。" >&2
    [[ ! -s "$why" ]] || sed 's/^/     /' "$why" >&2
  fi
done < <(printf '%s' "$prs" | jq -r '
  group_by(.org + "/" + .repo) | .[] | [.[0].org, .[0].repo, (length|tostring)] | @tsv')

if [[ "$unknown_count" -gt 0 ]]; then
  echo "${PREFIX} 有 ${unknown_count} 個 repo 不知道要通知哪裡——問使用者要一個目的地。" >&2
  echo "${PREFIX} **不要猜一個，也不要沿用別的 repo 的**。拿到之後照宣告那一層說的方式記下來，" >&2
  echo "${PREFIX} 不然下一次還會再問一次同樣的問題。" >&2
  exit 4
fi
