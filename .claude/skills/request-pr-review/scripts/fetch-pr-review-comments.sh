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
#   4. Inline comments: GitHub 上 resolve 了的 thread 算處理過；沒 resolve 的，作者回過、而開 thread
#      的 reviewer 在作者最後一則回覆之後交了 APPROVED 也算；其餘用 thread 判斷——最後一則非 author → 未回覆
#   5. Review body comments: 非 author 的 review body（非空、非 APPROVED），author 沒有回到它身上
#      ——回了這則 review 自己帶的逐行留言的 thread，或之後的 issue comment／review 本文 @ 了 reviewer
#   6. Issue comments: 交過 review 的人留的 issue comment，之後 author 沒有 @ 他回覆
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

# org 從每一筆 PR 自己帶的 `.org` 讀，不從環境變數——一批 PR 可以橫跨多個 org。
# 環境變數留作 fallback，給手工餵舊格式 JSON 的情況。
ORG_FALLBACK="${ORG:-}"
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
  org=$(_jq '.org')
  if [[ -z "$org" || "$org" == "null" ]]; then
    org="$ORG_FALLBACK"
  fi
  if [[ -z "$org" ]]; then
    echo "POLARIS_COMMENTS_NO_ORG: ${repo} #${number} 這一筆沒有 org，也沒有 ORG fallback" >&2
    exit 2
  fi

  count=$((count + 1))

  # ========== Part A: Inline review comments（thread-based 判斷）==========

  # 取得所有 reviews（含 body）
  all_reviews=$(gh api "repos/${org}/${repo}/pulls/${number}/reviews" \
    --paginate \
    --jq '[.[] | {id: .id, user: .user.login, body: .body, state: .state, submitted_at: .submitted_at}]' 2>/dev/null || echo "[]")

  all_reviews=$(echo "$all_reviews" | jq -s 'flatten')

  # 每個 thread 在 GitHub 上 resolve 了沒。REST 沒有這一格，只有 GraphQL 有；鍵是 thread 根留言的 id。
  # **問不到不得變成 0**：問不到就當全部沒 resolve 照算，並說出是哪一顆。
  resolved_roots=$(gh api graphql --paginate -F owner="$org" -F name="$repo" -F number="$number" -f query='
    query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        reviewThreads(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { isResolved comments(first: 1) { nodes { databaseId } } } } } } }' \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved) | .comments.nodes[0].databaseId]' 2>/dev/null) \
    || { echo "  ${repo} #${number}：thread 的 resolve 狀態問不到，這一顆的逐行留言全部當成沒 resolve 照算" >&2; resolved_roots="[]"; }
  resolved_roots=$(echo "$resolved_roots" | jq -s 'flatten')

  # 取得所有 inline review comments
  all_comments=$(gh api "repos/${org}/${repo}/pulls/${number}/comments" \
    --paginate \
    --jq '[.[] | {id: .id, user: .user.login, path: .path, line: (.line // .original_line // 0), body: .body, in_reply_to_id: .in_reply_to_id, review_id: .pull_request_review_id, created_at: .created_at}]' 2>/dev/null || echo "[]")

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
    --argjson resolved "$resolved_roots" \
    --argjson reviews "$all_reviews" \
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
      select((.id | IN($resolved[])) | not) |
      ([$all[] | select(.in_reply_to_id == $top.id and .user == $author) | .created_at] | max) as $last_author_reply |
      # 作者回過，而開 thread 的人在那之後核准了 → 同一個 thread 裡核准前後的話都算在核准底下
      select(($last_author_reply != null
              and ([$reviews[] | select(.user == $top.user and .state == "APPROVED"
                                        and .submitted_at > $last_author_reply)] | length > 0)) | not) |
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


  # PR 上的一般留言（issue comment）。它跟 review 本文一樣是頂層的話，作者回覆它也只能用頂層的話。
  all_issue_comments=$(gh api "repos/${org}/${repo}/issues/${number}/comments" \
    --paginate \
    --jq '[.[] | {id: .id, user: .user.login, user_type: .user.type, body: .body, created_at: .created_at}]' 2>/dev/null || echo "[]")
  all_issue_comments=$(echo "$all_issue_comments" | jq -s 'flatten')

  # 「作者回到了這一則上」只有兩種形狀，**不是「作者之後有任何活動」**：
  #   (a) 回了這則 review 自己帶的逐行留言的 thread（逐行留言帶著 review_id）
  #   (b) 之後的頂層發言（issue comment 或本文非空的 review）裡 @ 了那位 reviewer
  # 2026-10-16 的標本：一則沒有逐行留言的 review 本文，因為作者 80 分鐘後回了另一則 review 的
  # thread 就被算成回過，從那天起每次都回報 0。
  review_actionable=$(echo "$all_reviews" | jq \
    --arg author "$AUTHOR" \
    --argjson skip_bots "$skip_bots_jq" \
    --argjson all_comments "$all_comments" \
    --argjson issue_comments "$all_issue_comments" \
    '
    . as $reviews |
    ([$reviews[] | select(.user == $author and ((.body // "") != "")) | {at: .submitted_at, body: .body}] +
     [$issue_comments[] | select(.user == $author) | {at: .created_at, body: (.body // "")}]) as $author_top |
    def mentioned($who; $after): [$author_top[] | select(.at > $after and (.body | contains("@" + $who)))] | length > 0;
    ([$reviews[] | select(.user != $author) | .user] | unique) as $reviewers |
    [
      .[] |
      select(
        (.user != $author)
        and ((.user | IN($skip_bots[])) | not)
        and (.state != "APPROVED")
        and ((.body // "") != "")
      ) |
      . as $review |
      ([$all_comments[] | select(.review_id == $review.id and .in_reply_to_id == null) | .id]) as $own_roots |
      ([$all_comments[] | select(.user == $author and .created_at > $review.submitted_at
                                  and ((.in_reply_to_id // -1) | IN($own_roots[])))] | length > 0) as $thread_reply |
      select(($thread_reply or mentioned($review.user; $review.submitted_at)) | not) |
      {id: .id, user: .user, path: "", line: 0, body: (.body | .[0:200]), type: "review_body"}
    ] +
    [
      $issue_comments[] |
      select(
        (.user != $author)
        and (.user_type != "Bot")
        and ((.user | IN($skip_bots[])) | not)
        and (.user | IN($reviewers[]))
        and ((.body // "") != "")
      ) |
      select(mentioned(.user; .created_at) | not) |
      {id: .id, user: .user, path: "", line: 0, body: (.body | .[0:200]), type: "issue_comment"}
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
