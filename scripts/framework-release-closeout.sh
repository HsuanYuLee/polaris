#!/usr/bin/env bash
set -euo pipefail

# framework-release-closeout.sh
#
# Deterministic post-release closeout for DP-backed framework tasks after the
# workspace PR has been merged and sync-to-polaris completed.
#
# Usage:
#   scripts/framework-release-closeout.sh \
#     --task-md <path> [--task-head-sha <sha>] \
#     --verify-evidence <path> [--ci-local-evidence <path|N/A>] [--vr-evidence <path|N/A>] \
#     [--task-md <path> ...] \
#     --workspace-commit <sha> \
#     --template-commit <sha> \
#     --version-tag <tag|N/A> \
#     --release-url <url|N/A> \
#     [--repo <workspace-repo>] \
#     [--template-repo <template-repo>] \
#     [--extension-id framework-release] \
#     [--delete-branches]
#
# Repeated per-task inputs are positional. Each --task-md must have one
# --verify-evidence. --task-head-sha is optional; when omitted it is resolved
# from the task branch in task.md.
# After the parent DP reaches IMPLEMENTED, the canonical DP container is archived
# automatically. docs-manager reads canonical specs directly, so no viewer sync is
# needed after this move.

PREFIX="[framework-release-closeout]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"
TEMPLATE_REPO=""
EXTENSION_ID="framework-release"
WORKSPACE_COMMIT=""
TEMPLATE_COMMIT=""
VERSION_TAG=""
RELEASE_URL=""
DELETE_BRANCHES=0

TASK_MDS=()
TASK_HEAD_SHAS=()
VERIFY_EVIDENCES=()
CI_LOCAL_EVIDENCES=()
VR_EVIDENCES=()

usage() {
  sed -n '3,34p' "$0" >&2
}

die() {
  echo "$PREFIX ERROR: $1" >&2
  exit 2
}

info() {
  echo "$PREFIX $1" >&2
}

is_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

sha_matches() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" || "$expected" == "$actual"* || "$actual" == "$expected"* ]]
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$path")")
  fi
}

json_field() {
  local json="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr} or '')" <<<"$json"
}

frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

registered_worktree_for_branch() {
  local branch="$1"
  git -C "$REPO_ROOT" worktree list --porcelain | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

resolve_branch_sha() {
  local branch="$1"
  local sha=""
  sha="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "${branch}^{commit}" 2>/dev/null || true)"
  if [[ -z "$sha" ]]; then
    sha="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/${branch}^{commit}" 2>/dev/null || true)"
  fi
  [[ -n "$sha" ]] || die "cannot resolve task branch commit: ${branch}"
  printf '%s\n' "$sha"
}

ensure_clean_worktree_if_present() {
  local task_branch="$1"
  local worktree
  worktree="$(registered_worktree_for_branch "$task_branch")"
  if [[ -z "$worktree" ]]; then
    info "no registered worktree for ${task_branch}; cleanup will be NOOP"
    return 0
  fi
  [[ "$worktree" == *"/.worktrees/"* ]] || die "refusing non-implementation worktree: ${worktree}"
  if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
    die "dirty implementation worktree blocks closeout: ${worktree}"
  fi
}

delete_branch_if_safe() {
  local task_branch="$1"
  local task_head_sha="$2"

  [[ "$DELETE_BRANCHES" -eq 1 ]] || return 0

  if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$task_head_sha" "$WORKSPACE_COMMIT"; then
    die "refusing branch delete; workspace_commit does not contain task head for ${task_branch}"
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${task_branch}"; then
    git -C "$REPO_ROOT" branch -d "$task_branch"
    info "deleted local branch ${task_branch}"
  else
    info "local branch already absent: ${task_branch}"
  fi

  if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$task_branch" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" push origin --delete "$task_branch"
    info "deleted remote branch origin/${task_branch}"
  else
    info "remote branch already absent: origin/${task_branch}"
  fi
}

