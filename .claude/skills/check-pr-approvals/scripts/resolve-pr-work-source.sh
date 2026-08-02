#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
RESOLVE_TASK_MD_BY_BRANCH="${SCRIPT_DIR}/resolve-task-md-by-branch.sh"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

usage() {
  cat >&2 <<'EOF'
usage: resolve-pr-work-source.sh [--repo PATH] [--task-md PATH] [--pr-json PATH]
                                 [--pr NUMBER|URL] [--intent mutable|read-only]
                                 [--aggregate-release] [--format json|field]
                                 [--field KEY]

Outputs:
  json (default) or a single field from the resolved work-source snapshot.
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

parse_pr_url() {
  local value="$1"
  python3 - "$value" <<'PY'
import re
import sys

value = sys.argv[1].strip()
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", value)
if not match:
    raise SystemExit(1)
print("\t".join(match.groups()))
PY
}

json_field() {
  local path="$1"
  local field="$2"
  python3 - "$path" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:3]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

value = data.get(field)
if value is None:
    raise SystemExit(1)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

REPO=""
TASK_MD=""
PR_JSON=""
PR_INPUT=""
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
    --intent) INTENT="${2:-}"; shift 2 ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "resolve-pr-work-source: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$INTENT" in
  mutable|read-only) ;;
  *) echo "resolve-pr-work-source: invalid --intent: $INTENT" >&2; exit 2 ;;
esac

case "$FORMAT" in
  json|field) ;;
  *) echo "resolve-pr-work-source: invalid --format: $FORMAT" >&2; exit 2 ;;
esac

if [[ "$FORMAT" == "field" && -z "$FIELD" ]]; then
  echo "resolve-pr-work-source: --field is required when --format field" >&2
  exit 2
fi

if [[ -n "$TASK_MD" && ! -f "$TASK_MD" ]]; then
  echo "resolve-pr-work-source: --task-md not found: $TASK_MD" >&2
  exit 2
fi

if [[ -n "$PR_JSON" && ! -f "$PR_JSON" ]]; then
  echo "resolve-pr-work-source: --pr-json not found: $PR_JSON" >&2
  exit 2
fi

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(abs_path "$REPO")"

TMP_PR_JSON=""
TMP_TASK_JSON=""
cleanup() {
  if [[ -n "$TMP_PR_JSON" ]]; then
    rm -f "$TMP_PR_JSON"
  fi
  if [[ -n "$TMP_TASK_JSON" ]]; then
    rm -f "$TMP_TASK_JSON"
  fi
}
trap cleanup EXIT

