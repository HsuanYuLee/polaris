#!/usr/bin/env bash
# Purpose: Deterministic selftest for pr-action-classifier.sh — asserts action_class /
#          readiness_state across snapshot fixtures (unsupported / conflict / rereview /
#          ready / missing-assignee / unaddressed-comment / disposition-filtered).
# Inputs:  none (fixtures emitted to a temp dir).
# Outputs: PASS/FAIL summary on stdout; exit 1 if any assertion fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFIER="${SCRIPT_DIR}/pr-action-classifier.sh"
APPROVAL_COUNT_LIB="${SCRIPT_DIR}/lib/pr-approval-count.sh"
TMPROOT="$(mktemp -d -t polaris-pr-action-classifier-XXXXXX)"
PASS=0
FAIL=0

# Hermetic threshold resolution: point the classifier's company-config lookup at
# an empty temp workspace so no ambient workspace-config.yaml scrum.approval_threshold
# leaks into the fixtures. The pre-existing APPROVED->mergeable_ready byte-parity
# fixtures and the AC5 fallback below depend on there being no configured threshold
# here; AC4 supplies the threshold explicitly via --approval-threshold.
export POLARIS_WORKSPACE_ROOT="$TMPROOT"

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

# field_of_disp emits a classifier field with a disposition file applied. Args:
# $1 = snapshot json path, $2 = disposition json path, $3 = field key.
field_of_disp() {
  local path="$1" disp="$2" field="$3"
  bash "$CLASSIFIER" --snapshot-json "$path" --disposition "$disp" --format field --field "$field"
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

# AC2: an approved, otherwise-mergeable PR that still carries an unaddressed
# substantive human conversation comment must NOT report mergeable_ready; it must
# emit needs_disposition so the runner routes it back for agent disposition.
SN7="$TMPROOT/unaddressed-human-comment.json"
emit_snapshot "$SN7" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"unaddressed_human_comments":[{"id":"C1","author_login":"reviewer","author_typename":"User"}]}'
assert_eq "unaddressed-comment action" "$(field_of "$SN7" action_class)" "needs_disposition"
assert_eq "unaddressed-comment readiness" "$(field_of "$SN7" readiness_state)" "needs_code_changes"

# AC-NEG1: only a bot comment exists. The snapshot layer already filters bot
# authors, so the classifier sees an empty unaddressed_human_comments list and
# must fall through to the normal approved -> mergeable_ready path.
SN8="$TMPROOT/bot-only-comment.json"
emit_snapshot "$SN8" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"unaddressed_human_comments":[]}'
assert_eq "bot-only-comment action" "$(field_of "$SN8" action_class)" "ready_to_merge"
assert_eq "bot-only-comment readiness" "$(field_of "$SN8" readiness_state)" "mergeable_ready"

# AC-NEG2: a human conversation comment that has been dispositioned (fixed /
# reply_only / not_actionable) via the --disposition file must no longer trigger
# needs_disposition; the PR returns to mergeable_ready.
SN9="$TMPROOT/disposed-human-comment.json"
emit_snapshot "$SN9" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"unaddressed_human_comments":[{"id":"C1","author_login":"reviewer","author_typename":"User"}]}'
DISP9="$TMPROOT/disposed-human-comment.disposition.json"
emit_snapshot "$DISP9" '{"comments":[{"comment_id":"C1","disposition":"reply_only"}]}'
assert_eq "disposed-comment action" "$(field_of_disp "$SN9" "$DISP9" action_class)" "ready_to_merge"
assert_eq "disposed-comment readiness" "$(field_of_disp "$SN9" "$DISP9" readiness_state)" "mergeable_ready"

# AC-NEG3: a snapshot with no unaddressed_human_comments key at all keeps the
# pre-existing behavior (approved -> mergeable_ready). The six fixtures above
# (SN1..SN6) plus this one establish byte-parity with the prior contract.
SN10="$TMPROOT/no-comment-key.json"
emit_snapshot "$SN10" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true}'
assert_eq "no-comment-key action" "$(field_of "$SN10" action_class)" "ready_to_merge"
assert_eq "no-comment-key readiness" "$(field_of "$SN10" readiness_state)" "mergeable_ready"

# ===== Policy-first approval threshold (AC4 / AC5 / AC6 / AC-NF2) =====
# field_of_policy classifies a snapshot with an injected company approval
# threshold and pre-fetched reviews. The --reviews-json seam stands in for the
# live gh review fetch so the policy-first APPROVED branch is exercised without
# a network round-trip. Args: $1 snapshot path, $2 threshold, $3 reviews path,
# $4 field key.
field_of_policy() {
  local path="$1" threshold="$2" reviews="$3" field="$4"
  bash "$CLASSIFIER" --snapshot-json "$path" \
    --approval-threshold "$threshold" --reviews-json "$reviews" \
    --format field --field "$field"
}

