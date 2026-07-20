#!/usr/bin/env bash
set -euo pipefail

PREFIX="[framework-release-preflight]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
TASK_MD=""
PR_URL=""
PR_HEAD_SHA=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/framework-release-preflight.sh --repo <workspace-repo> --task-md <task.md> [--pr-url <url>] [--pr-head-sha <sha>]

Validates framework-release preflight authority:
  1. remote PR head has head-bound PR create evidence;
  2. aggregate verify-AC V artifact has release-eligible disposition;
  3. release checkout is clean before closeout.
USAGE
}

die() {
  echo "$PREFIX BLOCKED: $1" >&2
  exit 2
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$path")")
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --pr-url|--workspace-pr-url) PR_URL="${2:-}"; shift 2 ;;
    --pr-head-sha) PR_HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$REPO_ROOT" && -n "$TASK_MD" ]] || { usage; exit 64; }
[[ -d "$REPO_ROOT" ]] || die "repo not found: $REPO_ROOT"
[[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"

REPO_ROOT="$(abs_path "$REPO_ROOT")"
TASK_MD="$(abs_path "$TASK_MD")"

[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || die "repo is not a git checkout: $REPO_ROOT"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  die "release worktree must be clean before framework-release closeout: $REPO_ROOT"
fi

task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field task_jira_key 2>/dev/null || true)"
case "$task_id" in
  ""|N/A|null)
    task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field task_id 2>/dev/null || true)"
    ;;
esac
[[ -n "$task_id" && "$task_id" != "N/A" && "$task_id" != "null" ]] || die "cannot resolve task identity from $TASK_MD"

if [[ -z "$PR_URL" ]]; then
  PR_URL="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field deliverable_pr_url 2>/dev/null || true)"
fi
[[ -n "$PR_URL" && "$PR_URL" != "N/A" && "$PR_URL" != "null" ]] || die "workspace PR URL is required"

parse_pr_url() {
  python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" parse-pr-url "$1"
}

parsed="$(parse_pr_url "$PR_URL")" || die "workspace PR URL is not a GitHub PR URL: $PR_URL"
gh_repo="${parsed%%$'\t'*}"
pr_number="${parsed##*$'\t'}"

if [[ -z "$PR_HEAD_SHA" ]]; then
  command -v gh >/dev/null 2>&1 || die "gh is required to verify remote PR head"
  PR_HEAD_SHA="$(gh pr view "$PR_URL" --repo "$gh_repo" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
[[ "$PR_HEAD_SHA" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "cannot resolve remote PR head SHA for $PR_URL"

resolve_evidence_repo() {
  local repo="$1"
  local common_git_dir=""
  if common_git_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    if [[ "$(basename "$common_git_dir")" == ".git" ]]; then
      dirname "$common_git_dir"
      return
    fi
  fi
  printf '%s\n' "$repo"
}

evidence_repo="$(resolve_evidence_repo "$REPO_ROOT")"
evidence_dir="${POLARIS_PR_CREATE_EVIDENCE_DIR:-$evidence_repo/.polaris/evidence/pr-create}"
pr_evidence="$evidence_dir/${task_id}-${PR_HEAD_SHA}.json"
[[ -f "$pr_evidence" ]] || die "missing head-bound PR create evidence: $pr_evidence"

python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" validate-pr-evidence \
  "$pr_evidence" "$task_id" "$PR_HEAD_SHA" "$PR_URL" "$pr_number" \
  || die "PR create evidence does not match remote PR head"

source_container="$(python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" source-container "$TASK_MD")" \
  || die "cannot resolve source container for $TASK_MD"

python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" verify-ac-release-eligible "$source_container" \
  || die "verify-AC disposition is missing or not release-eligible"

preflight_dir="${POLARIS_RELEASE_PREFLIGHT_DIR:-$evidence_repo/.polaris/evidence/framework-release-preflight}"
preflight_path="$preflight_dir/${task_id}-${PR_HEAD_SHA}.json"
python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" write-preflight \
  "$preflight_path" "$task_id" "$PR_HEAD_SHA" "$PR_URL" "$pr_evidence" "$TASK_MD"
