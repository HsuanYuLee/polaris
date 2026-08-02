#!/usr/bin/env bash
# check-feature-pr.sh — Check feature branch PR readiness and status
#
# Usage: ./check-feature-pr.sh <owner/repo> <feature_branch> [--base <base_branch>]
#
# Checks:
#   1. How many task PRs target the feature branch (merged / open / closed)
#   2. Whether all task PRs are merged (= ready to create feature PR)
#   3. Whether a feature PR (feature_branch → base) already exists
#   4. If feature PR exists: its review, CI, and merge conflict status
#
# Output (stdout): JSON object with all status fields
# Progress (stderr): human-readable progress
#
# Examples:
#   ./check-feature-pr.sh acme-org/my-app feat/PROJ-460-product-listing
#   ./check-feature-pr.sh acme-org/my-app feat/PROJ-460-product-listing --base main

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

REPO="${1:?Usage: $0 <owner/repo> <feature_branch> [--base <base_branch>]}"
FEATURE_BRANCH="${2:?Usage: $0 <owner/repo> <feature_branch> [--base <base_branch>]}"
shift 2

BASE_BRANCH="develop"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "🔍 Checking feature branch status: $FEATURE_BRANCH → $BASE_BRANCH in $REPO" >&2

# ── Step 1: Query all task PRs targeting the feature branch ──

echo "  查詢 task PRs (base: $FEATURE_BRANCH)..." >&2
if declare -F polaris_gh_api >/dev/null 2>&1; then
  task_prs=$(polaris_gh_api "repos/$REPO/pulls" --method GET -f "base=$FEATURE_BRANCH" -f "state=all" -f "per_page=50" \
    --jq '[.[] | {
      number: .number,
      title: .title,
      state: (if .merged_at then "MERGED" else (.state | ascii_upcase) end),
      mergedAt: .merged_at,
      headRefName: .head.ref
    }]' 2>/dev/null || echo "[]")
else
  task_prs=$(gh pr list --repo "$REPO" --base "$FEATURE_BRANCH" --state all \
    --json number,title,state,mergedAt,headRefName --limit 50 2>/dev/null || echo "[]")
fi

total=$(echo "$task_prs" | jq 'length')
merged=$(echo "$task_prs" | jq '[.[] | select(.state == "MERGED")] | length')
open=$(echo "$task_prs" | jq '[.[] | select(.state == "OPEN")] | length')
closed=$(echo "$task_prs" | jq '[.[] | select(.state == "CLOSED" and .mergedAt == null)] | length')

echo "  📊 Task PRs: $total total ($merged merged, $open open, $closed closed)" >&2

# ── Step 2: Determine if all tasks are merged ──

all_merged=false
if [[ "$open" -eq 0 ]] && [[ "$merged" -gt 0 ]]; then
  all_merged=true
  echo "  ✅ All task PRs merged — ready for feature PR" >&2
elif [[ "$open" -gt 0 ]]; then
  echo "  ⏳ $open task PR(s) still open" >&2
elif [[ "$total" -eq 0 ]]; then
  echo "  ⚠️  No task PRs found targeting $FEATURE_BRANCH" >&2
fi

# ── Step 3: Check if feature PR already exists ──

echo "  查詢 feature PR ($FEATURE_BRANCH → $BASE_BRANCH)..." >&2
if declare -F polaris_gh_api >/dev/null 2>&1 && declare -F polaris_pr_checks_rest >/dev/null 2>&1; then
  repo_owner="${REPO%%/*}"
  feature_pr=$(polaris_gh_api "repos/$REPO/pulls" \
    --method GET \
    -f "head=${repo_owner}:${FEATURE_BRANCH}" \
    -f "base=$BASE_BRANCH" \
    -f "state=open" \
    -f "per_page=1" \
    --jq '[.[] | {
      number: .number,
      title: .title,
      state: (.state | ascii_upcase),
      mergeable: (.mergeable_state // "unknown"),
      isDraft: .draft,
      url: .html_url
    }]' 2>/dev/null || echo "[]")
else
  feature_pr=$(gh pr list --repo "$REPO" --head "$FEATURE_BRANCH" --base "$BASE_BRANCH" --state open \
    --json number,title,state,mergeable,statusCheckRollup,reviews,isDraft,reviewRequests,url --limit 1 2>/dev/null || echo "[]")
fi

feature_pr_exists=false
feature_pr_number=null
feature_pr_url=null
feature_pr_review_status="{}"
feature_pr_ci_status="unknown"
feature_pr_mergeable="unknown"
feature_pr_inline_comments=0

