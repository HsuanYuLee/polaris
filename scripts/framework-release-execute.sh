#!/usr/bin/env bash
# Purpose: deterministic framework-release executor for feat-model release tails.
# Inputs:  --repo, --source-id/--feat-branch, and ordered --task-md entries.
# Outputs: executes the requested release-tail phase or fails closed with a
#          POLARIS_FRAMEWORK_RELEASE_EXECUTE_* marker on stderr.
set -euo pipefail

PREFIX="[framework-release-execute]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ID=""
FEAT_BRANCH=""
LAND_TASKS_TO_FEAT=0
FULL_TAIL=0
RELEASE_PR_NUMBER=""
RELEASE_PR_TITLE=""
RELEASE_PR_BODY_FILE=""
TASK_MDS=()

usage() {
  cat >&2 <<'USAGE'
usage:
  framework-release-execute.sh --land-tasks-to-feat --source-id DP-NNN --task-md <path> [--task-md <path> ...] [--repo <path>] [--feat-branch feat/DP-NNN]
  framework-release-execute.sh --full-tail --source-id DP-NNN --task-md <path> [--task-md <path> ...] [--repo <path>] [--feat-branch feat/DP-NNN] [--release-pr <number>]

Executes the deterministic task -> feat landing phase for framework-release.
The ordered --task-md list must describe a single PR or declared stack PR. Full
tail continues through feat rebase, version compression, feat -> main PR
creation, and PR-gated main promotion.
USAGE
  exit 2
}

