#!/usr/bin/env bash
# fetch-pr-review-comments.sh — 取得 PR review comments 並過濾出需要處理的
#
# Usage: ./fetch-pr-review-comments.sh <owner/repo> <pr_number> [--my-user <username>]
# Output (stdout): JSON object with filtered comments and CI status
# Progress (stderr): 取得進度
#
# 過濾邏輯：
#   Inline comments:
#     1. 排除自己留的 comment
#     2. 排除非 code review 的 bot（changeset-bot、codecov-commenter、your-bot-account）
#     3. Thread-based 判斷：thread 最後一則 comment 是 author → 已回覆
#     4. Reviewer 確認回覆（含 "確認" + "✅" 或 "LGTM"）視為已解決
#   Review summaries:
#     1. 排除自己的 review
#     2. 排除 APPROVED 狀態（approval 是結論，不需回覆）
#     3. 排除 author 之後有活動的 review（已回覆）
#   Issue comments:
#     1. 排除 Bot（保留 changeset-bot）
#     2. 排除自己的留言
#
# 輸出欄位：
#   - comments         — 需要處理的 inline review comments
#   - all_comments     — 完整原始 inline comments（thread 追溯用）
#   - review_summaries — 需要處理的 review-level body comments
#   - all_reviews      — 完整原始 reviews（含已處理的）
#   - issue_comments   — 需要處理的 issue comments
#   - ci_checks        — CI check 狀態
#   - stats            — 統計資訊
#
# Example:
#   ./fetch-pr-review-comments.sh your-org/your-app 1920
#   ./fetch-pr-review-comments.sh your-org/your-app 1920 --my-user your-username

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo> <pr_number> [--my-user <username>]}"
PR_NUMBER="${2:?Usage: $0 <owner/repo> <pr_number> [--my-user <username>]}"
shift 2

MY_USER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 如果未指定 user，自動取得
if [ -z "$MY_USER" ]; then
  MY_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
fi

echo "📋 取得 $REPO #$PR_NUMBER review comments..." >&2

# Step 1: PR metadata (base/head branch)
pr_info=$(gh api "repos/$REPO/pulls/$PR_NUMBER" \
  --jq '{base: .base.ref, head: .head.ref, title: .title, author: .user.login}' 2>/dev/null || echo '{}')

base=$(echo "$pr_info" | jq -r '.base // ""')
head=$(echo "$pr_info" | jq -r '.head // ""')
pr_title=$(echo "$pr_info" | jq -r '.title // ""')
pr_author=$(echo "$pr_info" | jq -r '.author // ""')

# Step 2: Inline review comments
echo "  取得 inline comments..." >&2
raw_comments=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate \
  --jq '[.[] | {
    id: .id,
    path: .path,
    line: .line,
    original_line: .original_line,
    body: .body,
    user: .user.login,
    in_reply_to_id: .in_reply_to_id,
    created_at: .created_at,
    updated_at: .updated_at
  }]' 2>/dev/null || echo "[]")

# 如果 paginate 返回多頁，jq 會輸出多個 array，需要合併
raw_comments=$(echo "$raw_comments" | jq -s 'flatten')

total_comments=$(echo "$raw_comments" | jq 'length')
echo "  📝 共 $total_comments 個 inline comments" >&2

# Step 3: Thread-based 過濾 inline comments
# 找出「thread 中最後一則 comment 不是 author 且不是確認回覆」的 top-level comment
# 非 code review 的 bot 排除（可透過環境變數 SKIP_BOTS 覆蓋，逗號分隔）
SKIP_BOTS="${SKIP_BOTS:-changeset-bot,codecov-commenter}"
skip_bots_jq=$(echo "$SKIP_BOTS" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(. != ""))')

filtered_comments=$(echo "$raw_comments" | jq \
  --arg my_user "$MY_USER" \
  --argjson skip_bots "$skip_bots_jq" \
  '
  # 確認回覆偵測：reviewer 回覆含 "確認" 且含 "✅"，或含 "LGTM"
  def is_confirmation:
    (.body | ascii_downcase) as $b |
    (($b | contains("確認")) and ($b | contains("✅")))
    or ($b | contains("lgtm"));

  # 建立 top-level comments（非 author、非 skip bot）
  [.[] | select(.in_reply_to_id == null)] as $tops |
  . as $all |
  [
    $tops[] |
    select(
      (.user != $my_user)
      and ((.user | IN($skip_bots[])) | not)
    ) |
    . as $top |
    # 找出 thread 中所有 replies + top-level 自身，按時間排序取最後一則
    ([$top] + [$all[] | select(.in_reply_to_id == $top.id)]) |
    sort_by(.created_at) |
    last |
    # 最後一則非 author 且不是確認回覆 → 此 thread 未被回覆
    select((.user != $my_user) and (is_confirmation | not)) |
    # 回傳 top-level comment 的資訊
    $top
  ]')

filtered_count=$(echo "$filtered_comments" | jq 'length')
echo "  🎯 過濾後 $filtered_count 個 inline comment 需要處理" >&2

# Step 4: Review-level comments（review body）
echo "  取得 review summaries..." >&2
raw_reviews=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
  --jq '[.[] | {
    id: .id,
    user: .user.login,
    state: .state,
    body: .body,
    submitted_at: .submitted_at
  }]' 2>/dev/null || echo "[]")

