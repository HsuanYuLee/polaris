#!/usr/bin/env bash
set -euo pipefail

# framework-release-pr-lane.sh
#
# Deterministic preflight / executor for DP-backed framework workspace PR lanes.
# It verifies that a task chain's PR bases match the task.md Branch chain before
# framework-release syncs workspace main to the Polaris template repo.

PREFIX="[framework-release-pr-lane]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"
VERSION_BUMP_CHECKER="${SCRIPT_DIR}/check-version-bump-reminder.sh"
SCRIPT_MANIFEST_CHECKER="${SCRIPT_DIR}/check-script-manifest.sh"
GOVERNED_SCRIPT_TEST_RUNNER="${SCRIPT_DIR}/run-governed-script-tests.sh"
WORKSPACE_REPO=""
MAIN_BRANCH="main"
EXECUTE=0
REQUIRE_MAIN_CONTAINS_FINAL=0
GH_BIN="${GH_BIN:-gh}"
TERMINAL_TASK_MD=""
TASK_MDS=()

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

usage() {
  cat >&2 <<'EOF'
usage: framework-release-pr-lane.sh [options]

Options:
  --repo <path>              Workspace repo path (default: script repo)
  --workspace-repo <owner/repo>
                             GitHub repo slug for gh commands
  --terminal-task-md <path>  Terminal DP task.md; branch chain is resolved from it
  --task-md <path>           Explicit ordered task.md. May repeat; bypasses chain lookup
  --main <branch>            Main branch name (default: main)
  --execute                  Merge open PRs in order, retargeting downstream PRs to main
  --require-main-contains-final
                             After execution/preflight, require origin/main contains final head
  -h, --help                 Show help

Default mode is dry-run preflight: no GitHub writes.
EOF
}

die() {
  echo "$PREFIX ERROR: $*" >&2
  exit 2
}

info() {
  echo "$PREFIX $*" >&2
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
}