die() {
  echo "$PREFIX POLARIS_FRAMEWORK_RELEASE_EXECUTE_BLOCKED: $*" >&2
  exit 2
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  else
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    --repo=*) REPO_PATH="${1#--repo=}"; shift ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --source-id=*) SOURCE_ID="${1#--source-id=}"; shift ;;
    --feat-branch) FEAT_BRANCH="${2:-}"; shift 2 ;;
    --feat-branch=*) FEAT_BRANCH="${1#--feat-branch=}"; shift ;;
    --task-md) TASK_MDS+=("$(abs_path "${2:-}")"); shift 2 ;;
    --task-md=*) TASK_MDS+=("$(abs_path "${1#--task-md=}")"); shift ;;
    --land-tasks-to-feat) LAND_TASKS_TO_FEAT=1; shift ;;
    --full-tail) FULL_TAIL=1; LAND_TASKS_TO_FEAT=1; shift ;;
    --release-pr) RELEASE_PR_NUMBER="${2:-}"; shift 2 ;;
    --release-pr=*) RELEASE_PR_NUMBER="${1#--release-pr=}"; shift ;;
    --release-pr-title) RELEASE_PR_TITLE="${2:-}"; shift 2 ;;
    --release-pr-title=*) RELEASE_PR_TITLE="${1#--release-pr-title=}"; shift ;;
    --release-pr-body-file) RELEASE_PR_BODY_FILE="$(abs_path "${2:-}")"; shift 2 ;;
    --release-pr-body-file=*) RELEASE_PR_BODY_FILE="$(abs_path "${1#--release-pr-body-file=}")"; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

REPO_PATH="$(abs_path "$REPO_PATH")"
[[ -d "$REPO_PATH/.git" || -f "$REPO_PATH/.git" ]] || die "not a git repository: $REPO_PATH"
[[ "$LAND_TASKS_TO_FEAT" -eq 1 || "$FULL_TAIL" -eq 1 ]] || die "no execution phase selected; pass --land-tasks-to-feat or --full-tail"
[[ "${#TASK_MDS[@]}" -gt 0 ]] || die "at least one --task-md is required"

if [[ -z "$FEAT_BRANCH" ]]; then
  [[ "$SOURCE_ID" =~ ^DP-[0-9]+$ ]] || die "--source-id DP-NNN is required when --feat-branch is omitted"
  FEAT_BRANCH="feat/${SOURCE_ID}"
fi
[[ "$FEAT_BRANCH" == feat/DP-* ]] || die "feat branch must match feat/DP-NNN, got '$FEAT_BRANCH'"

for task_md in "${TASK_MDS[@]}"; do
  [[ -f "$task_md" ]] || die "task.md not found: $task_md"
done

if [[ -n "$(git -C "$REPO_PATH" status --porcelain --untracked-files=no)" ]]; then
  die "repo must be clean before task -> feat landing: $REPO_PATH"
fi

if ! git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/${FEAT_BRANCH}" \
  && ! git -C "$REPO_PATH" ls-remote --exit-code --heads origin "$FEAT_BRANCH" >/dev/null 2>&1; then
  die "feat branch not found locally or on origin: $FEAT_BRANCH"
fi

echo "$PREFIX landing ${#TASK_MDS[@]} task PR(s) into ${FEAT_BRANCH}"
lane_args=()
for task_md in "${TASK_MDS[@]}"; do
  lane_args+=(--task-md "$task_md")
done
bash "$SCRIPT_DIR/framework-release-pr-lane.sh" \
  --repo "$REPO_PATH" \
  --main "$FEAT_BRANCH" \
  "${lane_args[@]}" \
  --execute
echo "$PREFIX PASS land-tasks-to-feat feat_branch=${FEAT_BRANCH}"

if [[ "$FULL_TAIL" != "1" ]]; then
  exit 0
fi

echo "$PREFIX rebasing ${FEAT_BRANCH} onto origin/main"
git -C "$REPO_PATH" checkout "$FEAT_BRANCH" >/dev/null
git -C "$REPO_PATH" fetch origin main >/dev/null
bash "$SCRIPT_DIR/cascade-rebase-chain.sh" \
  --repo "$REPO_PATH" \
  --onto origin/main \
  "${lane_args[@]}"

echo "$PREFIX compressing version at ${FEAT_BRANCH} HEAD"
(cd "$REPO_PATH" && mise run release-version)

if [[ -n "$(git -C "$REPO_PATH" status --porcelain --untracked-files=no)" ]]; then
  git -C "$REPO_PATH" add VERSION package.json CHANGELOG.md .changeset >/dev/null 2>&1 || true
  git -C "$REPO_PATH" commit -m "chore(release): compress ${SOURCE_ID} version" >/dev/null
  echo "$PREFIX committed version compression for ${SOURCE_ID}"
else
  echo "$PREFIX release-version produced no tracked changes"
fi

git -C "$REPO_PATH" push origin "HEAD:refs/heads/${FEAT_BRANCH}" >/dev/null
git -C "$REPO_PATH" fetch origin "$FEAT_BRANCH" >/dev/null

if [[ -z "$RELEASE_PR_TITLE" ]]; then
  RELEASE_PR_TITLE="[${SOURCE_ID}] framework release"
fi
if [[ -z "$RELEASE_PR_BODY_FILE" ]]; then
  RELEASE_PR_BODY_FILE="$(mktemp -t framework-release-pr.XXXXXX.md)"
  cat >"$RELEASE_PR_BODY_FILE" <<EOF
## Description
${SOURCE_ID} framework release.

## Changed
- Compress accumulated changesets at ${FEAT_BRANCH} HEAD.
- Promote ${FEAT_BRANCH} to main through PR-gated fast-forward promotion.

## Evidence Summary
| Layer | Status | Evidence |
|-------|--------|----------|
| Release tail | PASS | ${FEAT_BRANCH} validated by framework-release-execute.sh |

## Screenshots (Test Plan)
- framework-release-execute.sh --full-tail

## Related documents
- ${SOURCE_ID}

## QA notes
Framework release-tail automation; no UI artifact.
EOF
fi

if [[ -z "$RELEASE_PR_NUMBER" ]]; then
  echo "$PREFIX creating ${FEAT_BRANCH} -> main release PR"
  pr_create_out="$(bash "$SCRIPT_DIR/polaris-pr-create.sh" \
    --repo "$REPO_PATH" \
    --base main \
    --head "$FEAT_BRANCH" \
    --title "$RELEASE_PR_TITLE" \
    --body-file "$RELEASE_PR_BODY_FILE")"
  printf '%s\n' "$pr_create_out"
  RELEASE_PR_NUMBER="$(printf '%s\n' "$pr_create_out" | sed -nE 's#^https://github.com/[^/]+/[^/]+/pull/([0-9]+).*#\1#p' | tail -1)"
  [[ -n "$RELEASE_PR_NUMBER" ]] || die "could not resolve release PR number from polaris-pr-create output"
fi

echo "$PREFIX promoting main from ${FEAT_BRANCH} via PR #${RELEASE_PR_NUMBER}"
bash "$SCRIPT_DIR/framework-release-main-promotion.sh" \
  --repo "$REPO_PATH" \
  --pr "$RELEASE_PR_NUMBER" \
  --base main \
  --head "$FEAT_BRANCH" \
  --execute
echo "$PREFIX PASS full-tail source=${SOURCE_ID} feat_branch=${FEAT_BRANCH} pr=${RELEASE_PR_NUMBER}"
