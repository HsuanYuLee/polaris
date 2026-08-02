#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-pr-work-source.sh"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

usage() {
  cat >&2 <<'EOF'
usage: pr-state-snapshot.sh [--repo PATH] [--task-md PATH] [--pr-json PATH]
                            [--pr NUMBER|URL] [--checks-json PATH]
                            [--threads-json PATH] [--comments-json PATH]
                            [--disposition PATH]
                            [--intent mutable|read-only]
                            [--aggregate-release] [--format json|field]
                            [--field KEY]
EOF
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
}

REPO=""
TASK_MD=""
PR_JSON=""
PR_INPUT=""
CHECKS_JSON=""
THREADS_JSON=""
COMMENTS_JSON=""
DISPOSITION_JSON=""
INTENT="mutable"
AGGREGATE_RELEASE=0
FORMAT="json"
FIELD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --pr-json) PR_JSON="${2:-}"; shift 2 ;;
    --pr) PR_INPUT="${2:-}"; shift 2 ;;
    --checks-json) CHECKS_JSON="${2:-}"; shift 2 ;;
    --threads-json) THREADS_JSON="${2:-}"; shift 2 ;;
    --comments-json) COMMENTS_JSON="${2:-}"; shift 2 ;;
    --disposition) DISPOSITION_JSON="${2:-}"; shift 2 ;;
    --intent) INTENT="${2:-}"; shift 2 ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "pr-state-snapshot: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$FORMAT" in
  json|field) ;;
  *) echo "pr-state-snapshot: invalid --format: $FORMAT" >&2; exit 2 ;;
esac

if [[ "$FORMAT" == "field" && -z "$FIELD" ]]; then
  echo "pr-state-snapshot: --field is required when --format field" >&2
  exit 2
fi

for file in "$PR_JSON" "$CHECKS_JSON" "$THREADS_JSON" "$COMMENTS_JSON" "$DISPOSITION_JSON"; do
  if [[ -n "$file" && ! -f "$file" ]]; then
    echo "pr-state-snapshot: file not found: $file" >&2
    exit 2
  fi
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(abs_path "$REPO")"

TMP_RESOLVER=""
TMP_CHECKS=""
TMP_THREADS=""
TMP_COMMENTS=""
cleanup() {
  if [[ -n "$TMP_RESOLVER" ]]; then
    rm -f "$TMP_RESOLVER"
  fi
  if [[ -n "$TMP_CHECKS" ]]; then
    rm -f "$TMP_CHECKS"
  fi
  if [[ -n "$TMP_THREADS" ]]; then
    rm -f "$TMP_THREADS"
  fi
  if [[ -n "$TMP_COMMENTS" ]]; then
    rm -f "$TMP_COMMENTS"
  fi
}
trap cleanup EXIT

TMP_RESOLVER="$(mktemp -t polaris-pr-state-resolver.XXXXXX.json)"
bash "$RESOLVER" \
  --repo "$REPO" \
  ${TASK_MD:+--task-md "$TASK_MD"} \
  ${PR_JSON:+--pr-json "$PR_JSON"} \
  ${PR_INPUT:+--pr "$PR_INPUT"} \
  --intent "$INTENT" \
  $([[ "$AGGREGATE_RELEASE" -eq 1 ]] && printf '%s' "--aggregate-release") \
  >"$TMP_RESOLVER"

resolver_pr_number="$(python3 - "$TMP_RESOLVER" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
value = data.get("pr_number")
if value is not None:
    print(value)
PY
)"
resolver_pr_url="$(python3 - "$TMP_RESOLVER" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
value = data.get("pr_url")
if value:
    print(value)
PY
)"

