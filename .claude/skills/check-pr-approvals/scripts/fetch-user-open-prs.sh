#!/usr/bin/env bash
# fetch-user-open-prs.sh — 取得指定使用者在 your-org org 的所有 open PR（含 branch 資訊）
#
# Usage: ./fetch-user-open-prs.sh [--author <username>]
# Output (stdout): JSON array of PR objects with base/head branch info
# Progress (stderr): 搜尋進度
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username
#   ./fetch-user-open-prs.sh  # auto-detect via `gh api user`

set -euo pipefail

ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi
AUTHOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) AUTHOR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Auto-detect GitHub username if not provided
if [ -z "$AUTHOR" ]; then
  AUTHOR=$(gh api user --jq '.login' 2>/dev/null || echo "")
  if [ -z "$AUTHOR" ]; then
    echo "❌ 無法偵測 GitHub username，請用 --author <username> 指定" >&2
    exit 1
  fi
  echo "👤 自動偵測 GitHub user: $AUTHOR" >&2
fi

echo "🔍 搜尋 $AUTHOR 在 $ORG 的 open PR..." >&2

# Step 1: 用 gh search prs 取得所有 open PR
prs=$(gh search prs "draft:false" --author "$AUTHOR" --state open --owner "$ORG" --limit 100 \
  --json repository,number,title,url,updatedAt,labels)

total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "📭 目前沒有 open PR" >&2
  echo "[]"
  exit 0
fi

echo "📦 找到 $total 個 open PR，取得 branch 資訊中..." >&2

# Step 2: 批次取得每個 PR 的 base/head branch 資訊
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo_full=$(_jq '.repository.name')
  number=$(_jq '.number')
  title=$(_jq '.title')
  url=$(_jq '.url')
  updated_at=$(_jq '.updatedAt')
  labels=$(_jq '[.labels[].name] | join(",")')

  count=$((count + 1))

  # 取得 base/head branch
  branch_info=$(gh api "repos/$ORG/$repo_full/pulls/$number" \
    --jq '{base: .base.ref, head: .head.ref}' 2>/dev/null || echo '{"base":"","head":""}')

  base=$(echo "$branch_info" | jq -r '.base')
  head=$(echo "$branch_info" | jq -r '.head')

  jq -n \
    --arg repo "$repo_full" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg updated_at "$updated_at" \
    --arg labels "$labels" \
    --arg base "$base" \
    --arg head "$head" \
    '{repo: $repo, number: $number, title: $title, url: $url, updated_at: $updated_at, labels: $labels, base: $base, head: $head}' >> "$tmpfile"

  echo "  [$count/$total] $repo_full #$number — base: $base, head: $head" >&2
done

jq -s '.' "$tmpfile"
echo "✅ 取得完成，共 $total 個 PR" >&2