if [[ $(echo "$feature_pr" | jq 'length') -gt 0 ]]; then
  feature_pr_exists=true
  feature_pr_number=$(echo "$feature_pr" | jq '.[0].number')
  feature_pr_url=$(echo "$feature_pr" | jq -r '.[0].url')
  feature_pr_mergeable=$(echo "$feature_pr" | jq -r '.[0].mergeable // "unknown"')

  echo "  📋 Feature PR found: #$feature_pr_number ($feature_pr_url)" >&2

  # CI status
  if declare -F polaris_pr_checks_rest >/dev/null 2>&1; then
    feature_pr_checks=$(polaris_pr_checks_rest "$REPO" "$feature_pr_number" 2>/dev/null || echo "[]")
    ci_success=$(echo "$feature_pr_checks" | jq '[.[] | select(.state == "SUCCESS")] | length')
    ci_failure=$(echo "$feature_pr_checks" | jq '[.[] | select(.state == "FAILURE")] | length')
    ci_pending=$(echo "$feature_pr_checks" | jq '[.[] | select(.state != "SUCCESS" and .state != "FAILURE")] | length')
  else
    ci_success=$(echo "$feature_pr" | jq '[.[0].statusCheckRollup[]? | select(.state == "SUCCESS")] | length')
    ci_failure=$(echo "$feature_pr" | jq '[.[0].statusCheckRollup[]? | select(.state == "FAILURE")] | length')
    ci_pending=$(echo "$feature_pr" | jq '[.[0].statusCheckRollup[]? | select(.state != "SUCCESS" and .state != "FAILURE")] | length')
  fi

  if [[ "$ci_failure" -gt 0 ]]; then
    feature_pr_ci_status="failure"
  elif [[ "$ci_pending" -gt 0 ]]; then
    feature_pr_ci_status="pending"
  elif [[ "$ci_success" -gt 0 ]]; then
    feature_pr_ci_status="success"
  fi

  # Review status
  if declare -F polaris_gh_api >/dev/null 2>&1; then
    feature_reviews=$(polaris_gh_api "repos/$REPO/pulls/$feature_pr_number/reviews" \
      --jq '[.[] | {state: .state}]' 2>/dev/null || echo "[]")
    approved=$(echo "$feature_reviews" | jq '[.[] | select(.state == "APPROVED")] | length')
    changes_requested=$(echo "$feature_reviews" | jq '[.[] | select(.state == "CHANGES_REQUESTED")] | length')
    requested=0
  else
    approved=$(echo "$feature_pr" | jq '[.[0].reviews[]? | select(.state == "APPROVED")] | length')
    changes_requested=$(echo "$feature_pr" | jq '[.[0].reviews[]? | select(.state == "CHANGES_REQUESTED")] | length')
    requested=$(echo "$feature_pr" | jq '[.[0].reviewRequests[]?] | length')
  fi

  feature_pr_review_status=$(jq -n \
    --argjson approved "$approved" \
    --argjson changes_requested "$changes_requested" \
    --argjson requested "$requested" \
    '{approved: $approved, changes_requested: $changes_requested, requested: $requested}')

  # Inline comments count
  if declare -F polaris_gh_api >/dev/null 2>&1; then
    feature_pr_inline_comments=$(polaris_gh_api "repos/$REPO/pulls/$feature_pr_number/comments" --jq 'length' 2>/dev/null || echo "0")
  else
    feature_pr_inline_comments=$(gh api "repos/$REPO/pulls/$feature_pr_number/comments" --jq 'length' 2>/dev/null || echo "0")
  fi

  echo "  Review: $approved approved, $changes_requested changes requested | CI: $feature_pr_ci_status | Comments: $feature_pr_inline_comments" >&2
else
  echo "  ℹ️  No open feature PR found" >&2
fi

# ── Step 4: Assemble result ──

result=$(jq -n \
  --arg repo "$REPO" \
  --arg feature_branch "$FEATURE_BRANCH" \
  --arg base_branch "$BASE_BRANCH" \
  --argjson task_prs "$task_prs" \
  --argjson total "$total" \
  --argjson merged "$merged" \
  --argjson open "$open" \
  --argjson closed "$closed" \
  --argjson all_merged "$all_merged" \
  --argjson feature_pr_exists "$feature_pr_exists" \
  --argjson feature_pr_number "$feature_pr_number" \
  --arg feature_pr_url "$feature_pr_url" \
  --arg feature_pr_ci "$feature_pr_ci_status" \
  --arg feature_pr_mergeable "$feature_pr_mergeable" \
  --argjson feature_pr_review "$feature_pr_review_status" \
  --argjson feature_pr_inline_comments "$feature_pr_inline_comments" \
  '{
    repo: $repo,
    feature_branch: $feature_branch,
    base_branch: $base_branch,
    task_prs: {
      total: $total,
      merged: $merged,
      open: $open,
      closed: $closed,
      all_merged: $all_merged,
      details: $task_prs
    },
    feature_pr: {
      exists: $feature_pr_exists,
      number: $feature_pr_number,
      url: $feature_pr_url,
      ci: $feature_pr_ci,
      mergeable: $feature_pr_mergeable,
      review: $feature_pr_review,
      inline_comments: $feature_pr_inline_comments
    },
    action: (
      if $all_merged and ($feature_pr_exists | not) then "CREATE_FEATURE_PR"
      elif $all_merged and $feature_pr_exists then "FEATURE_PR_EXISTS"
      elif $open > 0 then "TASKS_IN_PROGRESS"
      elif $total == 0 then "NO_TASK_PRS"
      else "UNKNOWN"
      end
    )
  }')

echo "$result"
echo "✅ Done: action=$(echo "$result" | jq -r '.action')" >&2
