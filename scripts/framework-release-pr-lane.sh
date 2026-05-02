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
WORKSPACE_REPO=""
MAIN_BRANCH="main"
EXECUTE=0
REQUIRE_MAIN_CONTAINS_FINAL=0
GH_BIN="${GH_BIN:-gh}"
TERMINAL_TASK_MD=""
TASK_MDS=()

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

gh_repo_args=()
refresh_gh_repo_args() {
  gh_repo_args=()
  if [[ -n "$WORKSPACE_REPO" ]]; then
    gh_repo_args=(--repo "$WORKSPACE_REPO")
  fi
}

pr_view_json() {
  local branch="$1"
  "$GH_BIN" pr view "$branch" ${gh_repo_args[@]+"${gh_repo_args[@]}"} \
    --json number,state,baseRefName,headRefName,headRefOid,mergeStateStatus,url
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
  local task_md task_id task_branch expected_initial_base json number state base head url action

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
    url="$(json_field "$json" "d.get('url')")"
    final_head="$head"

    [[ "$state" != "CLOSED" ]] || die "PR #$number for $task_id is CLOSED: $url"
    [[ -n "$head" ]] || die "PR #$number for $task_id has empty headRefOid"

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

validate_and_plan
echo "$PREFIX PASS"
