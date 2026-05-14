#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFIER="${SCRIPT_DIR}/pr-action-classifier.sh"
TMPROOT="$(mktemp -d -t polaris-pr-action-classifier-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s want=%s got=%s\n' "$label" "$want" "$got" >&2
  fi
}

emit_snapshot() {
  local path="$1" payload="$2"
  printf '%s\n' "$payload" >"$path"
}

field_of() {
  local path="$1" field="$2"
  bash "$CLASSIFIER" --snapshot-json "$path" --format field --field "$field"
}

SN1="$TMPROOT/unsupported.json"
emit_snapshot "$SN1" '{"resolver":{"intent":"mutable","mutable_allowed":false,"unsupported_reason":"missing_task_authority"},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"UNKNOWN","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true}'
assert_eq "unsupported action" "$(field_of "$SN1" action_class)" "unsupported_mutation"
assert_eq "unsupported readiness" "$(field_of "$SN1" readiness_state)" "unsupported_mutation"

SN2="$TMPROOT/conflict.json"
emit_snapshot "$SN2" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"conflict","base_freshness":"stale_downstream","ci_state":"GREEN","review_decision":"CHANGES_REQUESTED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true}'
assert_eq "conflict action" "$(field_of "$SN2" action_class)" "blocked_conflict"
assert_eq "conflict readiness" "$(field_of "$SN2" readiness_state)" "blocked_conflict"

SN3="$TMPROOT/rereview.json"
emit_snapshot "$SN3" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"CHANGES_REQUESTED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true}'
assert_eq "rereview action" "$(field_of "$SN3" action_class)" "reviewer_handoff"
assert_eq "rereview readiness" "$(field_of "$SN3" readiness_state)" "awaiting_re_review"

SN4="$TMPROOT/ready.json"
emit_snapshot "$SN4" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true}'
assert_eq "ready action" "$(field_of "$SN4" action_class)" "ready_to_merge"
assert_eq "ready readiness" "$(field_of "$SN4" readiness_state)" "mergeable_ready"

SN5="$TMPROOT/missing-assignee.json"
emit_snapshot "$SN5" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"required_assignee_missing":true}'
assert_eq "missing assignee action" "$(field_of "$SN5" action_class)" "code_fix"
assert_eq "missing assignee readiness" "$(field_of "$SN5" readiness_state)" "needs_code_changes"

SN6="$TMPROOT/missing-assignee-pending-ci.json"
emit_snapshot "$SN6" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"PENDING","review_decision":"UNKNOWN","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"required_assignee_missing":true}'
assert_eq "missing assignee before wait-ci action" "$(field_of "$SN6" action_class)" "code_fix"
assert_eq "missing assignee before wait-ci readiness" "$(field_of "$SN6" readiness_state)" "needs_code_changes"

printf 'pr-action-classifier selftest: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
