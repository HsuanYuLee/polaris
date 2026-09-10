#!/usr/bin/env bash
# scan-need-review-prs.sh — Scan all repos in the org for open PRs with the "need review" label
#
# Usage: ./scan-need-review-prs.sh [--exclude-author <username>]
# Output (stdout): JSON array of PR objects, sorted by created_at asc
# Progress (stderr): scan progress
# Exit:  0 問到了（含「問到了而且一顆都沒有」）
#        1 參數不對、少了 ORG
#        2 問不到上游（POLARIS_NEED_REVIEW_SCAN_UNAVAILABLE）——不印一個 0 顆的結論
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

# **離場碼不吞。** 這一行以前寫的是 `2>/dev/null || echo "[]"`：上游被限流、憑證過期、
# 網路斷掉，三種都被換成一個合法的空陣列，然後下面印「Found 0 PRs」並以 0 離場。**空的
# 方向是「比較少」，而往少的方向錯沒有人會抱怨**——整份待看清單消失，讀的人看到的是
# 「今天沒有 PR 要看」。DP-700 在姊妹腳本上量到這個形狀真的會發生：同一個命令幾分鐘內
# 回 25 顆、0 顆、2 顆、21 顆。
# `search_rc=$?` 不能寫成獨立的一行：這支開著 `set -e`，賦值失敗會當場離場，那一行永遠
# 到不了。`|| search_rc=$?` 讓那次失敗變成一個被處理過的條件。
search_err="$(mktemp)"
search_rc=0
search_results="$(gh search prs "draft:false" --label "need review" --state open --owner "$ORG" --limit 100 \
  --json repository,number,title,url,author,createdAt 2>"$search_err")" || search_rc=$?
if [[ "$search_rc" -ne 0 ]]; then
  echo "POLARIS_NEED_REVIEW_SCAN_UNAVAILABLE" >&2
  echo "問不到上游：gh search prs 離場碼 ${search_rc}" >&2
  cat "$search_err" >&2
  rm -f "$search_err"
  exit 2
fi
rm -f "$search_err"

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
