#!/usr/bin/env bash
# Purpose: Classify a PR's next actionable state (action_class / readiness_state /
#          claim_allowed) from a pr-state-snapshot, per pr-state-contract.md vocabulary.
# Inputs:  --snapshot-json PATH (or snapshot passthrough args), optional --disposition PATH,
#          --format json|field, --field KEY.
# Outputs: classifier result on stdout (json or a single field); exit 2 on contract violation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="${SCRIPT_DIR}/pr-state-snapshot.sh"
APPROVAL_COUNT_LIB="${SCRIPT_DIR}/lib/pr-approval-count.sh"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

usage() {
  cat >&2 <<'EOF'
usage: pr-action-classifier.sh [--snapshot-json PATH]
                               [--repo PATH] [--task-md PATH] [--pr-json PATH]
                               [--pr NUMBER|URL] [--checks-json PATH]
                               [--threads-json PATH] [--disposition PATH]
                               [--intent mutable|read-only] [--aggregate-release]
                               [--approval-threshold N] [--reviews-json PATH]
                               [--format json|field] [--field KEY]
EOF
}

SNAPSHOT_JSON=""
DISPOSITION_JSON=""
FORWARD_ARGS=()
FORMAT="json"
FIELD=""
REPO_PATH=""
# --approval-threshold overrides the company config lookup (used by selftests and
# explicit callers). --reviews-json injects a pre-fetched reviews array so the
# policy-first count runs without a live gh fetch.
APPROVAL_THRESHOLD_OVERRIDE=""
REVIEWS_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot-json) SNAPSHOT_JSON="${2:-}"; shift 2 ;;
    --disposition) DISPOSITION_JSON="${2:-}"; FORWARD_ARGS+=("$1" "$2"); shift 2 ;;
    --approval-threshold) APPROVAL_THRESHOLD_OVERRIDE="${2:-}"; shift 2 ;;
    --reviews-json) REVIEWS_JSON="${2:-}"; shift 2 ;;
    --repo) REPO_PATH="${2:-}"; FORWARD_ARGS+=("$1" "$2"); shift 2 ;;
    --format) FORMAT="${2:-}"; FORWARD_ARGS+=("$1" "$2"); shift 2 ;;
    --field) FIELD="${2:-}"; FORWARD_ARGS+=("$1" "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) FORWARD_ARGS+=("$1"); shift ;;
  esac
done

case "$FORMAT" in
  json|field) ;;
  *) echo "pr-action-classifier: invalid --format: $FORMAT" >&2; exit 2 ;;
esac

if [[ -z "$SNAPSHOT_JSON" ]]; then
  SNAPSHOT_JSON="$(mktemp -t polaris-pr-action-snapshot.XXXXXX.json)"
  trap 'rm -f "$SNAPSHOT_JSON"' EXIT
  bash "$SNAPSHOT" "${FORWARD_ARGS[@]}" >"$SNAPSHOT_JSON"
elif [[ ! -f "$SNAPSHOT_JSON" ]]; then
  echo "pr-action-classifier: --snapshot-json not found: $SNAPSHOT_JSON" >&2
  exit 2
fi

# Sentinel passed to the python layer when no company approval threshold applies
# (AC5 fallback to repo branch-protection reviewDecision) or when the valid-approval
# count is not needed.
NULL_TOKEN="__NULL__"

# resolve_approval_threshold echoes the company approval threshold or empty.
# Priority: explicit --approval-threshold override > workspace-config.yaml
# scrum.approval_threshold (defaults block, the canonical single place;
# per-repo/company override is a deferred Open Question). Any read failure is
# best-effort empty so an unreadable config falls back to AC5, never crashes.
resolve_approval_threshold() {
  if [[ -n "$APPROVAL_THRESHOLD_OVERRIDE" ]]; then
    printf '%s\n' "$APPROVAL_THRESHOLD_OVERRIDE"
    return 0
  fi
  local config="${POLARIS_WORKSPACE_ROOT:-}/workspace-config.yaml"
  [[ -f "$config" ]] || return 0
  python3 - "$config" <<'PYCFG' 2>/dev/null || true
import sys
try:
    import yaml
    data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    sys.exit(0)
value = ((data.get("defaults") or {}).get("scrum") or {}).get("approval_threshold")
if value is None:
    value = (data.get("scrum") or {}).get("approval_threshold")
if value is not None:
    print(value)
PYCFG
}

