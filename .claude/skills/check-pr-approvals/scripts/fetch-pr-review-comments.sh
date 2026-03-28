#!/usr/bin/env bash
# fetch-pr-review-comments.sh — 批次取得 PR 的未回覆 actionable review comments
#
# Usage: echo '<pr_json>' | ./fetch-pr-review-comments.sh --author <username>
# Input (stdin): fetch-user-open-prs.sh 或 pipeline 上游的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 unaddressed_comments 欄位
# Progress (stderr): 檢查進度
#
# 過濾邏輯：
#   1. 保留所有 code review bot 的建議（Copilot、CodeRabbit 等）— 這些建議具參考價值
#   2. 只排除非 code review 的自動化訊息（changeset-bot、codecov-commenter 等）
#   3. 排除 PR author 自己的 comment
#   4. Inline comments: 用 thread 判斷 — thread 最後一則非 author → 未回覆
#   5. Review body comments: 非 author 的 review body（非空）且 author 之後無回覆
#
# 附加欄位：
#   - unaddressed_comments — 未回覆的 actionable comment 數量
#   - actionable_comments  — [{id, user, path, line, body, type}] 明細
#   - has_actionable       — 是否有需要處理的 comment
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username \
#     | ./fetch-pr-review-comments.sh --author your-username

set -euo pipefail

ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi
AUTHOR=""

# 非 code review 的自動化 bot — 這些只是通知訊息，不是 code review 建議
# Code review bot（Copilot、CodeRabbit 等）不在此列，其建議具參考價值應保留
# 可透過環境變數 SKIP_BOTS 覆蓋（逗號分隔）
SKIP_BOTS="${SKIP_BOTS:-changeset-bot,codecov-commenter}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) AUTHOR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$AUTHOR" ]; then
  echo "Error: --author is required" >&2
  exit 1
fi

# 讀取 stdin
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "💬 檢查 ${total} 個 PR 的 review comments..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

