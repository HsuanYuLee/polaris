#!/usr/bin/env bash
# check-pr-approval-status.sh — 批次檢查 PR 的 approval 數量（含 stale 偵測）
#
# Usage: echo '<pr_json>' | ./check-pr-approval-status.sh [--threshold <N>]
# Input (stdin): fetch-user-open-prs.sh 或 rebase-pr-branch.sh 的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 approval 資訊
# Progress (stderr): 檢查進度
#
# 附加欄位：
#   - valid_approvals   — 有效的 approve 數（submitted_at > pushed_at）
#   - total_approvals   — 所有 APPROVED review 數
#   - has_stale         — 是否有 stale approve
#   - reviewers         — reviewer 明細 JSON array [{user, state, is_stale}]
#   - needs_review      — 是否需要（更多）review（valid < threshold）
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username \
#     | ./check-pr-approval-status.sh --threshold 2

set -euo pipefail

ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi
THRESHOLD=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 讀取 stdin
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "🔎 檢查 ${total} 個 PR 的 approval 狀態（threshold: ${THRESHOLD}）..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')

  count=$((count + 1))

  # 取得 reviews
  reviews=$(gh api "repos/$ORG/$repo/pulls/$number/reviews" \
    --jq '[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}]' 2>/dev/null || echo "[]")

  # 取得最後 push 時間
  pushed_at=$(gh api "repos/$ORG/$repo/pulls/$number" \
    --jq '.head.repo.pushed_at' 2>/dev/null || echo "")

  # 計算每位 reviewer 的最新狀態
  # 先取得所有 unique reviewers，再找各自最新的 review
  reviewer_users=$(echo "$reviews" | jq -r '[.[].user] | unique | .[]')

  reviewer_tmpfile=$(mktemp)
  valid_approvals=0
  total_approvals=0
  has_stale=false

  for user in $reviewer_users; do
    # 該 reviewer 最新的 review
    latest=$(echo "$reviews" | jq "[.[] | select(.user == \"$user\")] | sort_by(.submitted_at) | last")
    state=$(echo "$latest" | jq -r '.state')
    submitted_at=$(echo "$latest" | jq -r '.submitted_at')

    is_stale=false

    if [ "$state" = "APPROVED" ]; then
      total_approvals=$((total_approvals + 1))
      if [ -n "$pushed_at" ] && [[ "$submitted_at" < "$pushed_at" ]]; then
        is_stale=true
        has_stale=true
      else
        valid_approvals=$((valid_approvals + 1))
      fi
    fi

    jq -n \
      --arg user "$user" \
      --arg state "$state" \
      --argjson is_stale "$is_stale" \
      '{user: $user, state: $state, is_stale: $is_stale}' >> "$reviewer_tmpfile"
  done

  reviewers=$(jq -s '.' "$reviewer_tmpfile")
  rm -f "$reviewer_tmpfile"

  needs_review=false
  if [ "$valid_approvals" -lt "$THRESHOLD" ]; then
    needs_review=true
  fi

  # 保留原本的欄位，附加新欄位
  original=$(echo "$row" | base64 --decode)
  enriched=$(echo "$original" | jq \
    --argjson valid_approvals "$valid_approvals" \
    --argjson total_approvals "$total_approvals" \
    --argjson has_stale "$has_stale" \
    --argjson reviewers "$reviewers" \
    --argjson needs_review "$needs_review" \
    --argjson threshold "$THRESHOLD" \
    '. + {valid_approvals: $valid_approvals, total_approvals: $total_approvals, has_stale: $has_stale, reviewers: $reviewers, needs_review: $needs_review, threshold: $threshold}')

  echo "$enriched" >> "$tmpfile"

  status_str="${valid_approvals}/${THRESHOLD}"
  if [ "$has_stale" = true ]; then
    status_str="${status_str} (stale)"
  fi
  echo "  [$count/$total] $repo #$number — $status_str" >&2
done

# 排序：valid_approvals 升序（最需要 review 的排前面）
results=$(jq -s '.' "$tmpfile")
echo "$results" | jq 'sort_by(.valid_approvals)'

needs=$(echo "$results" | jq "[.[] | select(.needs_review == true)] | length")
done_count=$((total - needs))
echo "✅ 完成：$needs 個需要 review，$done_count 個已達標" >&2