table_field() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    /^[[:space:]]*\|[[:space:]]*-+/ { next }
    NF >= 3 {
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

json_field() {
  local json="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr} or '')" <<<"$json"
}

line_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

gh_repo_args=()
refresh_gh_repo_args() {
  gh_repo_args=()
  if [[ -n "$WORKSPACE_REPO" ]]; then
    gh_repo_args=(--repo "$WORKSPACE_REPO")
  fi
}

pr_view_json() {
  local branch="$1"
  local gh_repo="$WORKSPACE_REPO"
  local owner=""
  local rest_json=""

  if [[ -z "$gh_repo" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
    gh_repo="$(polaris_github_repo_slug "$REPO_PATH" 2>/dev/null || true)"
  fi

  if [[ -n "$gh_repo" ]] && declare -F polaris_gh_api >/dev/null 2>&1; then
    owner="${gh_repo%%/*}"
    rest_json="$(polaris_gh_api "repos/${gh_repo}/pulls" \
      --method GET \
      -f "head=${owner}:${branch}" \
      -f "state=all" \
      -f "per_page=1" \
      --jq '.[0] | {
        number: .number,
        state: (if .merged_at then "MERGED" else (.state | ascii_upcase) end),
        baseRefName: .base.ref,
        headRefName: .head.ref,
        headRefOid: .head.sha,
        mergeStateStatus: (.mergeable_state // "unknown"),
        url: .html_url
      }' 2>/dev/null || true)"
    if [[ -n "$rest_json" && "$rest_json" != "null" ]]; then
      printf '%s\n' "$rest_json"
      return
    fi
  fi

  "$GH_BIN" pr view "$branch" ${gh_repo_args[@]+"${gh_repo_args[@]}"} \
    --json number,state,baseRefName,headRefName,headRefOid,mergeStateStatus,url
}

run_version_bump_release_gate() {
  local final_task_md final_task_branch
  final_task_md="${TASK_MDS[$((${#TASK_MDS[@]} - 1))]}"
  final_task_branch="$(table_field "Task branch" "$final_task_md")"
  [[ -n "$final_task_branch" ]] || die "missing Task branch in terminal task.md: $final_task_md"
  [[ -f "$VERSION_BUMP_CHECKER" ]] || die "missing checker: $VERSION_BUMP_CHECKER"

  info "running version-bump release gate on ${final_task_branch} against origin/${MAIN_BRANCH}"
  bash "$VERSION_BUMP_CHECKER" \
    --mode release-preflight \
    --base "origin/${MAIN_BRANCH}" \
    --head-ref "$final_task_branch" \
    --repo "$REPO_PATH" || die "release preflight blocked: missing required VERSION bump"
}

run_script_manifest_release_gate() {
  [[ -f "$SCRIPT_MANIFEST_CHECKER" ]] || die "missing checker: $SCRIPT_MANIFEST_CHECKER"
  [[ -f "$REPO_PATH/scripts/manifest.json" ]] || die "release preflight blocked: missing scripts/manifest.json"

  info "running script manifest release gate"
  bash "$SCRIPT_MANIFEST_CHECKER" --root "$REPO_PATH" --quiet \
    || die "release preflight blocked: script manifest drift"
}

run_governed_script_tests_release_gate() {
  local final_task_md final_task_branch
  final_task_md="${TASK_MDS[$((${#TASK_MDS[@]} - 1))]}"
  final_task_branch="$(table_field "Task branch" "$final_task_md")"
  [[ -n "$final_task_branch" ]] || die "missing Task branch in terminal task.md: $final_task_md"
  [[ -f "$GOVERNED_SCRIPT_TEST_RUNNER" ]] || die "missing runner: $GOVERNED_SCRIPT_TEST_RUNNER"

  info "running governed script test suite for ${final_task_branch}"
  bash "$GOVERNED_SCRIPT_TEST_RUNNER" \
    --root "$REPO_PATH" \
    --profile release \
    --base "origin/${MAIN_BRANCH}" \
    --head-ref "$final_task_branch" \
    || die "release preflight blocked: governed script tests failed"
}

verify_pr_task_lineage() {
  local task_md="$1"
  local task_id="$2"
  local task_branch="$3"
  local pr_number="$4"
  local pr_head_branch="$5"
  local resolver_err=""
  local resolver_out=""
  local resolver_status=0
  local resolved=()

  [[ "$task_branch" == task/* ]] || die "release preflight blocked: $task_id PR #$pr_number uses '$task_branch', not a DP task branch. Polaris framework release PRs must come from refinement -> breakdown -> engineering task.md lineage; generic GitHub publish branches are not valid release inputs."
  [[ -n "$pr_head_branch" ]] || die "PR #$pr_number for $task_id has empty headRefName"
  [[ "$pr_head_branch" == "$task_branch" ]] || die "PR #$pr_number head is '$pr_head_branch'; expected task.md Task branch '$task_branch'"

  resolver_err="$(mktemp -t framework-release-pr-lane-resolve-err.XXXXXX)"
  resolver_out="$(mktemp -t framework-release-pr-lane-resolve-out.XXXXXX)"
  set +e
  bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --scan-root "$REPO_PATH" "$pr_head_branch" >"$resolver_out" 2>"$resolver_err"
  resolver_status=$?
  set -e
  while IFS= read -r line; do
    [[ -n "$line" ]] && resolved+=("$line")
  done < "$resolver_out"

  if [[ $resolver_status -ne 0 || ${#resolved[@]} -eq 0 ]]; then
    local detail
    detail="$(tr '\n' ' ' < "$resolver_err" | sed 's/[[:space:]]\+/ /g')"
    rm -f "$resolver_err" "$resolver_out"
    die "release preflight blocked: PR #$pr_number for $task_id lacks task.md lineage for head '$pr_head_branch'. Run the canonical chain first: refinement -> breakdown -> engineering; do not use github:yeet or generic publisher. ${detail}"
  fi
  rm -f "$resolver_err" "$resolver_out"

  task_md="$(abs_path "$task_md")"
  if ! line_in_list "$task_md" "${resolved[@]}"; then
    die "release preflight blocked: PR #$pr_number head '$pr_head_branch' resolves to a different task.md than supplied for $task_id. Expected $task_md; resolved ${resolved[*]}"
  fi
}

resolve_task_mds_from_terminal() {
  [[ -n "$TERMINAL_TASK_MD" ]] || die "provide --task-md or --terminal-task-md"
  [[ -f "$TERMINAL_TASK_MD" ]] || die "terminal task.md not found: $TERMINAL_TASK_MD"

  local branch task_path
  while IFS= read -r branch; do
    [[ "$branch" == task/* ]] || continue
    task_path="$(bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --scan-root "$REPO_PATH" "$branch" | head -1 || true)"
    if [[ -z "$task_path" && "$branch" == "$(table_field "Task branch" "$TERMINAL_TASK_MD")" ]]; then
      task_path="$TERMINAL_TASK_MD"
    fi
    [[ -n "$task_path" ]] || die "could not resolve task.md for branch in chain: $branch"
    TASK_MDS+=("$(abs_path "$task_path")")
  done < <(bash "$SCRIPT_DIR/resolve-branch-chain.sh" "$TERMINAL_TASK_MD")

  [[ ${#TASK_MDS[@]} -gt 0 ]] || die "no task branches found in terminal Branch chain"
}

validate_and_plan() {
  local previous_branch=""
  local previous_state=""
  local idx=0
  local final_head=""
  local task_md task_id task_branch expected_initial_base json number state base head head_branch url action

  echo "$PREFIX release lane plan:"
  for task_md in "${TASK_MDS[@]}"; do
    [[ -f "$task_md" ]] || die "task.md not found: $task_md"
    task_id="$(table_field "Task ID" "$task_md")"
    [[ -n "$task_id" ]] || task_id="$(table_field "Task JIRA key" "$task_md")"
    task_branch="$(table_field "Task branch" "$task_md")"
    [[ -n "$task_branch" ]] || die "missing Task branch in $task_md"

    json="$(pr_view_json "$task_branch")" || die "gh pr view failed for $task_branch"
    number="$(json_field "$json" "d.get('number')")"
    state="$(json_field "$json" "d.get('state')")"
    base="$(json_field "$json" "d.get('baseRefName')")"
    head="$(json_field "$json" "d.get('headRefOid')")"
    head_branch="$(json_field "$json" "d.get('headRefName')")"
    url="$(json_field "$json" "d.get('url')")"
    final_head="$head"

    [[ "$state" != "CLOSED" ]] || die "PR #$number for $task_id is CLOSED: $url"
    [[ -n "$head" ]] || die "PR #$number for $task_id has empty headRefOid"
    verify_pr_task_lineage "$task_md" "$task_id" "$task_branch" "$number" "$head_branch"

    if [[ $idx -eq 0 ]]; then
      expected_initial_base="$MAIN_BRANCH"
      [[ "$base" == "$MAIN_BRANCH" ]] || die "$task_id PR #$number base is '$base'; expected '$MAIN_BRANCH'"
      action="merge into $MAIN_BRANCH"
    else
      expected_initial_base="$previous_branch"
      if [[ "$base" != "$previous_branch" && ! ( "$previous_state" == "MERGED" && "$base" == "$MAIN_BRANCH" ) ]]; then
        die "$task_id PR #$number base is '$base'; expected '$expected_initial_base'"
      fi
      if [[ "$base" == "$previous_branch" ]]; then
        action="retarget to $MAIN_BRANCH, then merge"
      else
        action="merge into $MAIN_BRANCH"
      fi
    fi

    printf '  - %s PR #%s base=%s state=%s head=%s action=%s\n' \
      "${task_id:-$task_branch}" "$number" "$base" "$state" "$head" "$action"

    if [[ "$EXECUTE" == "1" && "$state" != "MERGED" ]]; then
      if [[ $idx -gt 0 && "$base" == "$previous_branch" ]]; then
        info "retargeting PR #$number ($task_id) to $MAIN_BRANCH"
        "$GH_BIN" pr edit "$number" ${gh_repo_args[@]+"${gh_repo_args[@]}"} --base "$MAIN_BRANCH"
        json="$(pr_view_json "$task_branch")"
        base="$(json_field "$json" "d.get('baseRefName')")"
        [[ "$base" == "$MAIN_BRANCH" ]] || die "PR #$number retarget verification failed; base is '$base'"
      fi
      info "merging PR #$number ($task_id)"
      "$GH_BIN" pr merge "$number" ${gh_repo_args[@]+"${gh_repo_args[@]}"} --merge
      state="MERGED"
    fi

    previous_branch="$task_branch"
    previous_state="$state"
    idx=$((idx + 1))
  done

  if [[ "$REQUIRE_MAIN_CONTAINS_FINAL" == "1" ]]; then
    [[ -n "$final_head" ]] || die "cannot check final ancestry without final head"
    git -C "$REPO_PATH" fetch origin "$MAIN_BRANCH" >/dev/null
    git -C "$REPO_PATH" merge-base --is-ancestor "$final_head" "origin/$MAIN_BRANCH" \
      || die "origin/$MAIN_BRANCH does not contain terminal task head $final_head"
    info "origin/$MAIN_BRANCH contains terminal task head $final_head"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="$2"; shift 2 ;;
    --repo=*) REPO_PATH="${1#--repo=}"; shift ;;
    --workspace-repo) WORKSPACE_REPO="$2"; shift 2 ;;
    --workspace-repo=*) WORKSPACE_REPO="${1#--workspace-repo=}"; shift ;;
    --terminal-task-md) TERMINAL_TASK_MD="$2"; shift 2 ;;
    --terminal-task-md=*) TERMINAL_TASK_MD="${1#--terminal-task-md=}"; shift ;;
    --task-md) TASK_MDS+=("$(abs_path "$2")"); shift 2 ;;
    --task-md=*) TASK_MDS+=("$(abs_path "${1#--task-md=}")"); shift ;;
    --main) MAIN_BRANCH="$2"; shift 2 ;;
    --main=*) MAIN_BRANCH="${1#--main=}"; shift ;;
    --execute) EXECUTE=1; shift ;;
    --require-main-contains-final) REQUIRE_MAIN_CONTAINS_FINAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

REPO_PATH="$(abs_path "$REPO_PATH")"
refresh_gh_repo_args

if [[ ${#TASK_MDS[@]} -eq 0 ]]; then
  resolve_task_mds_from_terminal
fi

run_version_bump_release_gate
run_script_manifest_release_gate
run_governed_script_tests_release_gate
validate_and_plan
echo "$PREFIX PASS"