# 建立 skip bots 的 jq filter（提前計算一次）
skip_bots_jq=$(echo "$SKIP_BOTS" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(. != ""))')

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')

  count=$((count + 1))

  # ========== Part A: Inline review comments（thread-based 判斷）==========

  # 取得所有 inline review comments
  all_comments=$(gh api "repos/$ORG/$repo/pulls/$number/comments" \
    --paginate \
    --jq '[.[] | {id: .id, user: .user.login, path: .path, line: (.line // .original_line // 0), body: .body, in_reply_to_id: .in_reply_to_id, created_at: .created_at}]' 2>/dev/null || echo "[]")

  # 如果 paginate 返回多頁，jq 會輸出多個 array，需要合併
  all_comments=$(echo "$all_comments" | jq -s 'flatten')

  # Thread-based 判斷：找出「thread 中最後一則 comment 不是 author」的 top-level comment
  # 步驟：
  #   1. 找出所有 top-level comments（in_reply_to_id == null）
  #   2. 對每個 top-level，找出其所有 replies（in_reply_to_id == top-level id）
  #   3. 取 thread 中最後一則 comment（含 top-level 自身），看是否為 author
  #   4. 最後一則非 author → 檢查是否為 reviewer 確認回覆
  #   5. 確認回覆（含 "確認" + "✅" 或 "LGTM"）視為已解決
  inline_actionable=$(echo "$all_comments" | jq \
    --arg author "$AUTHOR" \
    --argjson skip_bots "$skip_bots_jq" \
    '
    # 確認回覆偵測：reviewer 回覆含 "確認" 且含 "✅"，或含 "LGTM"
    def is_confirmation:
      (.body | ascii_downcase) as $b |
      (($b | contains("確認")) and ($b | contains("✅")))
      or ($b | contains("lgtm"));

    # 建立 top-level comments（非 author、非 skip bot）
    [.[] | select(.in_reply_to_id == null)] as $tops |
    # 所有 comments 供 thread lookup
    . as $all |
    [
      $tops[] |
      select(
        (.user != $author)
        and ((.user | IN($skip_bots[])) | not)
      ) |
      . as $top |
      # 找出 thread 中所有 replies + top-level 自身，按時間排序取最後一則
      ([$top] + [$all[] | select(.in_reply_to_id == $top.id)]) |
      sort_by(.created_at) |
      last |
      # 最後一則非 author 且不是確認回覆 → 此 thread 未被回覆
      select((.user != $author) and (is_confirmation | not)) |
      # 回傳 top-level comment 的資訊
      $top |
      {id: .id, user: .user, path: .path, line: .line, body: (.body | .[0:200]), type: "inline"}
    ]')

  # ========== Part B: Review body comments ==========

  # 取得所有 reviews（含 body）
  all_reviews=$(gh api "repos/$ORG/$repo/pulls/$number/reviews" \
    --paginate \
    --jq '[.[] | {id: .id, user: .user.login, body: .body, state: .state, submitted_at: .submitted_at}]' 2>/dev/null || echo "[]")

  all_reviews=$(echo "$all_reviews" | jq -s 'flatten')

  # 找出非 author、非 skip bot、有 body 的 review（排除 APPROVED 狀態）
  # APPROVED review body 是 reviewer 給出的 approval 結論，不需要 author 回覆
  # 然後檢查 author 是否在該 review 之後有任何回覆（review body 或 inline comment）
  review_actionable=$(echo "$all_reviews" | jq \
    --arg author "$AUTHOR" \
    --argjson skip_bots "$skip_bots_jq" \
    --argjson all_comments "$all_comments" \
    '
    . as $reviews |
    # Author 的所有活動時間點（review submissions + inline comments）
    ([$reviews[] | select(.user == $author) | .submitted_at] +
     [$all_comments[] | select(.user == $author) | .created_at]) as $author_timestamps |
    [
      .[] |
      select(
        (.user != $author)
        and ((.user | IN($skip_bots[])) | not)
        and (.state != "APPROVED")
        and (.body != null)
        and (.body != "")
        and ((.body | length) > 0)
      ) |
      . as $review |
      # 檢查 author 是否在此 review 之後有任何活動
      [$author_timestamps[] | select(. > $review.submitted_at)] |
      # 沒有後續 author 活動 → 未回覆
      select(length == 0) |
      $review |
      {id: .id, user: .user, path: "", line: 0, body: (.body | .[0:200]), type: "review_body"}
    ]')

  # ========== 合併 Part A + Part B ==========

  actionable=$(jq -n \
    --argjson inline "$inline_actionable" \
    --argjson reviews "$review_actionable" \
    '$inline + $reviews')

  unaddressed_count=$(echo "$actionable" | jq 'length')
  has_actionable=false
  if [ "$unaddressed_count" -gt 0 ]; then
    has_actionable=true
  fi

  # 保留原本的欄位，附加新欄位
  original=$(echo "$row" | base64 --decode)
  enriched=$(echo "$original" | jq \
    --argjson unaddressed_comments "$unaddressed_count" \
    --argjson actionable_comments "$actionable" \
    --argjson has_actionable "$has_actionable" \
    '. + {unaddressed_comments: $unaddressed_comments, actionable_comments: $actionable_comments, has_actionable: $has_actionable}')

  echo "$enriched" >> "$tmpfile"

  if [ "$has_actionable" = true ]; then
    echo "  [$count/$total] $repo #$number — $unaddressed_count 則未回覆 comment" >&2
  else
    echo "  [$count/$total] $repo #$number — 無未回覆 comment ✅" >&2
  fi
done

results=$(jq -s '.' "$tmpfile")
echo "$results"

actionable_prs=$(echo "$results" | jq '[.[] | select(.has_actionable == true)] | length')
echo "✅ 完成：$actionable_prs 個 PR 有未回覆的 actionable comments" >&2
