#!/usr/bin/env bash
# fetch-prs-by-url.sh — 從 PR URL 清單取得 PR metadata
#
# Usage: echo '<urls>' | ./fetch-prs-by-url.sh [--exclude-author <username>]
# Input (stdin): 每行一個 GitHub PR URL（https://github.com/your-org/<repo>/pull/<number>）
# Output (stdout): JSON array，格式與 scan-need-review-prs.sh 相同
#
# 用途：Slack 模式下，從 Slack 訊息萃取的 PR URL 取得 metadata，
#       再 pipe 到 check-my-review-status.sh 判斷 review 狀態
#
# Example:
#   echo "https://github.com/your-org/your-app/pull/1800
#   https://github.com/your-org/your-design-system/pull/302" \
#     | ./fetch-prs-by-url.sh --exclude-author your-username

set -euo pipefail

ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi
EXCLUDE_AUTHOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude-author) EXCLUDE_AUTHOR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 讀取 stdin 的 URL 並去重
urls=$(sort -u)

if [ -z "$urls" ]; then
  echo "[]"
  exit 0
fi

total=$(echo "$urls" | wc -l | tr -d ' ')
echo "🔍 處理 ${total} 個 PR URL..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0
skipped=0

while IFS= read -r url; do
  [ -z "$url" ] && continue

  # Parse repo and number from URL
  # Expected format: https://github.com/<org>/<repo>/pull/<number>
  if [[ "$url" =~ github\.com/${ORG}/([^/]+)/pull/([0-9]+) ]]; then
    repo="${BASH_REMATCH[1]}"
    number="${BASH_REMATCH[2]}"
  else
    echo "  ⚠️ 無法解析 URL: $url" >&2
    continue
  fi

  count=$((count + 1))

  # 取得 PR 資訊（state + draft + author + created_at）
  pr_data=$(gh api "repos/$ORG/$repo/pulls/$number" \
    --jq '{state: .state, draft: .draft, title: .title, author: .user.login, created_at: .created_at, url: .html_url}' 2>/dev/null || echo "")

  if [ -z "$pr_data" ]; then
    echo "  ⚠️ 無法取得 PR 資訊: $repo#$number" >&2
    continue
  fi

  # 只允許 open 且非 draft 的 PR（draft 代表還在編輯中，不該被 review）
  pr_state=$(echo "$pr_data" | jq -r '.state')
  pr_draft=$(echo "$pr_data" | jq -r '.draft')
  if [ "$pr_state" != "open" ] || [ "$pr_draft" = "true" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  author=$(echo "$pr_data" | jq -r '.author // ""')
  created_at=$(echo "$pr_data" | jq -r '.created_at // ""')

  # 排除指定 author
  if [ -n "$EXCLUDE_AUTHOR" ] && [ "$author" = "$EXCLUDE_AUTHOR" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  title=$(echo "$pr_data" | jq -r '.title')
  url=$(echo "$pr_data" | jq -r '.url')

  # 組裝結果（與 scan-need-review-prs.sh 輸出格式一致）
  jq -n \
    --arg repo "$repo" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg author "$author" \
    --arg created_at "$created_at" \
    '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at}' >> "$tmpfile"

  # 進度
  if [ $((count % 5)) -eq 0 ] || [ "$count" -eq "$total" ]; then
    echo "  [$count/$total] 取得 PR 資訊中..." >&2
  fi
done <<< "$urls"

# 輸出 JSON array，按建立時間排序
if [ -s "$tmpfile" ]; then
  jq -s 'sort_by(.created_at)' "$tmpfile"
  found=$(jq -s 'length' "$tmpfile")
else
  echo "[]"
  found=0
fi

echo "✅ 完成：$found 個 open PR（跳過 $skipped 個：已關閉/draft/自己的）" >&2