if [[ -z "$CHECKS_JSON" && -n "$resolver_pr_number" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
  gh_repo="$(polaris_github_repo_slug "$REPO" 2>/dev/null || true)"
  if [[ -n "$gh_repo" ]] && declare -F polaris_pr_checks_rest >/dev/null 2>&1; then
    TMP_CHECKS="$(mktemp -t polaris-pr-state-checks.XXXXXX.json)"
    if polaris_pr_checks_rest "$gh_repo" "$resolver_pr_number" >"$TMP_CHECKS" 2>/dev/null; then
      CHECKS_JSON="$TMP_CHECKS"
    else
      rm -f "$TMP_CHECKS"
      TMP_CHECKS=""
    fi
  fi
fi

if [[ -z "$THREADS_JSON" && -n "$resolver_pr_number" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
  gh_repo="$(polaris_github_repo_slug "$REPO" 2>/dev/null || true)"
  if [[ -n "$gh_repo" ]] && command -v gh >/dev/null 2>&1; then
    owner="${gh_repo%%/*}"
    repo_name="${gh_repo#*/}"
    TMP_THREADS="$(mktemp -t polaris-pr-state-threads.XXXXXX.json)"
    if gh api graphql \
      -f owner="$owner" \
      -f repo="$repo_name" \
      -F number="$resolver_pr_number" \
      -f query='query($owner:String!,$repo:String!,$number:Int!){ repository(owner:$owner,name:$repo){ pullRequest(number:$number){ reviewThreads(first:100){ nodes{ id isResolved isOutdated path line originalLine comments(first:20){ nodes{ url } } } } } } }' \
      >"$TMP_THREADS" 2>/dev/null; then
      THREADS_JSON="$TMP_THREADS"
    else
      rm -f "$TMP_THREADS"
      TMP_THREADS=""
    fi
  fi
fi

# Conversation (issue-level) comment fetch. Unlike the review-thread fetch above,
# this lane is fail-closed (AC-NF1): when a PR is resolved but comments can neither
# be injected nor fetched, emit a POLARIS_TOOL_* marker and exit 2 rather than
# fail-open with an empty comment set (which would hide unaddressed human comments).
if [[ -z "$COMMENTS_JSON" && -n "$resolver_pr_number" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
  gh_repo="$(polaris_github_repo_slug "$REPO" 2>/dev/null || true)"
  if [[ -n "$gh_repo" ]]; then
    gh_bin="${GH_BIN:-gh}"
    if ! command -v "$gh_bin" >/dev/null 2>&1; then
      echo "pr-state-snapshot: gh unavailable; cannot fetch conversation comments (fail-closed)" >&2
      echo "POLARIS_TOOL_MISSING:gh" >&2
      exit 2
    fi
    owner="${gh_repo%%/*}"
    repo_name="${gh_repo#*/}"
    TMP_COMMENTS="$(mktemp -t polaris-pr-state-comments.XXXXXX.json)"
    if "$gh_bin" api graphql \
      -f owner="$owner" \
      -f repo="$repo_name" \
      -F number="$resolver_pr_number" \
      -f query='query($owner:String!,$repo:String!,$number:Int!){ repository(owner:$owner,name:$repo){ pullRequest(number:$number){ comments(first:100){ nodes{ id url createdAt authorAssociation author{ __typename login } body } } } } }' \
      >"$TMP_COMMENTS" 2>/dev/null; then
      COMMENTS_JSON="$TMP_COMMENTS"
    else
      rm -f "$TMP_COMMENTS"
      TMP_COMMENTS=""
      echo "pr-state-snapshot: conversation comment fetch failed (fail-closed)" >&2
      echo "POLARIS_TOOL_AUTH_FAILED:gh" >&2
      exit 2
    fi
  fi
fi

python3 - "$REPO" "$SCRIPT_DIR/parse-task-md.sh" "$TMP_RESOLVER" "${PR_JSON:-__NULL__}" "${CHECKS_JSON:-__NULL__}" \
  "${THREADS_JSON:-__NULL__}" "${COMMENTS_JSON:-__NULL__}" "${DISPOSITION_JSON:-__NULL__}" "$FORMAT" "${FIELD:-__NULL__}" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

# GitHub GraphQL __typename for automated (App/bot) comment authors.
BOT_AUTHOR_TYPENAME = "Bot"
# Polaris embeds evidence / status markers as HTML comments; any body carrying one
# is a Polaris-authored automation comment, never an unaddressed human comment.
POLARIS_HTML_MARKER_PREFIX = "<!-- polaris"
# Known-automation body signatures posted under a real account (e.g. a GitHub
# Action using a PAT) so __typename reads "User" but the content is still a bot
# summary. Matched case-insensitively on the raw body.
KNOWN_AUTOMATION_BODY_PATTERNS = [
    re.compile(r"^\s{0,3}#{1,6}\s*claude code review\b", re.IGNORECASE | re.MULTILINE),
    re.compile(r"^\s*claude finished\b", re.IGNORECASE | re.MULTILINE),
]
# A comment whose entire body is a JIRA ticket link is boilerplate (auto-posted
# issue link), not an unaddressed review comment.
JIRA_LINK_BOILERPLATE_RE = re.compile(
    r"^\s*(?:related:?\s*|jira:?\s*|ticket:?\s*)?https?://\S+/browse/[A-Z][A-Z0-9]+-\d+\s*$",
    re.IGNORECASE,
)


def load_json(path):
    if path in {"", "__NULL__"}:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


def maybe_null(value):
    if value in {"", None, "__NULL__"}:
        return None
    return value


def normalize_pr(data):
    if not isinstance(data, dict):
        return {}
    if "pullRequest" in data and isinstance(data["pullRequest"], dict):
        data = data["pullRequest"]
    head = data.get("head") if isinstance(data.get("head"), dict) else {}
    base = data.get("base") if isinstance(data.get("base"), dict) else {}
    state = str(data.get("state") or "").upper() or "UNKNOWN"
    return {
        "state": state,
        "headRefOid": data.get("headRefOid") or head.get("sha"),
        "baseRefName": data.get("baseRefName") or base.get("ref"),
        "mergeStateStatus": data.get("mergeStateStatus") or data.get("mergeable_state") or data.get("mergeable"),
        "reviewDecision": data.get("reviewDecision"),
    }


def normalize_assignees(data):
    if not isinstance(data, dict):
        return None
    if "pullRequest" in data and isinstance(data["pullRequest"], dict):
        data = data["pullRequest"]
    assignees = data.get("assignees")
    if isinstance(assignees, dict):
        assignees = assignees.get("nodes")
    if not isinstance(assignees, list):
        return None
    names = []
    for item in assignees:
        if not isinstance(item, dict):
            continue
        name = str(item.get("login") or item.get("name") or "").strip()
        if name:
            names.append(name)
    return names


def read_pr_assignee_policy(repo):
    start = Path(repo).resolve()
    for root in [start, *start.parents]:
        cfg = root / "workspace-config.yaml"
        if not cfg.exists():
            continue
        for line in cfg.read_text(encoding="utf-8").splitlines():
            match = __import__("re").match(r"\s*pr_assignee_policy\s*:\s*([^#]+)", line)
            if match:
                return match.group(1).strip().strip('"').strip("'") or "required"
    return "required"


def normalize_ci(checks):
    if not checks:
        return "UNKNOWN"
    pending = False
    for item in checks:
        state = str(item.get("state") or item.get("status") or "").upper()
        conclusion = str(item.get("conclusion") or "").upper()
        if state in {"FAILURE", "ERROR", "FAIL"}:
            return "FAIL"
        if conclusion in {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "FAILURE"}:
            return "FAIL"
        if state in {"SUCCESS", "GREEN"} or conclusion in {"SUCCESS", "NEUTRAL", "SKIPPED"}:
            continue
        pending = True
    return "PENDING" if pending else "GREEN"


def normalize_mergeability(value, ci_state):
    raw = str(value or "").upper()
    if raw in {"CLEAN", "HAS_HOOKS", "MERGEABLE", "TRUE"}:
        return "clean"
    if raw == "UNSTABLE" and ci_state == "PENDING":
        return "clean"
    if raw in {"DIRTY", "CONFLICTING", "CONFLICT", "FALSE"}:
        return "conflict"
    if raw in {"BLOCKED", "DRAFT"}:
        return "blocked"
    if raw in {"BEHIND"}:
        return "conflict"
    return "unknown"


def readiness_reason(mergeability, ci_state, raw_mergeability):
    raw = str(raw_mergeability or "").upper()
    if mergeability == "conflict":
        return "merge_conflict"
    if mergeability == "blocked":
        return "blocked_review"
    if raw == "UNSTABLE" and ci_state == "PENDING":
        return "pending_ci"
    if mergeability == "unknown":
        return "mergeability_unknown"
    if ci_state == "FAIL":
        return "failing_ci"
    if ci_state == "PENDING":
        return "pending_ci"
    return "ready"


def load_dispositions(data):
    if not isinstance(data, dict):
        return {}
    out = {}
    for entry in data.get("threads") or []:
        if not isinstance(entry, dict):
            continue
        thread_id = str(entry.get("thread_id") or "").strip()
        disposition = str(entry.get("disposition") or "").strip()
        if thread_id and disposition:
            out[thread_id] = disposition
    return out


def review_stats(threads_data, dispositions):
    pr = {}
    if isinstance(threads_data, dict):
        pr = (((threads_data.get("data") or {}).get("repository") or {}).get("pullRequest")) or threads_data.get("pullRequest") or {}
    nodes = (((pr.get("reviewThreads") or {}).get("nodes")) or []) if isinstance(pr, dict) else []
    unresolved = [thread for thread in nodes if not thread.get("isResolved")]
    active = [thread for thread in unresolved if not thread.get("isOutdated")]
    outdated_unresolved = [thread for thread in unresolved if thread.get("isOutdated")]
    actionable = []
    disposed = []
    deferred = []
    for thread in active:
        disposition = dispositions.get(str(thread.get("id") or ""))
        if disposition in {"fixed", "reply_only", "not_actionable"}:
            disposed.append(thread)
        elif disposition == "deferred_with_reason":
            deferred.append(thread)
        else:
            actionable.append(thread)
    return {
        "loaded": bool(threads_data),
        "total_unresolved": len(unresolved),
        "active": len(active),
        "outdated_unresolved": len(outdated_unresolved),
        "actionable": len(actionable),
        "disposed": len(disposed),
        "deferred": len(deferred),
    }


def normalize_comments(data):
    """Extract issue-level comment nodes from injected or gh-graphql shapes.

    Args:
        data: parsed comments JSON, either the gh graphql envelope
            ({"data":{"repository":{"pullRequest":{"comments":{"nodes":[...]}}}}})
            or the injected shape ({"pullRequest":{"comments":{"nodes":[...]}}}).

    Returns:
        The list of comment nodes, or None when no comment set is present.
    """
    if not isinstance(data, dict):
        return None
    pr = (((data.get("data") or {}).get("repository") or {}).get("pullRequest")) or data.get("pullRequest") or {}
    if not isinstance(pr, dict):
        return None
    nodes = (pr.get("comments") or {}).get("nodes")
    return nodes if isinstance(nodes, list) else None


def is_automation_comment(node):
    """Report whether a conversation comment is automation-authored (AC3).

    Args:
        node: a single comment node with author / authorAssociation / body.

    Returns:
        True when the comment is a bot (typename=Bot), carries a Polaris HTML
        marker, or matches a known-automation body signature (Claude Code Review
        summary, JIRA ticket-link boilerplate); False for genuine human comments.
    """
    author = node.get("author") if isinstance(node.get("author"), dict) else {}
    if str(author.get("__typename") or "") == BOT_AUTHOR_TYPENAME:
        return True
    body = str(node.get("body") or "")
    if POLARIS_HTML_MARKER_PREFIX in body:
        return True
    for pattern in KNOWN_AUTOMATION_BODY_PATTERNS:
        if pattern.search(body):
            return True
    if JIRA_LINK_BOILERPLATE_RE.match(body.strip()):
        return True
    return False


def unaddressed_comment_stats(comments_data):
    """Build the unaddressed_human_comments signal from conversation comments (AC1).

    Args:
        comments_data: parsed comments JSON, or None when not loaded.

    Returns:
        A dict with `loaded` (bool) and `items` (list of human comment records,
        each carrying id / url / author_login / author_typename /
        author_association / body).
    """
    nodes = normalize_comments(comments_data)
    if nodes is None:
        return {"loaded": bool(comments_data), "items": []}
    items = []
    for node in nodes:
        if not isinstance(node, dict) or is_automation_comment(node):
            continue
        author = node.get("author") if isinstance(node.get("author"), dict) else {}
        items.append({
            "id": node.get("id"),
            "url": node.get("url"),
            "author_login": author.get("login") or None,
            "author_typename": author.get("__typename") or None,
            "author_association": node.get("authorAssociation") or None,
            "body": node.get("body") or "",
        })
    return {"loaded": True, "items": items}


def git_ref(repo, name):
    if not name:
        return None
    candidates = [name]
    if "/" not in name:
        candidates.append(f"origin/{name}")
    elif not name.startswith("origin/"):
        candidates.append(f"origin/{name}")
    for candidate in candidates:
        proc = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--verify", "--quiet", candidate],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if proc.returncode == 0:
            return candidate
    return None


def base_freshness(repo, base_branch, head_branch, pr_type):
    if pr_type == "external_base":
        return "external_base"
    if not base_branch or not head_branch:
        return "unknown"
    base_ref = git_ref(repo, base_branch)
    head_ref = git_ref(repo, head_branch)
    if not base_ref or not head_ref:
        return "unknown"
    proc = subprocess.run(
        ["git", "-C", repo, "merge-base", "--is-ancestor", base_ref, head_ref],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return "fresh" if proc.returncode == 0 else "stale_downstream"


repo, parse_task_md, resolver_path, pr_json_path, checks_json_path, threads_json_path, comments_json_path, disposition_json_path, fmt, field = sys.argv[1:11]
resolver = load_json(resolver_path) or {}
raw_pr = load_json(pr_json_path)
pr = normalize_pr(raw_pr)
assignee_names = normalize_assignees(raw_pr)
assignee_policy = read_pr_assignee_policy(repo)
checks = load_json(checks_json_path) or []
threads = load_json(threads_json_path)
comments = load_json(comments_json_path)
dispositions = load_dispositions(load_json(disposition_json_path))

ci_state = normalize_ci(checks)
raw_mergeability = pr.get("mergeStateStatus") or resolver.get("merge_state_status")
mergeability = normalize_mergeability(raw_mergeability, ci_state)
readiness = readiness_reason(mergeability, ci_state, raw_mergeability)
review_decision = str(pr.get("reviewDecision") or "").upper() or "UNKNOWN"
stats = review_stats(threads, dispositions)
comment_stats = unaddressed_comment_stats(comments)

deliverable_head = None
task_md = resolver.get("task_md")
if task_md:
    task_json = json.loads(subprocess.check_output(["bash", parse_task_md, task_md, "--no-resolve"], text=True))
    deliverable_head = (((task_json.get("frontmatter") or {}).get("deliverable") or {}).get("head_sha"))

pr_head = maybe_null(pr.get("headRefOid")) or maybe_null(resolver.get("head_sha"))
evidence_match = None
if deliverable_head and pr_head:
    evidence_match = pr_head == deliverable_head or pr_head.startswith(str(deliverable_head))
elif pr_head:
    current_head = subprocess.run(
        ["git", "-C", repo, "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    )
    if current_head.returncode == 0:
        current_value = current_head.stdout.strip()
        if current_value:
            evidence_match = current_value == pr_head or current_value.startswith(str(pr_head)) or pr_head.startswith(current_value)

result = {
    "resolver": resolver,
    "pr_state": resolver.get("pr_state") or pr.get("state") or "UNKNOWN",
    "base_freshness": base_freshness(repo, resolver.get("authoritative_base"), resolver.get("head_branch"), resolver.get("pr_type")),
    "mergeability": mergeability,
    "raw_mergeability": raw_mergeability,
    "readiness_reason": readiness,
    "ci_state": ci_state,
    "review_decision": review_decision,
    "review_threads_loaded": stats["loaded"],
    "total_unresolved_threads": stats["total_unresolved"],
    "active_unresolved_threads": stats["active"],
    "outdated_unresolved_threads": stats["outdated_unresolved"],
    "actionable_unresolved_threads": stats["actionable"],
    "disposed_unresolved_threads": stats["disposed"],
    "deferred_threads": stats["deferred"],
    "conversation_comments_loaded": comment_stats["loaded"],
    "unaddressed_human_comments": comment_stats["items"],
    "unaddressed_human_comment_count": len(comment_stats["items"]),
    "evidence_head_sha_match": evidence_match,
    "head_branch": resolver.get("head_branch"),
    "head_sha": pr_head,
    "authoritative_base": resolver.get("authoritative_base"),
    "pr_assignee_policy": assignee_policy,
    "pr_assignee_count": None if assignee_names is None else len(assignee_names),
    "required_assignee_missing": assignee_policy in {"", "required"} and assignee_names is not None and len(assignee_names) == 0,
}

if fmt == "field":
    key = None if field == "__NULL__" else field
    if key == "pr_type":
        value = (result.get("resolver") or {}).get("pr_type")
    elif key == "mutable_allowed":
        value = (result.get("resolver") or {}).get("mutable_allowed")
    else:
        if key not in result:
            raise SystemExit(f"pr-state-snapshot: unknown field: {key}")
        value = result.get(key)
    if isinstance(value, list):
        print("\n".join(str(item) for item in value))
    elif isinstance(value, bool):
        print("true" if value else "false")
    elif value is not None:
        print(value)
else:
    print(json.dumps(result, separators=(",", ":")))
PY
