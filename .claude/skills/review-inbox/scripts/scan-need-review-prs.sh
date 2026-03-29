#!/usr/bin/env bash
# scan-need-review-prs.sh — Scan all repos in the org for open PRs with the "need review" label
#
# Usage: ./scan-need-review-prs.sh [--exclude-author <username>]
# Output (stdout): JSON array of PR objects, sorted by created_at asc
# Progress (stderr): scan progress
#
# Example:
#   ./scan-need-review-prs.sh --exclude-author your-github-user
#   ./scan-need-review-prs.sh  # no author exclusion

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

echo "🔍 Scanning $ORG org for need review PRs..." >&2

# Step 1: Use gh search to find open PRs with "need review" label (avoids per-repo scanning)
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

search_results=$(gh search prs "draft:false" --label "need review" --state open --owner "$ORG" --limit 100 \
  --json repository,number,title,url,author,createdAt 2>/dev/null || echo "[]")

total=$(echo "$search_results" | jq 'length')
echo "📦 Found $total PRs with need review label" >&2

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

# Step 2: Transform format and filter
for row in $(echo "$search_results" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repository.name')
  author=$(_jq '.author.login')

  # Exclude specified author
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

# Step 3: Sort by creation time and output JSON
if [ -s "$tmpfile" ]; then
  jq -s 'sort_by(.created_at)' "$tmpfile"
  found=$(jq -s 'length' "$tmpfile")
else
  echo "[]"
  found=0
fi

echo "✅ Scan complete, found $found PR(s)" >&2
