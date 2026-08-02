#!/usr/bin/env bash
# Purpose: Canonical valid-approval counter (DP-413 T3). Single shared source of
#          the per-reviewer latest-review valid/stale approval tally, consumed by
#          both check-pr-approvals (check-pr-approval-status.sh) and the PR-state
#          pr-action-classifier policy-first APPROVED branch, so there is exactly
#          one counting path (AC6, no second implementation that can drift).
# Inputs:  --head-sha SHA (required) — current PR head commit SHA.
#          --reviews-json PATH       — reviews array file; read from stdin if omitted.
#          Reviews JSON shape: [{user, state, submitted_at, commit_id}, ...].
# Outputs: stdout JSON {valid_approvals, total_approvals, has_stale, reviewers[]}
#          where reviewers[] = [{user, state, is_stale}]. exit 2 on contract
#          violation (missing head-sha, unreadable reviews, unparseable JSON).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the canonical commit_id-based staleness atom (DP-315). approval_staleness
# <review_commit_id> <head_sha> echoes "valid" / "stale"; reusing it keeps the
# staleness decision on its single writer path shared with review-inbox.
APPROVAL_STALENESS_HELPER="${SCRIPT_DIR}/approval-staleness.sh"
if [[ ! -f "$APPROVAL_STALENESS_HELPER" ]]; then
  echo "POLARIS_TOOL_MISSING:approval-staleness.sh (expected at $APPROVAL_STALENESS_HELPER)" >&2
  exit 2
fi
# shellcheck source=approval-staleness.sh
source "$APPROVAL_STALENESS_HELPER"

HEAD_SHA=""
REVIEWS_JSON_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --reviews-json) REVIEWS_JSON_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: pr-approval-count.sh --head-sha SHA [--reviews-json PATH] (reviews via stdin if omitted)" >&2
      exit 0 ;;
    *) echo "pr-approval-count: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$HEAD_SHA" ]]; then
  echo "pr-approval-count: --head-sha is required (fail-closed)" >&2
  exit 2
fi

if [[ -n "$REVIEWS_JSON_PATH" ]]; then
  if [[ ! -f "$REVIEWS_JSON_PATH" ]]; then
    echo "pr-approval-count: --reviews-json not found: $REVIEWS_JSON_PATH" >&2
    exit 2
  fi
  reviews="$(cat "$REVIEWS_JSON_PATH")"
else
  reviews="$(cat)"
fi

# Validate the reviews payload is a JSON array before consuming it; a malformed
# or non-array body fails closed rather than silently counting zero approvals.
if ! echo "$reviews" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "pr-approval-count: reviews input is not a JSON array (fail-closed)" >&2
  exit 2
fi

# Per-reviewer latest-review tally. For each unique reviewer we take their most
# recent review (by submitted_at); an APPROVED latest review counts toward
# total_approvals, and counts toward valid_approvals only when its commit_id
# matches the current head (via the canonical staleness helper, fail-closed).
reviewer_users="$(echo "$reviews" | jq -r '[.[].user] | unique | .[]')"

reviewer_tmpfile="$(mktemp)"
trap 'rm -f "$reviewer_tmpfile"' EXIT
valid_approvals=0
total_approvals=0
has_stale=false

for user in $reviewer_users; do
  latest="$(echo "$reviews" | jq "[.[] | select(.user == \"$user\")] | sort_by(.submitted_at) | last")"
  state="$(echo "$latest" | jq -r '.state')"
  commit_id="$(echo "$latest" | jq -r '.commit_id')"

  is_stale=false

  if [ "$state" = "APPROVED" ]; then
    total_approvals=$((total_approvals + 1))
    if [ "$(approval_staleness "$commit_id" "$HEAD_SHA")" = "valid" ]; then
      valid_approvals=$((valid_approvals + 1))
    else
      is_stale=true
      has_stale=true
    fi
  fi

  jq -n \
    --arg user "$user" \
    --arg state "$state" \
    --argjson is_stale "$is_stale" \
    '{user: $user, state: $state, is_stale: $is_stale}' >>"$reviewer_tmpfile"
done

reviewers="$(jq -s '.' "$reviewer_tmpfile")"

jq -n \
  --argjson valid_approvals "$valid_approvals" \
  --argjson total_approvals "$total_approvals" \
  --argjson has_stale "$has_stale" \
  --argjson reviewers "$reviewers" \
  '{valid_approvals: $valid_approvals, total_approvals: $total_approvals, has_stale: $has_stale, reviewers: $reviewers}'