# Shared review fixtures against PR head "abc123":
#   REV_ONE_VALID  — one APPROVED review at head (valid) + one at a superseded
#                    commit (stale) -> valid_approvals=1, total_approvals=2.
#   REV_TWO_VALID  — two APPROVED reviews both at head -> valid_approvals=2.
REV_ONE_VALID="$TMPROOT/reviews-one-valid.json"
emit_snapshot "$REV_ONE_VALID" '[{"user":"r1","state":"APPROVED","submitted_at":"2026-01-02T00:00:00Z","commit_id":"abc123"},{"user":"r2","state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z","commit_id":"oldsha"}]'
REV_TWO_VALID="$TMPROOT/reviews-two-valid.json"
emit_snapshot "$REV_TWO_VALID" '[{"user":"r1","state":"APPROVED","submitted_at":"2026-01-02T00:00:00Z","commit_id":"abc123"},{"user":"r2","state":"APPROVED","submitted_at":"2026-01-02T00:00:00Z","commit_id":"abc123"}]'

# An otherwise-mergeable APPROVED PR whose head is abc123.
SNP="$TMPROOT/approved-head-abc123.json"
emit_snapshot "$SNP" '{"resolver":{"intent":"mutable","mutable_allowed":true},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"head_sha":"abc123"}'

# AC6: the shared valid-approval counter (scripts/lib/pr-approval-count.sh) is the
# single source of truth. One valid + one stale approval against head abc123 ->
# valid_approvals=1, total_approvals=2, has_stale=true.
count_json="$(bash "$APPROVAL_COUNT_LIB" --head-sha abc123 --reviews-json "$REV_ONE_VALID")"
assert_eq "AC6 shared-counter valid_approvals" "$(echo "$count_json" | jq -r '.valid_approvals')" "1"
assert_eq "AC6 shared-counter total_approvals" "$(echo "$count_json" | jq -r '.total_approvals')" "2"
assert_eq "AC6 shared-counter has_stale" "$(echo "$count_json" | jq -r '.has_stale')" "true"

# AC4: company threshold=2 but only 1 valid approval -> NOT mergeable_ready.
# The classifier must consume the shared counter, not the raw reviewDecision.
assert_eq "AC4 below-threshold action" "$(field_of_policy "$SNP" 2 "$REV_ONE_VALID" action_class)" "reviewer_handoff"
assert_eq "AC4 below-threshold readiness" "$(field_of_policy "$SNP" 2 "$REV_ONE_VALID" readiness_state)" "review_required"

# AC4 met: threshold=2 with 2 valid approvals -> mergeable_ready (via shared counter).
assert_eq "AC4 met action" "$(field_of_policy "$SNP" 2 "$REV_TWO_VALID" action_class)" "ready_to_merge"
assert_eq "AC4 met readiness" "$(field_of_policy "$SNP" 2 "$REV_TWO_VALID" readiness_state)" "mergeable_ready"

# AC4 threshold=1 with 1 valid approval -> mergeable_ready (parity with lib count).
assert_eq "AC4 threshold-one met readiness" "$(field_of_policy "$SNP" 1 "$REV_ONE_VALID" readiness_state)" "mergeable_ready"

# AC5: no company approval_threshold configured (no flag, empty workspace config)
# -> fall back to repo branch-protection reviewDecision (APPROVED) -> mergeable_ready.
assert_eq "AC5 fallback action" "$(field_of "$SNP" action_class)" "ready_to_merge"
assert_eq "AC5 fallback readiness" "$(field_of "$SNP" readiness_state)" "mergeable_ready"

# AC-NF2: the policy-first branch is pure PR-state logic with no source-type fast
# path — a DP-backed snapshot and a JIRA-Epic-backed snapshot (source_type hint on
# the resolver) reach the identical threshold decision.
SNP_SRC="$TMPROOT/approved-with-source-hint.json"
emit_snapshot "$SNP_SRC" '{"resolver":{"intent":"mutable","mutable_allowed":true,"source_type":"jira"},"mergeability":"clean","base_freshness":"fresh","ci_state":"GREEN","review_decision":"APPROVED","actionable_unresolved_threads":0,"deferred_threads":0,"evidence_head_sha_match":true,"head_sha":"abc123"}'
assert_eq "AC-NF2 jira-source below-threshold" "$(field_of_policy "$SNP_SRC" 2 "$REV_ONE_VALID" readiness_state)" "review_required"
assert_eq "AC-NF2 dp-source below-threshold" "$(field_of_policy "$SNP" 2 "$REV_ONE_VALID" readiness_state)" "review_required"

# AC-NF2 met-threshold parity: threshold=2 with 2 valid approvals reaches
# mergeable_ready identically for the JIRA-Epic-backed and DP-backed snapshots.
assert_eq "AC-NF2 jira-source met-threshold" "$(field_of_policy "$SNP_SRC" 2 "$REV_TWO_VALID" readiness_state)" "mergeable_ready"
assert_eq "AC-NF2 dp-source met-threshold" "$(field_of_policy "$SNP" 2 "$REV_TWO_VALID" readiness_state)" "mergeable_ready"

# AC-NF2 AC5-fallback parity: with no configured threshold (no flag), both source
# types fall back to branch-protection reviewDecision (APPROVED) -> mergeable_ready.
assert_eq "AC-NF2 jira-source fallback" "$(field_of "$SNP_SRC" readiness_state)" "mergeable_ready"
assert_eq "AC-NF2 dp-source fallback" "$(field_of "$SNP" readiness_state)" "mergeable_ready"

printf 'pr-action-classifier selftest: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
