#!/usr/bin/env bash
# Purpose: Promote a framework feat/DP-NNN release PR head to origin/main by
#          fast-forward push after validating the PR identity and ancestry.
# Inputs:  --repo PATH, --pr NUMBER, --head feat/DP-NNN, --base main,
#          optional --workspace-repo owner/repo, and --execute.
# Outputs: stdout/stderr status lines; POLARIS_* marker on fail-closed errors.
# Exit:    0 PASS, 2 validation or promotion failure.

set -euo pipefail

PREFIX="[framework-release-main-promotion]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_BRANCH="main"
HEAD_BRANCH=""
WORKSPACE_REPO=""
PR_NUMBER=""
EXECUTE=0
GH_BIN="${GH_BIN:-gh}"

usage() {
  cat >&2 <<'EOF'
usage: framework-release-main-promotion.sh --repo <path> --pr <number> --head feat/DP-NNN [options]

Options:
  --repo <path>              Workspace repo path (default: script repo)
  --workspace-repo <owner/repo>
                             GitHub repo slug for gh commands
  --pr <number>              feat/DP-NNN -> main release PR number
  --head <branch>            Release head branch, must be feat/DP-NNN
  --base <branch>            Base branch name (default: main)
  --execute                  Push origin/<base> to the release head by fast-forward
  -h, --help                 Show help

Default mode is dry-run validation: no GitHub or git writes.
EOF
}

die() {
  echo "$PREFIX POLARIS_FRAMEWORK_RELEASE_MAIN_PROMOTION_BLOCKED: $*" >&2
  exit 2
}

info() {
  echo "$PREFIX $*" >&2
}

json_field() {
  local json="$1" expr="$2"
  python3 - "$json" "$expr" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
value = eval(sys.argv[2], {}, {"d": data})
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="$2"; shift 2 ;;
    --repo=*) REPO_PATH="${1#--repo=}"; shift ;;
    --workspace-repo) WORKSPACE_REPO="$2"; shift 2 ;;
    --workspace-repo=*) WORKSPACE_REPO="${1#--workspace-repo=}"; shift ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --pr=*) PR_NUMBER="${1#--pr=}"; shift ;;
    --head) HEAD_BRANCH="$2"; shift 2 ;;
    --head=*) HEAD_BRANCH="${1#--head=}"; shift ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --base=*) BASE_BRANCH="${1#--base=}"; shift ;;
    --execute) EXECUTE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$REPO_PATH/.git" || -f "$REPO_PATH/.git" ]] || die "not a git repository: $REPO_PATH"
[[ -n "$PR_NUMBER" ]] || die "--pr is required"
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || die "--pr must be a number: $PR_NUMBER"
[[ -n "$HEAD_BRANCH" ]] || die "--head is required"
[[ "$HEAD_BRANCH" =~ ^feat/DP-[0-9]+$ ]] || die "--head must be feat/DP-NNN: $HEAD_BRANCH"
[[ -n "$BASE_BRANCH" ]] || die "--base must not be empty"
[[ "$BASE_BRANCH" != "$HEAD_BRANCH" ]] || die "base and head branches must differ"

gh_repo_args=()
if [[ -n "$WORKSPACE_REPO" ]]; then
  gh_repo_args=(--repo "$WORKSPACE_REPO")
fi

git -C "$REPO_PATH" fetch origin "refs/heads/${BASE_BRANCH}:refs/remotes/origin/${BASE_BRANCH}" >/dev/null
git -C "$REPO_PATH" fetch origin "refs/heads/${HEAD_BRANCH}:refs/remotes/origin/${HEAD_BRANCH}" >/dev/null

old_main="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/${BASE_BRANCH}")"
release_head="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/${HEAD_BRANCH}")"

pr_json="$("$GH_BIN" pr view "$PR_NUMBER" ${gh_repo_args[@]+"${gh_repo_args[@]}"} \
  --json number,state,mergeStateStatus,headRefName,headRefOid,baseRefName,url,isDraft)"

pr_state="$(json_field "$pr_json" "d.get('state')")"
pr_base="$(json_field "$pr_json" "d.get('baseRefName')")"
pr_head_branch="$(json_field "$pr_json" "d.get('headRefName')")"
pr_head_oid="$(json_field "$pr_json" "d.get('headRefOid')")"
pr_merge_state="$(json_field "$pr_json" "d.get('mergeStateStatus')")"
pr_url="$(json_field "$pr_json" "d.get('url')")"
pr_is_draft="$(json_field "$pr_json" "d.get('isDraft')")"

[[ "$pr_base" == "$BASE_BRANCH" ]] || die "release PR #$PR_NUMBER base is '$pr_base'; expected '$BASE_BRANCH'"
[[ "$pr_head_branch" == "$HEAD_BRANCH" ]] || die "release PR #$PR_NUMBER head is '$pr_head_branch'; expected '$HEAD_BRANCH'"
[[ "$pr_head_oid" == "$release_head" ]] || die "release PR #$PR_NUMBER head oid is '$pr_head_oid'; expected '$release_head'"
[[ "$pr_state" != "CLOSED" ]] || die "release PR #$PR_NUMBER is CLOSED: $pr_url"
[[ "$pr_is_draft" != "true" ]] || die "release PR #$PR_NUMBER is draft: $pr_url"
case "$pr_merge_state" in
  ""|"UNKNOWN"|"CLEAN"|"HAS_HOOKS"|"UNSTABLE") ;;
  *) die "release PR #$PR_NUMBER mergeStateStatus is '$pr_merge_state'; refusing promotion" ;;
esac

if ! git -C "$REPO_PATH" merge-base --is-ancestor "$old_main" "$release_head"; then
  die "origin/$BASE_BRANCH is not an ancestor of $HEAD_BRANCH. Rebase $HEAD_BRANCH onto origin/$BASE_BRANCH before framework-release promotion."
fi

if [[ "$old_main" == "$release_head" ]]; then
  echo "$PREFIX PASS: origin/$BASE_BRANCH already equals $HEAD_BRANCH head $release_head"
  exit 0
fi

if git -C "$REPO_PATH" log --merges --format='%H' "${old_main}..${release_head}" | grep -q .; then
  die "$HEAD_BRANCH introduces merge commits into ${BASE_BRANCH}. Rebase/linearize the feat branch before promotion."
fi

if [[ "$EXECUTE" != "1" ]]; then
  echo "$PREFIX PASS: dry-run validated PR #$PR_NUMBER for fast-forward promotion ${BASE_BRANCH} -> $release_head"
  exit 0
fi

info "fast-forwarding origin/$BASE_BRANCH to $HEAD_BRANCH ($release_head) via PR-gated promotion"
git -C "$REPO_PATH" push origin "${release_head}:refs/heads/${BASE_BRANCH}" >/dev/null
git -C "$REPO_PATH" fetch origin "refs/heads/${BASE_BRANCH}:refs/remotes/origin/${BASE_BRANCH}" >/dev/null

new_main="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/${BASE_BRANCH}")"
[[ "$new_main" == "$release_head" ]] || die "post-promotion origin/$BASE_BRANCH is '$new_main'; expected '$release_head'"
if git -C "$REPO_PATH" log --merges --format='%H' "${old_main}..refs/remotes/origin/${BASE_BRANCH}" | grep -q .; then
  die "post-promotion origin/$BASE_BRANCH contains merge commits between $old_main and $release_head"
fi

echo "$PREFIX PASS: origin/$BASE_BRANCH fast-forwarded to $HEAD_BRANCH head $release_head"
