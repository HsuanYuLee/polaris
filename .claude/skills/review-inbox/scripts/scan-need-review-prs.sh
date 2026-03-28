#!/usr/bin/env bash
# scan-need-review-prs.sh — 掃描 your-org org 所有 repo，找出掛 need review label 的 open PR
#
# Usage: ./scan-need-review-prs.sh [--exclude-author <username>]
# Output (stdout): JSON array of PR objects, sorted by created_at asc
# Progress (stderr): 掃描進度
#
# Example:
#   ./scan-need-review-prs.sh --exclude-author your-username
#   ./scan-need-review-prs.sh  # 不排除任何人

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

echo "🔍 掃描 $ORG org 的 need review PR..." >&2

# Step 1: 用 gh search 直接搜尋掛 "need review" label 的 open PR（避免逐 repo 掃描）
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

search_results=$(gh search prs "draft:false" --label "need review" --state open --owner "$ORG" --limit 100 \
  --json repository,number,title,url,author,createdAt 2>/dev/null || echo "[]")

total=$(echo "$search_results" | jq 'length')
echo "📦 找到 $total 個掛 need review label 的 PR" >&2

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

# Step 2: 轉換格式並過濾
for row in $(echo "$search_results" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repository.name')
  author=$(_jq '.author.login')

  # 排除指定 author
  if [ -n "$EXCLUDE_AUTHOR" ] && [ "$author" = "$EXCLUDE_AUTHOR" ]; then
    continue
  fi

  echo "$row" | base64 --decode | jq '{
    repo: .repository.name,
    number: .number,
    title: .title,
    url: .url,
    author: .author.login,
    created_at: .createdAt
  }' >> "$tmpfile"
done

# Step 3: 按建立時間排序並輸出 JSON
if [ -s "$tmpfile" ]; then
  jq -s 'sort_by(.created_at)' "$tmpfile"
  found=$(jq -s 'length' "$tmpfile")
else
  echo "[]"
  found=0
fi

echo "✅ 掃描完成，共找到 $found 個 PR" >&2