archive_parent_dp_if_terminal() {
  local moved_task_md="$1"
  local parser_json source_type source_id specs_root dp_dir plan_status

  parser_json="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$moved_task_md" --no-resolve)" || die "unable to parse implemented task.md: ${moved_task_md}"
  source_type="$(json_field "$parser_json" "d.get('identity', {}).get('source_type')")"
  source_id="$(json_field "$parser_json" "d.get('identity', {}).get('source_id')")"

  [[ "$source_type" == "dp" && "$source_id" =~ ^DP-[0-9]{3}$ ]] || return 0
  specs_root="$(resolve_specs_root "$REPO_ROOT")" || die "unable to resolve specs root"

  dp_dir=""
  while IFS= read -r -d '' match; do
    if [[ -n "$dp_dir" ]]; then
      die "multiple active DP containers match ${source_id}"
    fi
    dp_dir="$match"
  done < <(find "$specs_root/design-plans" -maxdepth 1 -type d -name "${source_id}-*" -print0 2>/dev/null)

  if [[ -z "$dp_dir" ]]; then
    info "parent ${source_id} is already archived or absent; archive skipped"
    return 0
  fi

  plan_status="$(frontmatter_status "$dp_dir/plan.md")"
  case "$plan_status" in
    IMPLEMENTED|ABANDONED)
      info "archiving parent ${source_id}"
      bash "${SCRIPT_DIR}/archive-spec.sh" --workspace "$REPO_ROOT" "$source_id"
      ;;
    *)
      info "parent ${source_id} not terminal yet; archive skipped"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --template-repo) TEMPLATE_REPO="${2:-}"; shift 2 ;;
    --extension-id) EXTENSION_ID="${2:-}"; shift 2 ;;
    --task-md) TASK_MDS+=("${2:-}"); shift 2 ;;
    --task-head-sha) TASK_HEAD_SHAS+=("${2:-}"); shift 2 ;;
    --verify-evidence) VERIFY_EVIDENCES+=("${2:-}"); shift 2 ;;
    --ci-local-evidence) CI_LOCAL_EVIDENCES+=("${2:-}"); shift 2 ;;
    --vr-evidence) VR_EVIDENCES+=("${2:-}"); shift 2 ;;
    --workspace-commit) WORKSPACE_COMMIT="${2:-}"; shift 2 ;;
    --template-commit) TEMPLATE_COMMIT="${2:-}"; shift 2 ;;
    --version-tag) VERSION_TAG="${2:-}"; shift 2 ;;
    --release-url) RELEASE_URL="${2:-}"; shift 2 ;;
    --delete-branches) DELETE_BRANCHES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "${#TASK_MDS[@]}" -gt 0 ]] || die "at least one --task-md is required"
