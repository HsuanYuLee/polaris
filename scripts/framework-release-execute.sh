#!/usr/bin/env bash
# Purpose: deterministic framework-release executor for feat-model release tails.
# Inputs:  --repo, --source-id/--feat-branch, and ordered --task-md entries.
# Outputs: executes the requested release-tail phase or fails closed with a
#          POLARIS_FRAMEWORK_RELEASE_EXECUTE_* marker on stderr.
set -euo pipefail

PREFIX="[framework-release-execute]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/workspace-config-root.sh
. "$SCRIPT_DIR/lib/workspace-config-root.sh"
REPO_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ID=""
FEAT_BRANCH=""
LAND_TASKS_TO_FEAT=0
FULL_TAIL=0
RELEASE_PR_NUMBER=""
RELEASE_PR_TITLE=""
RELEASE_PR_BODY_FILE=""
TASK_MDS=()
# DP-417 T10 (AC21): run mode. "default" executes the release tail; the collect
# modes (aggregate / enumerate) report the argument-shape precondition contract
# WITHOUT executing, and exit before any git-state check or mutation.
MODE="default"
PRECOND_FAILURES=()

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

# precond_fail <message>
# DP-417 T10 (AC21): single collect-all funnel for the up-front argument-shape
# preconditions. In default MODE it is exactly die() (immediate exit 2, same
# message) so execution behavior and exit codes are unchanged; in the collect
# modes it records the message and returns 0 so ALL violations surface in one
# pass instead of fail-first.
precond_fail() {
  if [[ "$MODE" == "default" ]]; then
    die "$1"
  fi
  PRECOND_FAILURES+=("$1")
}

# emit_aggregate_report
# Prints every collected argument-shape precondition violation at once
# (fail-aggregate) and exits: 2 when any violation was collected, 0 when the
# argument-shape contract is fully satisfied.
emit_aggregate_report() {
  local n="${#PRECOND_FAILURES[@]}"
  if [[ "$n" -eq 0 ]]; then
    echo "$PREFIX PASS argument-shape preconditions (aggregate): 0 violations"
    exit 0
  fi
  echo "$PREFIX POLARIS_FRAMEWORK_RELEASE_EXECUTE_PRECONDITION_AGGREGATE: $n" >&2
  local f
  for f in "${PRECOND_FAILURES[@]}"; do
    echo "  - $f" >&2
  done
  exit 2
}

# print_enumeration
# Dry-run lister: prints the complete release-execute precondition contract
# WITHOUT reading git state or executing anything, then exits 0.
print_enumeration() {
  cat <<'ENUM'
[framework-release-execute] enumerate: release-execute precondition contract (dry-run; no execution)
execution phase (exactly one required):
  --land-tasks-to-feat         land the ordered task PR(s) into feat/DP-NNN, then stop
  --full-tail                  land, then feat rebase -> version compression -> feat/DP-NNN -> main PR -> main promotion
required arguments:
  --source-id DP-NNN           derives feat/DP-NNN when --feat-branch is omitted
  --task-md <path>             one or more ordered task.md deliverables (repeatable)
optional arguments:
  --repo <path>                git checkout being released (default: workspace root)
  --feat-branch feat/DP-NNN    explicit feat branch; must match feat/DP-NNN
  --release-pr <number>        reuse an existing feat/DP-NNN -> main PR
git-state preconditions (checked only when actually executing):
  repo must be a clean git checkout; feat/DP-NNN must exist locally or on origin.
ENUM
}

read_workspace_language() {
  local start="${1:-$REPO_PATH}"
  local config_path=""
  config_path="$(resolve_workspace_config_path "$start" 2>/dev/null || true)"
  [[ -n "$config_path" && -f "$config_path" ]] || return 0
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") print v
      exit
    }
  ' "$config_path"
}

workspace_root_for_language_gate() {
  local start="${1:-$REPO_PATH}"
  local root=""
  root="$(resolve_workspace_config_root "$start" 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$REPO_PATH"
  fi
}

is_zh_language() {
  case "$1" in
    zh|zh-*|zh_*) return 0 ;;
    *) return 1 ;;
  esac
}

default_release_pr_title() {
  local language="$1"
  if is_zh_language "$language"; then
    printf '[%s] Polaris 框架發版\n' "$SOURCE_ID"
  else
    printf '[%s] framework release\n' "$SOURCE_ID"
  fi
}

write_default_release_pr_body() {
  local target="$1"
  local language="$2"
  if is_zh_language "$language"; then
    cat >"$target" <<EOF
## Description
${SOURCE_ID} Polaris 框架發版。

## Changed
- 在 ${FEAT_BRANCH} HEAD 壓縮累積的 changeset。
- 透過 PR-gated fast-forward promotion 將 ${FEAT_BRANCH} 推進到 main。

## Evidence Summary
| Layer | Status | Evidence |
|-------|--------|----------|
| Release tail | PASS | ${FEAT_BRANCH} 已由 framework-release-execute.sh 驗證 |

## Screenshots (Test Plan)
- framework-release-execute.sh --full-tail

## Related documents
- ${SOURCE_ID}

## QA notes
Polaris 框架發版自動化；無 UI artifact。
EOF
  else
    cat >"$target" <<EOF
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
}

gate_external_body() {
  local surface="$1"
  local body_file="$2"
  local language=""
  language="$(read_workspace_language "$REPO_PATH")"
  local gate_args=(--surface "$surface" --body-file "$body_file" --blocking)
  [[ -n "$language" ]] && gate_args+=(--language "$language")
  POLARIS_EXTERNAL_WRITE_WRITER=framework-release:pr-body \
    bash "$SCRIPT_DIR/polaris-external-write-gate.sh" \
      "${gate_args[@]}" >/dev/null
}