raw_reviews=$(echo "$raw_reviews" | jq -s 'flatten')

# 過濾 review summaries：
#   - 排除自己的 review
#   - 排除 APPROVED 狀態（approval 是結論，不需要回覆）
#   - 排除空 body
#   - 排除 author 之後有活動的 review（已回覆）
review_summaries=$(echo "$raw_reviews" | jq \
  --arg my_user "$MY_USER" \
  --argjson all_comments "$raw_comments" \
  '
  . as $reviews |
  # Author 的所有活動時間點（review submissions + inline comments）
  ([$reviews[] | select(.user == $my_user) | .submitted_at] +
   [$all_comments[] | select(.user == $my_user) | .created_at]) as $author_timestamps |
  [
    .[] |
    select(
      (.user != $my_user)
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
    $review
  ]')

review_summary_count=$(echo "$review_summaries" | jq 'length')
echo "  📝 review summaries: $review_summary_count 個需要處理" >&2

# Step 4b: Issue comments（PR 一般留言，非 inline review comments）
echo "  取得 issue comments..." >&2
raw_issue_comments=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq '[.[] | {
    id: .id,
    body: .body,
    user: .user.login,
    user_type: .user.type,
    created_at: .created_at,
    updated_at: .updated_at
  }]' 2>/dev/null || echo "[]")

raw_issue_comments=$(echo "$raw_issue_comments" | jq -s 'flatten')

# 過濾 issue comments：排除非 actionable bot 帳號和自己的留言
# 保留 changeset-bot（其警告視為 CI 層面問題，由 Step 6h 處理）
issue_comments=$(echo "$raw_issue_comments" | jq --arg my_user "$MY_USER" \
  '[.[] | select(
    (.user_type != "Bot" or (.user | test("changeset")))
    and .user != $my_user
  )]')

issue_comment_count=$(echo "$issue_comments" | jq 'length')
echo "  📝 issue comments: $issue_comment_count 個（排除 bot 和自己）" >&2

# Step 5: CI checks 狀態
echo "  取得 CI checks 狀態..." >&2
ci_checks=$(gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state,description 2>/dev/null || echo "[]")

ci_failed=$(echo "$ci_checks" | jq '[.[] | select(.state == "FAILURE")] | length')
ci_passed=$(echo "$ci_checks" | jq '[.[] | select(.state == "SUCCESS")] | length')
ci_pending=$(echo "$ci_checks" | jq '[.[] | select(.state != "SUCCESS" and .state != "FAILURE")] | length')

echo "  🔧 CI: $ci_passed passed, $ci_failed failed, $ci_pending pending" >&2

# 組裝結果
result=$(jq -n \
  --arg repo "$REPO" \
  --argjson number "$PR_NUMBER" \
  --arg title "$pr_title" \
  --arg author "$pr_author" \
  --arg base "$base" \
  --arg head "$head" \
  --argjson comments "$filtered_comments" \
  --argjson all_comments "$raw_comments" \
  --argjson review_summaries "$review_summaries" \
  --argjson all_reviews "$raw_reviews" \
  --argjson issue_comments "$issue_comments" \
  --argjson ci_checks "$ci_checks" \
  --argjson stats "$(jq -n \
    --argjson total "$total_comments" \
    --argjson filtered "$filtered_count" \
    --argjson review_summary "$review_summary_count" \
    --argjson issue "$issue_comment_count" \
    --argjson ci_failed "$ci_failed" \
    --argjson ci_passed "$ci_passed" \
    --argjson ci_pending "$ci_pending" \
    '{total_comments: $total, actionable_comments: $filtered, actionable_review_summaries: $review_summary, issue_comments: $issue, ci_failed: $ci_failed, ci_passed: $ci_passed, ci_pending: $ci_pending}')" \
  '{
    repo: $repo,
    number: $number,
    title: $title,
    author: $author,
    base: $base,
    head: $head,
    comments: $comments,
    all_comments: $all_comments,
    review_summaries: $review_summaries,
    all_reviews: $all_reviews,
    issue_comments: $issue_comments,
    ci_checks: $ci_checks,
    stats: $stats
  }')

echo "$result"
echo "✅ 完成：$filtered_count 個 inline comment + $review_summary_count 個 review summary 待處理，$issue_comment_count 個 issue comment，$ci_failed 個 CI 失敗" >&2
