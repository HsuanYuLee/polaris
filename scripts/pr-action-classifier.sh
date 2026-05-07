#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="${SCRIPT_DIR}/pr-state-snapshot.sh"

usage() {
  cat >&2 <<'EOF'
usage: pr-action-classifier.sh [--snapshot-json PATH]
                               [--repo PATH] [--task-md PATH] [--pr-json PATH]
                               [--pr NUMBER|URL] [--checks-json PATH]
                               [--threads-json PATH] [--disposition PATH]
                               [--intent mutable|read-only] [--aggregate-release]
                               [--format json|field] [--field KEY]
EOF
}

SNAPSHOT_JSON=""
FORWARD_ARGS=()
FORMAT="json"
FIELD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot-json) SNAPSHOT_JSON="${2:-}"; shift 2 ;;
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

python3 - "$SNAPSHOT_JSON" "$FORMAT" "${FIELD:-__NULL__}" <<'PY'
import json
import sys
from pathlib import Path

snapshot = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
fmt = sys.argv[2]
field = None if sys.argv[3] == "__NULL__" else sys.argv[3]
resolver = snapshot.get("resolver") or {}

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
elif snapshot.get("ci_state") in {"PENDING", "UNKNOWN"} or snapshot.get("mergeability") in {"unknown", "blocked"}:
    action_class = "wait_ci"
    readiness_state = "wait_ci"
    reason = "CI or mergeability state is not stable yet"
elif snapshot.get("review_decision") == "CHANGES_REQUESTED":
    action_class = "reviewer_handoff"
    readiness_state = "awaiting_re_review"
    claim_allowed = True
    reason = "changes requested remains, but code/evidence blockers are cleared"
elif snapshot.get("review_decision") == "APPROVED":
    action_class = "ready_to_merge"
    readiness_state = "mergeable_ready"
    claim_allowed = True
    reason = "approval, clean mergeability, green CI, and fresh evidence are all present"
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