if [[ -z "$PR_JSON" && -n "$PR_INPUT" ]]; then
  gh_repo=""
  pr_number=""
  if [[ "$PR_INPUT" =~ ^https://github\.com/ ]]; then
    read -r owner repo_name pr_number < <(parse_pr_url "$PR_INPUT")
    gh_repo="${owner}/${repo_name}"
  else
    gh_repo="$(polaris_github_repo_slug "$REPO" 2>/dev/null || true)"
    pr_number="$PR_INPUT"
  fi
  if [[ -n "$gh_repo" && -n "$pr_number" ]] && declare -F polaris_pr_view_rest >/dev/null 2>&1; then
    TMP_PR_JSON="$(mktemp -t polaris-pr-work-source-pr.XXXXXX.json)"
    polaris_pr_view_rest "$gh_repo" "$pr_number" >"$TMP_PR_JSON"
    PR_JSON="$TMP_PR_JSON"
  fi
fi

if [[ -z "$PR_JSON" ]] && declare -F polaris_current_branch_pr_rest >/dev/null 2>&1; then
  TMP_PR_JSON="$(mktemp -t polaris-pr-work-source-current.XXXXXX.json)"
  if polaris_current_branch_pr_rest "$REPO" >"$TMP_PR_JSON" 2>/dev/null; then
    PR_JSON="$TMP_PR_JSON"
  else
    rm -f "$TMP_PR_JSON"
    TMP_PR_JSON=""
  fi
fi

CURRENT_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
PR_HEAD_BRANCH=""
if [[ -n "$PR_JSON" ]]; then
  PR_HEAD_BRANCH="$(json_field "$PR_JSON" "headRefName" 2>/dev/null || true)"
fi

if [[ -z "$TASK_MD" ]]; then
  lookup_branch="${PR_HEAD_BRANCH:-$CURRENT_BRANCH}"
  if [[ -n "$lookup_branch" && -f "$RESOLVE_TASK_MD_BY_BRANCH" ]]; then
    TASK_MD="$(bash "$RESOLVE_TASK_MD_BY_BRANCH" --scan-root "$REPO" "$lookup_branch" 2>/dev/null | head -n 1 || true)"
  fi
fi

if [[ -n "$TASK_MD" ]]; then
  TASK_MD="$(abs_path "$TASK_MD")"
  TMP_TASK_JSON="$(mktemp -t polaris-pr-work-source-task.XXXXXX.json)"
  bash "$PARSE_TASK_MD" "$TASK_MD" >"$TMP_TASK_JSON"
fi

python3 - "$REPO" "${TASK_MD:-__NULL__}" "${TMP_TASK_JSON:-__NULL__}" \
  "${PR_JSON:-__NULL__}" "$INTENT" "$AGGREGATE_RELEASE" "$CURRENT_BRANCH" \
  "$FORMAT" "${FIELD:-__NULL__}" <<'PY'
import json
import re
import sys
from pathlib import Path


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
    state = str(data.get("state") or "").upper()
    head = data.get("head") if isinstance(data.get("head"), dict) else {}
    base = data.get("base") if isinstance(data.get("base"), dict) else {}
    return {
        "number": data.get("number"),
        "url": data.get("url") or data.get("html_url"),
        "state": state or "UNKNOWN",
        "headRefName": data.get("headRefName") or head.get("ref"),
        "headRefOid": data.get("headRefOid") or head.get("sha"),
        "baseRefName": data.get("baseRefName") or base.get("ref"),
        "mergeStateStatus": data.get("mergeStateStatus") or data.get("mergeable_state") or data.get("mergeable"),
        "reviewDecision": data.get("reviewDecision"),
    }


def parse_chain(raw):
    if not raw:
        return []
    parts = [
        item.strip().strip("`")
        for item in re.split(r"\s*(?:->|→|,|\n)\s*", raw)
        if item.strip().strip("`")
    ]
    chain = []
    for item in parts:
      if not chain or chain[-1] != item:
        chain.append(item)
    return chain


def is_external_base(branch):
    if not branch:
        return False
    return not (
        branch in {"main", "master", "develop"}
        or branch.startswith("task/")
        or branch.startswith("feat/")
    )


repo, task_md, task_json_path, pr_json_path, intent, aggregate_release, current_branch, fmt, field = sys.argv[1:10]
task = load_json(task_json_path) or {}
pr = normalize_pr(load_json(pr_json_path))

task_identity = task.get("identity") or {}
task_ctx = task.get("operational_context") or {}
task_meta = task.get("metadata") or {}

declared_base = maybe_null(task_ctx.get("base_branch"))
authoritative_base = maybe_null(task.get("resolved_base")) or declared_base or maybe_null(pr.get("baseRefName"))
task_branch = maybe_null(task_ctx.get("task_branch"))
branch_chain = parse_chain(task_ctx.get("branch_chain"))
head_branch = maybe_null(pr.get("headRefName")) or maybe_null(task_branch) or maybe_null(current_branch)
head_sha = maybe_null(pr.get("headRefOid"))

has_task = task_md != "__NULL__"
aggregate = aggregate_release == "1"
pr_type = "no_task_legacy"
ownership = "no_task"

if aggregate:
    pr_type = "aggregate_release"
    ownership = "aggregate_release"
    authoritative_base = "main"
elif has_task and is_external_base(authoritative_base):
    pr_type = "external_base"
    ownership = "external_base"
elif has_task and (str(task_branch or "").startswith("feat/") or str(head_branch or "").startswith("feat/")):
    pr_type = "feature"
    ownership = "feature_branch"
elif has_task and (
    str(authoritative_base or "").startswith("task/")
    or (len(branch_chain) >= 3 and any(branch.startswith("task/") for branch in branch_chain[:-1]))
):
    pr_type = "stacked_task"
    ownership = "task_managed"
elif has_task:
    pr_type = "direct_task"
    ownership = "task_managed"
elif str(head_branch or "").startswith("feat/"):
    pr_type = "feature"
    ownership = "feature_branch"
elif is_external_base(pr.get("baseRefName")):
    pr_type = "external_base"
    ownership = "external_base"

unsupported_reason = None
mutable_allowed = True
if intent == "mutable":
    if pr_type == "no_task_legacy":
        mutable_allowed = False
        unsupported_reason = "missing_task_authority"
    elif pr_type == "external_base":
        mutable_allowed = False
        unsupported_reason = "external_base_authority"

work_item_id = maybe_null(task_identity.get("work_item_id")) or maybe_null(task_ctx.get("task_id"))
result = {
    "repo": repo,
    "intent": intent,
    "pr_type": pr_type,
    "ownership": ownership,
    "task_md": None if task_md == "__NULL__" else task_md,
    "source_type": maybe_null(task_identity.get("source_type")) or "unknown",
    "source_id": maybe_null(task_identity.get("source_id")),
    "work_item_id": work_item_id,
    "jira_key": maybe_null(task_identity.get("jira_key")),
    "repo_name": maybe_null(task_meta.get("repo")),
    "pr_number": pr.get("number"),
    "pr_url": maybe_null(pr.get("url")),
    "pr_state": pr.get("state") or "UNKNOWN",
    "head_branch": head_branch,
    "head_sha": head_sha,
    "task_branch": task_branch,
    "branch_chain": branch_chain,
    "declared_base": declared_base,
    "authoritative_base": authoritative_base,
    "pr_base_ref": maybe_null(pr.get("baseRefName")),
    "merge_state_status": maybe_null(pr.get("mergeStateStatus")),
    "mutable_allowed": mutable_allowed,
    "unsupported_reason": unsupported_reason,
}

if fmt == "field":
    key = None if field == "__NULL__" else field
    if key not in result:
        raise SystemExit(f"resolve-pr-work-source: unknown field: {key}")
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
