#!/usr/bin/env bash
# fetch-prs-by-url.sh — Fetch PR metadata from a list of PR URLs
#
# Usage: echo '<urls>' | ./fetch-prs-by-url.sh [--exclude-author <username>]
# Input (stdin): One GitHub PR URL per line (https://github.com/<org>/<repo>/pull/<number>)
# Output (stdout): JSON array, same format as scan-need-review-prs.sh
#
# Purpose: In Slack mode, extract PR URLs from Slack messages to get metadata,
#          then pipe to check-my-review-status.sh to determine review status
#
# Example:
#   echo "https://github.com/your-org/your-repo/pull/1800
#   https://github.com/your-org/your-design-system/pull/302" \
#     | ./fetch-prs-by-url.sh --exclude-author your-github-user

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

# Read URLs from stdin and deduplicate
urls=$(sort -u)

if [ -z "$urls" ]; then
  echo "[]"
  exit 0
fi

total=$(echo "$urls" | wc -l | tr -d ' ')
echo "🔍 Processing ${total} PR URLs..." >&2

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
    echo "  ⚠️ Cannot parse URL: $url" >&2
    continue
  fi

  count=$((count + 1))

  # Fetch PR info (state + draft + author + created_at)
  pr_data=$(gh api "repos/$ORG/$repo/pulls/$number" \
    --jq '{state: .state, draft: .draft, title: .title, author: .user.login, created_at: .created_at, url: .html_url}' 2>/dev/null || echo "")

  if [ -z "$pr_data" ]; then
    echo "  ⚠️ 無法取得 PR 資訊: $repo#$number" >&2
    continue
  fi

  # Only allow open, non-draft PRs (draft means still in progress, not ready for review)
  pr_state=$(echo "$pr_data" | jq -r '.state')
  pr_draft=$(echo "$pr_data" | jq -r '.draft')
  if [ "$pr_state" != "open" ] || [ "$pr_draft" = "true" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  author=$(echo "$pr_data" | jq -r '.author // ""')
  created_at=$(echo "$pr_data" | jq -r '.created_at // ""')

  # Exclude specified author
  if [ -n "$EXCLUDE_AUTHOR" ] && [ "$author" = "$EXCLUDE_AUTHOR" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  title=$(echo "$pr_data" | jq -r '.title')
  url=$(echo "$pr_data" | jq -r '.url')

  # Assemble result (same output format as scan-need-review-prs.sh)
  jq -n \
    --arg repo "$repo" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg author "$author" \
    --arg created_at "$created_at" \
    '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at}' >> "$tmpfile"

  # Progress
  if [ $((count % 5)) -eq 0 ] || [ "$count" -eq "$total" ]; then
    echo "  [$count/$total] Fetching PR info..." >&2
  fi
done <<< "$urls"

# Output JSON array sorted by creation time
if [ -s "$tmpfile" ]; then
  jq -s 'sort_by(.created_at)' "$tmpfile"
  found=$(jq -s 'length' "$tmpfile")
else
  echo "[]"
  found=0
fi

echo "✅ Done: $found open PR(s) (skipped $skipped: closed/draft/own)" >&2
