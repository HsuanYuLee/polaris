#!/usr/bin/env bash
# merge-candidates.sh — 兩條 discovery 路徑的 candidates 取聯集。
#
# 用法（source 進來，不要執行）：
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/merge-candidates.sh"
#   merge_candidate_arrays '<這條路徑的 JSON 陣列>' <另一條路徑的檔案> [<這條的顆數>]
#
# 輸出（stdout）：合併後的 JSON 陣列，照 created_at 排序。
# 離場碼：0 合併好了／1 另一條那個檔讀不到或不是 JSON 陣列。
#
# **同一個 url 在兩邊都有時，合併的是欄位，不是挑一整列留下。** 挑一列的寫法
# （`unique_by(.url)`）保留的是輸入順序的第一列——而每一條路徑都固定把自己掃出來的那一列
# 放在前面，那一列常常還沒補上 review_status，於是欄位比較多的另一列每次都輸。下游
# build-review-prompt.sh 讀 review_status 讀不到就中斷，整批 packet 從那一顆起停掉。
#
# 每一個鍵取「兩邊非空的值排序後的第一個」：非空優先，所以少一邊沒填不會蓋掉有填的；
# 排序後取第一個，所以兩邊值不同時結果由值本身決定，不由誰先進陣列決定。兩邊都是空的
# 就照樣留那個空值，不要換成 null。
#
# **這一份是共用的，不是副本。** 這段判斷有兩個呼叫端（scan-my-stale-reviews.sh 與
# scan-unreviewed-prs.sh），而抄成兩份的話它們會漂——漂掉的那一刻，兩條路徑對同一顆 PR
# 給出不同的欄位，而沒有東西會說它們不一樣。

merge_candidate_arrays() {
  local mine="$1" other_file="$2" mine_count="${3:-}"

  if [[ ! -r "$other_file" ]]; then
    echo "ERROR: --merge-with 指的檔案讀不到：${other_file}" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' "$other_file" >/dev/null 2>&1; then
    echo "ERROR: --merge-with 指的檔案不是一個 JSON 陣列：${other_file}" >&2
    return 1
  fi

  local other_count
  other_count="$(jq 'length' "$other_file")"

  printf '%s' "$mine" | jq -s --slurpfile other "$other_file" '
    add + $other[0]
    | group_by(.url)
    | map(
        (map(to_entries) | add)
        | group_by(.key)
        | map({
            key: .[0].key,
            value: (
              [.[].value] as $vs
              | ([$vs[] | select(. != null and . != "")] | unique) as $filled
              | if ($filled | length) > 0 then $filled[0] else ($vs | unique | .[0]) end
            )
          })
        | from_entries
      )
    | sort_by(.created_at)'

  echo "🔗 聯集：這條路徑 ${mine_count:-$(printf '%s' "$mine" | jq 'length')} 顆 ＋ 另一條 ${other_count} 顆，去重後如上" >&2
}
