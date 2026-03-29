#!/usr/bin/env bash
# check-my-review-status.sh — 批次檢查每個 PR 對指定 user 的 review 狀態
#
# Usage: echo '<pr_json>' | ./check-my-review-status.sh <github_username>
# Input (stdin): scan-need-review-prs.sh 的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 review_status 和 review_detail
#
# review_status 值：
#   - "needs_first_review"  — 從未 review 過
#   - "needs_re_approve"    — approve 後作者有新 commit（stale）
#   - "needs_re_review"     — REQUEST_CHANGES 後作者有回覆 review comments（不論有無新 push）
#   - "valid_approve"       — approve 仍有效，不需動作
#   - "waiting_for_author"  — REQUEST_CHANGES 後作者未回覆 review comments（即使有新 push 也視為還在改）
#
# Example:
#   ./scan-need-review-prs.sh --exclude-author your-github-user \
#     | ./check-my-review-status.sh your-github-user

set -euo pipefail

MY_USER="${1:?Usage: $0 <github_username>}"
ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi

# 檢查 PR 作者是否在指定時間後回覆了 review comments 或 issue comments
# 回傳 "true" 或 "false"
check_author_replied() {
  local repo=$1 number=$2 author=$3 after_time=$4

  # 檢查 review comments（inline on diff）from author after my review
  local review_replies
  review_replies=$(gh api "repos/$ORG/$repo/pulls/$number/comments" --paginate \
    --jq "[.[] | select(.user.login == \"$author\" and .created_at > \"$after_time\")] | length" 2>/dev/null || echo "0")

  # 檢查 issue comments（general PR comments）from author after my review
  local issue_replies
  issue_replies=$(gh api "repos/$ORG/$repo/issues/$number/comments" --paginate \
    --jq "[.[] | select(.user.login == \"$author\" and .created_at > \"$after_time\")] | length" 2>/dev/null || echo "0")

  if [ "$review_replies" -gt 0 ] || [ "$issue_replies" -gt 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# 讀取 stdin 的 PR JSON
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "🔎 檢查 ${total} 個 PR 的 review 狀態（user: ${MY_USER}）..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')
  title=$(_jq '.title')
  url=$(_jq '.url')
  author=$(_jq '.author')
  created_at=$(_jq '.created_at')

  count=$((count + 1))

  # 取得該 PR 所有 reviews
  reviews=$(gh api "repos/$ORG/$repo/pulls/$number/reviews" \
    --jq "[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}]" 2>/dev/null || echo "[]")

  # 找出自己的最新 review
  my_latest=$(echo "$reviews" | jq "[.[] | select(.user == \"$MY_USER\")] | sort_by(.submitted_at) | last // empty")

  if [ -z "$my_latest" ] || [ "$my_latest" = "null" ]; then
    # 從未 review
    status="needs_first_review"
    detail="首次 review"
  else
    my_state=$(echo "$my_latest" | jq -r '.state')
    my_time=$(echo "$my_latest" | jq -r '.submitted_at')

    # 取得最後 commit 時間
    last_commit_time=$(gh api "repos/$ORG/$repo/pulls/$number/commits" \
      --jq '.[-1].commit.committer.date' 2>/dev/null || echo "")

    if [ "$my_state" = "APPROVED" ]; then
      if [ -n "$last_commit_time" ] && [[ "$last_commit_time" > "$my_time" ]]; then
        status="needs_re_approve"
        detail="⚠️ 需 re-approve（approve: ${my_time%T*}, 最新 commit: ${last_commit_time%T*}）"
      else
        status="valid_approve"
        detail="✓ approve 有效"
      fi
    elif [ "$my_state" = "CHANGES_REQUESTED" ]; then
      # 判斷作者是否回覆了我的 review comments（比單純看 push 更準確）
      author_replied=$(check_author_replied "$repo" "$number" "$author" "$my_time")

      if [ "$author_replied" = "true" ]; then
        # 作者有回覆 → 不論有無新 push，都該去 re-review
        if [ -n "$last_commit_time" ] && [[ "$last_commit_time" > "$my_time" ]]; then
          status="needs_re_review"
          detail="🔄 作者已修正並回覆，需 re-review"
        else
          status="needs_re_review"
          detail="🔄 作者已回覆 review comments，需 re-review"
        fi
      else
        # 作者沒回覆 → 即使有新 push 也視為還在改（還沒改到我提的問題）
        status="waiting_for_author"
        if [ -n "$last_commit_time" ] && [[ "$last_commit_time" > "$my_time" ]]; then
          detail="⏳ 作者有新 push 但尚未回覆 review comments"
        else
          detail="⏳ 等作者修正"
        fi
      fi
    else
      # COMMENTED or other — 視為需要 review
      if [ -n "$last_commit_time" ] && [[ "$last_commit_time" > "$my_time" ]]; then
        status="needs_re_review"
        detail="🔄 有新 commit，需 re-review"
      else
        status="needs_first_review"
        detail="首次 review（僅有 COMMENT）"
      fi
    fi
  fi

  # 組裝結果
  pr_result=$(jq -n \
    --arg repo "$repo" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg author "$author" \
    --arg created_at "$created_at" \
    --arg review_status "$status" \
    --arg review_detail "$detail" \
    '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at, review_status: $review_status, review_detail: $review_detail}')

  echo "$pr_result" >> "$tmpfile"

  # 進度
  if [ $((count % 5)) -eq 0 ] || [ "$count" -eq "$total" ]; then
    echo "  [$count/$total] 檢查中..." >&2
  fi
done

# 輸出：排除 valid_approve 和 waiting_for_author，只留需要動作的
results=$(jq -s '.' "$tmpfile")
actionable=$(echo "$results" | jq '[.[] | select(.review_status != "valid_approve" and .review_status != "waiting_for_author")]')
skipped=$(echo "$results" | jq '[.[] | select(.review_status == "valid_approve" or .review_status == "waiting_for_author")] | length')

echo "$actionable"

actionable_count=$(echo "$actionable" | jq 'length')
echo "✅ 完成：$actionable_count 個需要 review，$skipped 個已跳過（valid approve / 等作者修正）" >&2
