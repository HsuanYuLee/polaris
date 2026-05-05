#!/usr/bin/env bash
# fetch-pr-info.sh — 取得 PR 完整資訊（metadata + files + re-review 偵測）
#
# Usage: ./fetch-pr-info.sh <owner/repo> <pr_number> [--my-user <username>]
# Output (stdout): JSON object with PR info, files, size, and re-review status
# Progress (stderr): 取得進度
#
# Example:
#   ./fetch-pr-info.sh your-org/your-repo 1882
#   ./fetch-pr-info.sh your-org/your-repo 1882 --my-user your-github-user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REST_LIB=""
for candidate in \
  "${SCRIPT_DIR}/../../../../scripts/lib/github-rest.sh" \
  "${SCRIPT_DIR}/../../../scripts/lib/github-rest.sh" \
  "${SCRIPT_DIR}/../../scripts/lib/github-rest.sh"
do
  if [[ -f "$candidate" ]]; then
    GITHUB_REST_LIB="$candidate"
    break
  fi
done
if [[ -n "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=/dev/null
  . "$GITHUB_REST_LIB"
fi

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

echo "📋 取得 $REPO #$PR_NUMBER 資訊..." >&2

# Step 1: PR metadata
echo "  取得 PR metadata..." >&2
if declare -F polaris_pr_view_rest >/dev/null 2>&1; then
  pr_meta=$(polaris_pr_view_rest "$REPO" "$PR_NUMBER" 2>/dev/null || echo "{}")
else
  pr_meta=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
    --json title,body,author,baseRefName,headRefName,url,state,isDraft 2>/dev/null || echo "{}")
fi

# 只允許 open 且非 draft 的 PR（draft 代表還在編輯中，不該被 review）
pr_state=$(echo "$pr_meta" | jq -r '.state // ""')
pr_draft=$(echo "$pr_meta" | jq -r '.isDraft // false')
if [ "$pr_state" != "OPEN" ]; then
  echo "❌ PR #$PR_NUMBER 狀態為 ${pr_state}（非 OPEN），跳過 review" >&2
  exit 1
fi
if [ "$pr_draft" = "true" ]; then
  echo "❌ PR #$PR_NUMBER 是 draft（還在編輯中），跳過 review" >&2
  exit 1
fi

title=$(echo "$pr_meta" | jq -r '.title // ""')
author=$(echo "$pr_meta" | jq -r '.author.login // ""')
base=$(echo "$pr_meta" | jq -r '.baseRefName // ""')
head=$(echo "$pr_meta" | jq -r '.headRefName // ""')

# Step 2: Files with changes
echo "  取得變更檔案清單..." >&2
if declare -F polaris_gh_api >/dev/null 2>&1; then
  files=$(polaris_gh_api "repos/$REPO/pulls/$PR_NUMBER/files" --paginate \
    --jq '[.[] | {filename: .filename, status: .status, additions: .additions, deletions: .deletions, changes: .changes}]' 2>/dev/null || echo "[]")
else
  files=$(gh api "repos/$REPO/pulls/$PR_NUMBER/files" --paginate \
    --jq '[.[] | {filename: .filename, status: .status, additions: .additions, deletions: .deletions, changes: .changes}]' 2>/dev/null || echo "[]")
fi

# 計算總變更行數
total_additions=$(echo "$files" | jq '[.[].additions] | add // 0')
total_deletions=$(echo "$files" | jq '[.[].deletions] | add // 0')
total_changes=$((total_additions + total_deletions))
file_count=$(echo "$files" | jq 'length')

echo "  📊 ${file_count} 個檔案，${total_changes} 行變更（+${total_additions} -${total_deletions}）" >&2

# 判斷 review 策略
review_strategy="single"
if [ "$total_changes" -gt 800 ]; then
  review_strategy="batch"
  echo "  ⚡ 變更 > 800 行，建議分批 review" >&2
fi

# Step 3: Re-review 偵測
is_re_review=false
my_review_count=0
my_last_review_state=""

if [ -n "$MY_USER" ]; then
  echo "  檢查 re-review 狀態（user: ${MY_USER}）..." >&2

  if declare -F polaris_gh_api >/dev/null 2>&1; then
    reviews=$(polaris_gh_api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
      --jq "[.[] | select(.user.login == \"$MY_USER\") | {state: .state, submitted_at: .submitted_at}]" 2>/dev/null || echo "[]")
  else
    reviews=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
      --jq "[.[] | select(.user.login == \"$MY_USER\") | {state: .state, submitted_at: .submitted_at}]" 2>/dev/null || echo "[]")
  fi

  my_review_count=$(echo "$reviews" | jq 'length')

  if [ "$my_review_count" -gt 0 ]; then
    is_re_review=true
    my_last_review_state=$(echo "$reviews" | jq -r 'sort_by(.submitted_at) | last | .state')
    echo "  🔄 Re-review 模式（上次: ${my_last_review_state}）" >&2
  else
    echo "  🆕 首次 review" >&2
  fi
fi

# Step 4: Approval 狀態（附在結果中供 Step 6 使用）
echo "  取得 approval 狀態..." >&2
if declare -F polaris_gh_api >/dev/null 2>&1; then
  all_reviews=$(polaris_gh_api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
    --jq '[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}]' 2>/dev/null || echo "[]")
else
  all_reviews=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
    --jq '[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}]' 2>/dev/null || echo "[]")
fi

if declare -F polaris_gh_api >/dev/null 2>&1; then
  pushed_at=$(polaris_gh_api "repos/$REPO/pulls/$PR_NUMBER" --jq '.head.repo.pushed_at' 2>/dev/null || echo "")
else
  pushed_at=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq '.head.repo.pushed_at' 2>/dev/null || echo "")
fi

# 組裝最終 JSON
result=$(jq -n \
  --arg repo "$REPO" \
  --argjson number "$PR_NUMBER" \
  --arg title "$title" \
  --arg author "$author" \
  --arg base "$base" \
  --arg head "$head" \
  --argjson file_count "$file_count" \
  --argjson total_additions "$total_additions" \
  --argjson total_deletions "$total_deletions" \
  --argjson total_changes "$total_changes" \
  --arg review_strategy "$review_strategy" \
  --argjson is_re_review "$is_re_review" \
  --argjson my_review_count "$my_review_count" \
  --arg my_last_review_state "$my_last_review_state" \
  --argjson files "$files" \
  --argjson all_reviews "$all_reviews" \
  --arg pushed_at "$pushed_at" \
  '{
    repo: $repo,
    number: $number,
    title: $title,
    author: $author,
    base: $base,
    head: $head,
    file_count: $file_count,
    total_additions: $total_additions,
    total_deletions: $total_deletions,
    total_changes: $total_changes,
    review_strategy: $review_strategy,
    is_re_review: $is_re_review,
    my_review_count: $my_review_count,
    my_last_review_state: $my_last_review_state,
    files: $files,
    all_reviews: $all_reviews,
    pushed_at: $pushed_at
  }')

echo "$result"
echo "✅ PR 資訊取得完成" >&2