gate_release_pr_title() {
  local title_file=""
  title_file="$(mktemp -t framework-release-title.XXXXXX.txt)"
  printf '%s\n' "$RELEASE_PR_TITLE" >"$title_file"
  gate_external_body pr-body "$title_file"
  rm -f "$title_file"
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  else
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  fi
}

head_invariant_die() {
  echo "$PREFIX POLARIS_FRAMEWORK_RELEASE_EXECUTE_HEAD_INVARIANT: $*" >&2
  exit 2
}

task_deliverable_head_sha() {
  local task_md="$1"
  awk '
    /^deliverable:/ { in_blk = 1; next }
    in_blk && /^[^[:space:]]/ { in_blk = 0 }
    in_blk && /^[[:space:]]+head_sha:/ {
      v = $0
      sub(/^[[:space:]]+head_sha:[[:space:]]*/, "", v)
      gsub(/[[:space:]]+$/, "", v)
      gsub(/^["'\''"]|["'\''"]$/, "", v)
      print v
      exit
    }
  ' "$task_md"
}

assert_post_cascade_release_head_invariant() {
  local current_branch current_head task_md task_head
  current_branch="$(git -C "$REPO_PATH" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ "$current_branch" == "$FEAT_BRANCH" ]] || \
    head_invariant_die "expected current branch ${FEAT_BRANCH} after cascade, got ${current_branch:-DETACHED}"

  current_head="$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$current_head" ]] || head_invariant_die "unable to resolve ${FEAT_BRANCH} HEAD"
  [[ "$(git -C "$REPO_PATH" rev-parse "$FEAT_BRANCH" 2>/dev/null || true)" == "$current_head" ]] || \
    head_invariant_die "${FEAT_BRANCH} ref does not match current HEAD after cascade"

  for task_md in "${TASK_MDS[@]}"; do
    task_head="$(task_deliverable_head_sha "$task_md")"
    [[ -n "$task_head" ]] || \
      head_invariant_die "task.md has no deliverable.head_sha authority: $task_md"
    git -C "$REPO_PATH" cat-file -e "${task_head}^{commit}" 2>/dev/null || \
      head_invariant_die "task deliverable.head_sha does not exist: ${task_head} (${task_md})"
    git -C "$REPO_PATH" merge-base --is-ancestor "$task_head" "$current_head" 2>/dev/null || \
      head_invariant_die "task deliverable.head_sha is not contained in ${FEAT_BRANCH} HEAD: ${task_head} (${task_md})"
  done
  echo "$PREFIX PASS post-cascade release head invariant feat_branch=${FEAT_BRANCH} head=${current_head}"
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
    --aggregate) MODE="aggregate"; shift ;;
    --enumerate|--dry-run) MODE="enumerate"; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

# DP-417 T10 (AC21b): --enumerate is a pure dry-run lister; it needs no inputs
# and must never touch git state, so dispatch before the precondition funnel.
if [[ "$MODE" == "enumerate" ]]; then
  print_enumeration
  exit 0
fi

# Argument-shape preconditions: routed through the collect-all funnel so
# --aggregate surfaces every violation in one pass. In default MODE precond_fail
# is exactly die() (same message, immediate exit 2), so nothing about actual
# execution changes.
[[ "$LAND_TASKS_TO_FEAT" -eq 1 || "$FULL_TAIL" -eq 1 ]] || precond_fail "no execution phase selected; pass --land-tasks-to-feat or --full-tail"
[[ "${#TASK_MDS[@]}" -gt 0 ]] || precond_fail "at least one --task-md is required"

if [[ -z "$FEAT_BRANCH" ]]; then
  if [[ "$SOURCE_ID" =~ ^DP-[0-9]+$ ]]; then
    FEAT_BRANCH="feat/${SOURCE_ID}"
  else
    precond_fail "--source-id DP-NNN is required when --feat-branch is omitted"
  fi
fi
[[ -z "$FEAT_BRANCH" || "$FEAT_BRANCH" == feat/DP-* ]] || precond_fail "feat branch must match feat/DP-NNN, got '$FEAT_BRANCH'"

# DP-417 T10 (AC21a): collect-mode dispatch — report the argument-shape
# precondition contract and exit BEFORE any git-state check or mutation.
[[ "$MODE" == "aggregate" ]] && emit_aggregate_report

REPO_PATH="$(abs_path "$REPO_PATH")"
[[ -d "$REPO_PATH/.git" || -f "$REPO_PATH/.git" ]] || die "not a git repository: $REPO_PATH"

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

echo "$PREFIX syncing local ${FEAT_BRANCH} to origin/${FEAT_BRANCH} after task landing"
git -C "$REPO_PATH" fetch origin "$FEAT_BRANCH" >/dev/null
git -C "$REPO_PATH" checkout -B "$FEAT_BRANCH" "origin/${FEAT_BRANCH}" >/dev/null

echo "$PREFIX rebasing ${FEAT_BRANCH} onto origin/main"
git -C "$REPO_PATH" fetch origin main >/dev/null
bash "$SCRIPT_DIR/cascade-rebase-chain.sh" \
  --repo "$REPO_PATH" \
  --onto origin/main \
  "${lane_args[@]}"

assert_post_cascade_release_head_invariant

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
  RELEASE_PR_TITLE="$(default_release_pr_title "$(read_workspace_language "$REPO_PATH")")"
fi
if [[ -z "$RELEASE_PR_BODY_FILE" ]]; then
  RELEASE_PR_BODY_FILE="$(mktemp -t framework-release-pr.XXXXXX.md)"
  write_default_release_pr_body "$RELEASE_PR_BODY_FILE" "$(read_workspace_language "$REPO_PATH")"
fi
gate_release_pr_title
gate_external_body pr-body "$RELEASE_PR_BODY_FILE"

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
