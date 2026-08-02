#!/usr/bin/env bash
# Classify PR review state for routing decisions.
#
# Usage:
#   pr-review-state-classifier.sh --pr-json PATH [--threads-json PATH] [--disposition PATH]
#
# Inputs accept either `gh pr view --json ...` style JSON or GraphQL fixtures
# containing `data.repository.pullRequest`.

set -uo pipefail

PR_JSON=""
THREADS_JSON=""
DISPOSITION_JSON=""

usage() {
  cat >&2 <<'EOF'
Usage:
  pr-review-state-classifier.sh --pr-json PATH [--threads-json PATH] [--disposition PATH]

Outputs JSON with:
  classification, route, ci_state, review_decision, active_unresolved_threads,
  actionable_unresolved_threads, disposed_unresolved_threads, deferred_threads
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr-json) PR_JSON="${2:-}"; shift 2 ;;
    --threads-json) THREADS_JSON="${2:-}"; shift 2 ;;
    --disposition) DISPOSITION_JSON="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "pr-review-state-classifier: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$PR_JSON" || ! -f "$PR_JSON" ]]; then
  echo "pr-review-state-classifier: --pr-json is required and must exist" >&2
  usage
  exit 2
fi
if [[ -n "$THREADS_JSON" && ! -f "$THREADS_JSON" ]]; then
  echo "pr-review-state-classifier: --threads-json not found: $THREADS_JSON" >&2
  exit 2
fi
if [[ -n "$DISPOSITION_JSON" && ! -f "$DISPOSITION_JSON" ]]; then
  echo "pr-review-state-classifier: --disposition not found: $DISPOSITION_JSON" >&2
  exit 2
fi

python3 - "$PR_JSON" "${THREADS_JSON:-}" "${DISPOSITION_JSON:-}" <<'PY'
import json
import sys
from pathlib import Path


def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"FAIL: invalid JSON {path}: {exc}")


def pull_request(obj):
    if not isinstance(obj, dict):
        return {}
    try:
        pr = obj["data"]["repository"]["pullRequest"]
        if isinstance(pr, dict):
            return pr
    except Exception:
        pass
    pr = obj.get("pullRequest")
    if isinstance(pr, dict):
        return pr
    return obj


def upper(value):
    return str(value or "").strip().upper()


def ci_state(rollup):
    if not rollup:
        return "UNKNOWN"

    has_pending = False
    for item in rollup:
        typename = item.get("__typename", "")
        state = upper(item.get("state"))
        status = upper(item.get("status"))
        conclusion = upper(item.get("conclusion"))

        if typename == "StatusContext" or state:
            if state == "SUCCESS":
                continue
            if state in {"FAILURE", "ERROR"}:
                return "FAIL"
            if state:
                has_pending = True
                continue

        if typename == "CheckRun" or status or conclusion:
            if status and status != "COMPLETED":
                has_pending = True
                continue
            if conclusion in {"SUCCESS", "NEUTRAL", "SKIPPED"}:
                continue
            if conclusion in {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"}:
                return "FAIL"
            has_pending = True

    return "PENDING" if has_pending else "GREEN"


def review_threads(pr):
    return (((pr.get("reviewThreads") or {}).get("nodes")) or [])


def load_dispositions(path):
    if not path:
        return {}
    data = load_json(path)
    entries = data.get("threads")
    if not isinstance(entries, list):
        raise SystemExit("FAIL: disposition JSON must contain threads[]")
    out = {}
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SystemExit(f"FAIL: disposition threads[{idx}] must be an object")
        thread_id = str(entry.get("thread_id") or "").strip()
        disposition = str(entry.get("disposition") or "").strip()
        reason = str(entry.get("reason") or "").strip()
        if not thread_id:
            raise SystemExit(f"FAIL: disposition threads[{idx}].thread_id is required")
        if disposition not in {"fixed", "reply_only", "not_actionable", "deferred_with_reason"}:
            raise SystemExit(f"FAIL: unsupported disposition for {thread_id}: {disposition}")
        if len(reason) < 8:
            raise SystemExit(f"FAIL: disposition reason too short for {thread_id}")
        out[thread_id] = disposition
    return out


pr_path, threads_path, disposition_path = sys.argv[1], sys.argv[2], sys.argv[3]
pr = pull_request(load_json(pr_path))
if threads_path:
    thread_pr = pull_request(load_json(threads_path))
    if thread_pr:
        pr = {**pr, "reviewThreads": thread_pr.get("reviewThreads")}

review_decision = upper(pr.get("reviewDecision"))
state = upper(pr.get("state"))
ci = ci_state(pr.get("statusCheckRollup") or [])
dispositions = load_dispositions(disposition_path)

active_threads = [
    thread for thread in review_threads(pr)
    if not thread.get("isResolved") and not thread.get("isOutdated")
]

disposed = []
deferred = []
actionable = []
non_actionable_dispositions = {"fixed", "reply_only", "not_actionable"}
for thread in active_threads:
    disposition = dispositions.get(str(thread.get("id") or ""))
    if disposition in non_actionable_dispositions:
        disposed.append(thread)
    elif disposition == "deferred_with_reason":
        deferred.append(thread)
    else:
        actionable.append(thread)

classification = "READY"
route = "none"
reason = "no blocking signal"

if state and state not in {"OPEN", "UNKNOWN"}:
    classification = f"PR_{state}"
    route = "none"
    reason = f"pull request state is {state.lower()}"
elif ci == "FAIL":
    classification = "CI_RED"
    route = "engineering"
    reason = "one or more PR checks failed"
elif ci == "PENDING":
    classification = "CI_PENDING"
    route = "wait"
    reason = "one or more PR checks are pending"
elif actionable:
    classification = "HAS_UNRESOLVED_COMMENTS"
    route = "engineering"
    reason = "active unresolved review threads still need disposition or code changes"
elif deferred:
    classification = "REVIEW_THREAD_DEFERRED"
    route = "manual"
    reason = "active unresolved review thread is explicitly deferred"
elif review_decision == "CHANGES_REQUESTED" and ci == "GREEN":
    classification = "AWAITING_RE_REVIEW"
    route = "check-pr-approvals"
    reason = "changes-requested review remains, but CI is green and no active unresolved actionable thread remains"
elif review_decision in {"REVIEW_REQUIRED", ""} and ci == "GREEN":
    classification = "REVIEW_STUCK"
    route = "check-pr-approvals"
    reason = "PR needs reviewer attention"
elif review_decision == "APPROVED" and ci == "GREEN":
    classification = "READY_TO_MERGE"
    route = "none"
    reason = "approved and CI green"

print(json.dumps({
    "classification": classification,
    "route": route,
    "reason": reason,
    "ci_state": ci,
    "review_decision": review_decision or "UNKNOWN",
    "active_unresolved_threads": len(active_threads),
    "actionable_unresolved_threads": len(actionable),
    "disposed_unresolved_threads": len(disposed),
    "deferred_threads": len(deferred),
}, ensure_ascii=False, indent=2, sort_keys=True))
PY