[[ "${#VERIFY_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "provide exactly one --verify-evidence for each --task-md"
[[ "${#TASK_HEAD_SHAS[@]}" -eq 0 || "${#TASK_HEAD_SHAS[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--task-head-sha count must be zero or match --task-md count"
[[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 0 || "${#CI_LOCAL_EVIDENCES[@]}" -eq 1 || "${#CI_LOCAL_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--ci-local-evidence count must be zero, one, or match --task-md count"
[[ "${#VR_EVIDENCES[@]}" -eq 0 || "${#VR_EVIDENCES[@]}" -eq 1 || "${#VR_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--vr-evidence count must be zero, one, or match --task-md count"
[[ -n "$WORKSPACE_COMMIT" ]] || die "--workspace-commit is required"
[[ -n "$TEMPLATE_COMMIT" ]] || die "--template-commit is required"
[[ -n "$VERSION_TAG" ]] || die "--version-tag is required"
[[ -n "$RELEASE_URL" ]] || die "--release-url is required"
is_sha "$WORKSPACE_COMMIT" || die "--workspace-commit must be a 7-40 char hex SHA"
is_sha "$TEMPLATE_COMMIT" || die "--template-commit must be a 7-40 char hex SHA"

REPO_ROOT="$(abs_path "$REPO_ROOT")"
[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || die "repo is not a git checkout: ${REPO_ROOT}"
git -C "$REPO_ROOT" cat-file -e "${WORKSPACE_COMMIT}^{commit}" 2>/dev/null || die "workspace commit not found: ${WORKSPACE_COMMIT}"
current_workspace_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
sha_matches "$WORKSPACE_COMMIT" "$current_workspace_head" || die "workspace commit is stale; current HEAD is ${current_workspace_head}"

if [[ -n "$TEMPLATE_REPO" ]]; then
  TEMPLATE_REPO="$(abs_path "$TEMPLATE_REPO")"
  [[ -d "$TEMPLATE_REPO/.git" || -f "$TEMPLATE_REPO/.git" ]] || die "template repo is not a git checkout: ${TEMPLATE_REPO}"
  git -C "$TEMPLATE_REPO" cat-file -e "${TEMPLATE_COMMIT}^{commit}" 2>/dev/null || die "template commit not found: ${TEMPLATE_COMMIT}"
  current_template_head="$(git -C "$TEMPLATE_REPO" rev-parse HEAD)"
  sha_matches "$TEMPLATE_COMMIT" "$current_template_head" || die "template commit is stale; template HEAD is ${current_template_head}"
  if [[ "$VERSION_TAG" != "N/A" ]]; then
    git -C "$TEMPLATE_REPO" rev-parse -q --verify "refs/tags/${VERSION_TAG}" >/dev/null || die "template tag missing: ${VERSION_TAG}"
  fi
fi

declare -a ABS_TASK_MDS TASK_IDS TASK_BRANCHES RESOLVED_TASK_HEADS

for i in "${!TASK_MDS[@]}"; do
  task_md="$(abs_path "${TASK_MDS[$i]}")"
  [[ -f "$task_md" ]] || die "task.md not found: ${task_md}"

  parser_json="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md" --no-resolve)" || die "unable to parse task.md: ${task_md}"
  task_id="$(json_field "$parser_json" "d.get('identity', {}).get('work_item_id') or d.get('header', {}).get('task_id')")"
  task_branch="$(json_field "$parser_json" "d.get('operational_context', {}).get('task_branch')")"
  [[ -n "$task_id" ]] || die "task identity missing in ${task_md}"
  [[ -n "$task_branch" ]] || die "Task branch missing in ${task_md}"

  task_head_sha=""
  if [[ "${#TASK_HEAD_SHAS[@]}" -gt 0 ]]; then
    task_head_sha="${TASK_HEAD_SHAS[$i]}"
  fi
  if [[ -z "$task_head_sha" ]]; then
    task_head_sha="$(resolve_branch_sha "$task_branch")"
  fi
  is_sha "$task_head_sha" || die "task head SHA malformed for ${task_id}: ${task_head_sha}"
  git -C "$REPO_ROOT" cat-file -e "${task_head_sha}^{commit}" 2>/dev/null || die "task head does not exist for ${task_id}: ${task_head_sha}"
  git -C "$REPO_ROOT" merge-base --is-ancestor "$task_head_sha" "$WORKSPACE_COMMIT" || die "workspace commit does not contain task head for ${task_id}"

  ensure_clean_worktree_if_present "$task_branch"

  ABS_TASK_MDS+=("$task_md")
  TASK_IDS+=("$task_id")
  TASK_BRANCHES+=("$task_branch")
  RESOLVED_TASK_HEADS+=("$task_head_sha")
done

for i in "${!ABS_TASK_MDS[@]}"; do
  task_md="${ABS_TASK_MDS[$i]}"
  task_id="${TASK_IDS[$i]}"
  task_branch="${TASK_BRANCHES[$i]}"
  task_head_sha="${RESOLVED_TASK_HEADS[$i]}"
  verify_evidence="${VERIFY_EVIDENCES[$i]}"

  if [[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 0 ]]; then
    ci_local_evidence="N/A"
  elif [[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 1 ]]; then
    ci_local_evidence="${CI_LOCAL_EVIDENCES[0]}"
  else
    ci_local_evidence="${CI_LOCAL_EVIDENCES[$i]}"
  fi

  if [[ "${#VR_EVIDENCES[@]}" -eq 0 ]]; then
    vr_evidence="N/A"
  elif [[ "${#VR_EVIDENCES[@]}" -eq 1 ]]; then
    vr_evidence="${VR_EVIDENCES[0]}"
  else
    vr_evidence="${VR_EVIDENCES[$i]}"
  fi

  info "writing extension deliverable for ${task_id}"
  bash "${SCRIPT_DIR}/write-extension-deliverable.sh" "$task_md" \
    --extension-id "$EXTENSION_ID" \
    --task-head-sha "$task_head_sha" \
    --workspace-commit "$WORKSPACE_COMMIT" \
    --template-commit "$TEMPLATE_COMMIT" \
    --version-tag "$VERSION_TAG" \
    --release-url "$RELEASE_URL" \
    --ci-local-evidence "$ci_local_evidence" \
    --verify-evidence "$verify_evidence" \
    --vr-evidence "$vr_evidence"

  bash "${SCRIPT_DIR}/check-local-extension-completion.sh" \
    --repo "$REPO_ROOT" \
    --task-md "$task_md" \
    --task-id "$task_id" \
    --extension-id "$EXTENSION_ID" \
    ${TEMPLATE_REPO:+--template-repo "$TEMPLATE_REPO"}

  bash "${SCRIPT_DIR}/mark-spec-implemented.sh" "$task_id" --workspace "$REPO_ROOT"

  moved_task_md="${task_md}"
  if [[ ! -f "$moved_task_md" ]]; then
    moved_task_md="$(dirname "$task_md")/pr-release/$(basename "$task_md")"
  fi
  [[ -f "$moved_task_md" ]] || die "implemented task file not found after mark-spec-implemented: ${task_id}"

  bash "${SCRIPT_DIR}/close-parent-spec-if-complete.sh" --task-md "$moved_task_md" --workspace "$REPO_ROOT"
  bash "${SCRIPT_DIR}/engineering-clean-worktree.sh" --task-md "$moved_task_md" --repo "$REPO_ROOT"
  delete_branch_if_safe "$task_branch" "$task_head_sha"
  archive_parent_dp_if_terminal "$moved_task_md"

  info "closed out ${task_id}"
done

info "PASS: framework release closeout completed for ${#ABS_TASK_MDS[@]} task(s)"