# Policy-first approval resolution runs only for an APPROVED PR. When a company
# threshold applies, count valid approvals through the shared canonical counter
# (scripts/lib/pr-approval-count.sh, AC6) using the snapshot head sha and either
# an injected reviews array or a live gh fetch; fail-closed if the count cannot
# be obtained (AC-NF1 approval count fail-closed).
APPROVAL_THRESHOLD="$NULL_TOKEN"
VALID_APPROVALS="$NULL_TOKEN"
snapshot_review_decision="$(jq -r '.review_decision // "UNKNOWN"' "$SNAPSHOT_JSON")"

if [[ "$snapshot_review_decision" == "APPROVED" ]]; then
  threshold="$(resolve_approval_threshold)"
  if [[ -n "$threshold" ]]; then
    APPROVAL_THRESHOLD="$threshold"
    head_sha="$(jq -r '.head_sha // ""' "$SNAPSHOT_JSON")"
    if [[ -z "$head_sha" || "$head_sha" == "null" ]]; then
      echo "pr-action-classifier: cannot count approvals without a PR head sha (fail-closed)" >&2
      exit 2
    fi

    reviews_payload=""
    if [[ -n "$REVIEWS_JSON" ]]; then
      if [[ ! -f "$REVIEWS_JSON" ]]; then
        echo "pr-action-classifier: --reviews-json not found: $REVIEWS_JSON" >&2
        exit 2
      fi
      reviews_payload="$(cat "$REVIEWS_JSON")"
    else
      pr_number="$(jq -r '.resolver.pr_number // ""' "$SNAPSHOT_JSON")"
      gh_repo=""
      if [[ -n "$REPO_PATH" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
        gh_repo="$(polaris_github_repo_slug "$REPO_PATH" 2>/dev/null || true)"
      fi
      if [[ -z "$pr_number" || -z "$gh_repo" ]] || ! command -v gh >/dev/null 2>&1; then
        echo "pr-action-classifier: approval threshold set but reviews are unobtainable (fail-closed)" >&2
        echo "POLARIS_TOOL_MISSING:gh" >&2
        exit 2
      fi
      if ! reviews_payload="$(polaris_gh_api "repos/${gh_repo}/pulls/${pr_number}/reviews" \
        --jq '[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at, commit_id: .commit_id}]')"; then
        echo "pr-action-classifier: gh review fetch failed for ${gh_repo}#${pr_number} (fail-closed)" >&2
        echo "POLARIS_TOOL_AUTH_FAILED:gh" >&2
        exit 2
      fi
    fi

    count_json="$(printf '%s' "$reviews_payload" | bash "$APPROVAL_COUNT_LIB" --head-sha "$head_sha")"
    VALID_APPROVALS="$(printf '%s' "$count_json" | jq -r '.valid_approvals')"
  fi
fi

python3 - "$SNAPSHOT_JSON" "$FORMAT" "${FIELD:-__NULL__}" "${DISPOSITION_JSON:-__NULL__}" \
  "$APPROVAL_THRESHOLD" "$VALID_APPROVALS" <<'PY'
import json
import sys
from pathlib import Path

# Dispositions that mean a conversation comment has been handled and must no
# longer force needs_disposition (parallels the thread disposition vocabulary).
RESOLVED_COMMENT_DISPOSITIONS = {"fixed", "reply_only", "not_actionable"}

snapshot = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
fmt = sys.argv[2]
field = None if sys.argv[3] == "__NULL__" else sys.argv[3]
disposition_path = None if sys.argv[4] == "__NULL__" else sys.argv[4]
# Company approval threshold and the shared-counter valid-approval count, resolved
# in the shell layer. __NULL__ threshold means no company policy applies (AC5).
approval_threshold = None if sys.argv[5] == "__NULL__" else int(sys.argv[5])
valid_approvals = None if sys.argv[6] == "__NULL__" else int(sys.argv[6])
resolver = snapshot.get("resolver") or {}


def load_comment_dispositions(path):
    """Read comment_id -> disposition from a disposition file.

    Args:
        path: Optional path to a disposition JSON file, or None.

    Returns:
        A dict mapping str(comment_id) to its disposition string. Empty when
        no file is given or the file carries no comments[] array.
    """
    if not path:
        return {}
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    result = {}
    for item in data.get("comments") or []:
        comment_id = item.get("comment_id")
        if comment_id is not None:
            result[str(comment_id)] = item.get("disposition")
    return result


comment_dispositions = load_comment_dispositions(disposition_path)
effective_unaddressed_count = 0
for comment in snapshot.get("unaddressed_human_comments") or []:
    comment_id = comment.get("id")
    disposition = comment_dispositions.get(str(comment_id))
    if disposition not in RESOLVED_COMMENT_DISPOSITIONS:
        effective_unaddressed_count += 1

reason = ""
action_class = "planning_gap"
readiness_state = "planning_gap"
claim_allowed = False

if not resolver.get("mutable_allowed", True) and resolver.get("intent") == "mutable":
    action_class = "unsupported_mutation"
    readiness_state = "unsupported_mutation"
    reason = resolver.get("unsupported_reason") or "mutation is not allowed for this PR type"
elif snapshot.get("mergeability") == "conflict":
    action_class = "blocked_conflict"
    readiness_state = "blocked_conflict"
    reason = "PR mergeability reports a conflict"
elif snapshot.get("base_freshness") == "stale_downstream":
    action_class = "rebase_required"
    readiness_state = "blocked_conflict"
    reason = "upstream advanced and downstream branch is stale"
elif snapshot.get("ci_state") == "FAIL":
    action_class = "code_fix"
    readiness_state = "needs_code_changes"
    reason = "one or more PR checks failed"
elif snapshot.get("actionable_unresolved_threads", 0) > 0:
    action_class = "code_fix"
    readiness_state = "needs_code_changes"
    reason = "active unresolved review threads still require code or disposition work"
elif snapshot.get("deferred_threads", 0) > 0:
    action_class = "planning_gap"
    readiness_state = "planning_gap"
    reason = "review threads are explicitly deferred and need a higher-level decision"
elif snapshot.get("evidence_head_sha_match") is False:
    action_class = "code_fix"
    readiness_state = "needs_code_changes"
    reason = "head-bound delivery evidence is stale or does not match the PR head"
elif snapshot.get("required_assignee_missing") is True:
    action_class = "code_fix"
    readiness_state = "needs_code_changes"
    reason = "required PR assignee metadata is missing"
elif snapshot.get("ci_state") in {"PENDING", "UNKNOWN"} or snapshot.get("mergeability") in {"unknown", "blocked"}:
    action_class = "wait_ci"
    readiness_state = "wait_ci"
    reason = "CI or mergeability state is not stable yet"
elif effective_unaddressed_count > 0:
    action_class = "needs_disposition"
    readiness_state = "needs_code_changes"
    reason = "unaddressed human conversation comments require agent disposition"
elif snapshot.get("review_decision") == "CHANGES_REQUESTED":
    action_class = "reviewer_handoff"
    readiness_state = "awaiting_re_review"
    claim_allowed = True
    reason = "changes requested remains, but code/evidence blockers are cleared"
elif snapshot.get("review_decision") == "APPROVED":
    if approval_threshold is None:
        # AC5: no company approval_threshold — fall back to repo branch-protection
        # reviewDecision (APPROVED already implies branch-protection satisfaction).
        action_class = "ready_to_merge"
        readiness_state = "mergeable_ready"
        claim_allowed = True
        reason = "approval via repo branch-protection; no company approval threshold configured"
    elif valid_approvals is not None and valid_approvals >= approval_threshold:
        # AC4: company threshold met by valid (non-stale) approvals.
        action_class = "ready_to_merge"
        readiness_state = "mergeable_ready"
        claim_allowed = True
        reason = f"valid approvals {valid_approvals} meet company threshold {approval_threshold}"
    else:
        # AC4: approved by branch protection but company threshold not yet met.
        action_class = "reviewer_handoff"
        readiness_state = "review_required"
        claim_allowed = True
        reason = f"valid approvals {valid_approvals} below company threshold {approval_threshold}"
else:
    action_class = "reviewer_handoff"
    readiness_state = "review_required"
    claim_allowed = True
    reason = "reviewer attention is the next step"

result = {
    "action_class": action_class,
    "readiness_state": readiness_state,
    "claim_allowed": claim_allowed,
    "reason": reason,
    "snapshot": snapshot,
}

if fmt == "field":
    if field not in result:
        raise SystemExit(f"pr-action-classifier: unknown field: {field}")
    value = result.get(field)
    if isinstance(value, bool):
        print("true" if value else "false")
    elif value is not None:
        print(value)
else:
    print(json.dumps(result, separators=(",", ":")))
PY
