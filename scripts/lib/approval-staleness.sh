#!/usr/bin/env bash
# Purpose: Canonical commit_id-based approval-staleness atom (DP-315 T1).
#          Single shared implementation sourced by PR-review skill consumers
#          (check-pr-approvals, review-inbox) so there is exactly one writer
#          path for the staleness decision (AC2, AC-NF1).
# Inputs:  approval_staleness <review_commit_id> <head_sha>
#            $1 review.commit_id — the commit a review (APPROVED) was tied to.
#            $2 head.sha         — the current PR head commit SHA.
# Outputs: stdout "valid" or "stale"; always exit 0 (fail-closed, never crash).
#
# Canonical definition (mirrors .claude/skills/references/stale-approval-detection.md):
#   valid ⟺ review.commit_id == pr.head.sha   (both non-empty)
#   stale ⟺ review.commit_id != pr.head.sha
#           OR review.commit_id is empty/null
#           OR pr.head.sha     is empty/null   (fail-closed; AC-NEG3)
#
# This helper deliberately does NOT consult head.repo.pushed_at, submitted_at,
# or committer dates. Re-introducing a timestamp basis is forbidden (AC-NEG2).

# Sentinel value that represents "no usable commit id". gh --jq projects a
# missing JSON field as the string "null", so both empty and "null" must be
# treated as absent and fail-closed to stale.
APPROVAL_STALENESS_NULL_TOKEN="null"

# Returns "valid" when the review's commit_id matches the current PR head SHA,
# otherwise "stale". Missing / null inputs fail closed to "stale".
# Args:        $1 = review commit_id, $2 = head sha
# Side effects: none (read-only; writes only to stdout)
approval_staleness() {
  local review_commit_id="${1:-}"
  local head_sha="${2:-}"

  # Fail-closed: any absent input (empty string or the literal "null" token
  # that gh --jq emits for a missing field) yields stale.
  if [[ -z "$review_commit_id" || "$review_commit_id" == "$APPROVAL_STALENESS_NULL_TOKEN" ]]; then
    printf 'stale\n'
    return 0
  fi
  if [[ -z "$head_sha" || "$head_sha" == "$APPROVAL_STALENESS_NULL_TOKEN" ]]; then
    printf 'stale\n'
    return 0
  fi

  if [[ "$review_commit_id" == "$head_sha" ]]; then
    printf 'valid\n'
  else
    printf 'stale\n'
  fi
  return 0
}
