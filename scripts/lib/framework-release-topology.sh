#!/usr/bin/env bash
# Purpose: classify framework DP release topology and verify task-head ancestry.

framework_release_topology_die() {
  echo "[framework-release-topology] POLARIS_FRAMEWORK_RELEASE_TOPOLOGY_BLOCKED: $*" >&2
  return 2
}

framework_release_topology_table_field() {
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

framework_release_topology_task_id() {
  local task_md="$1"
  local task_id
  task_id="$(framework_release_topology_table_field "Task ID" "$task_md")"
  [[ -n "$task_id" ]] || task_id="$(framework_release_topology_table_field "JIRA key" "$task_md")"
  printf '%s\n' "$task_id"
}

framework_release_topology_classify_task_mds() {
  local task_mds=("$@")
  local count="${#task_mds[@]}"
  local idx=0
  local task_md task_id base branch previous_branch
  local stack_edges=0
  local same_base=""
  local same_base_count=0

  [[ "$count" -gt 0 ]] || framework_release_topology_die "no task.md supplied" || return $?

  if [[ "$count" -eq 1 ]]; then
    task_md="${task_mds[0]}"
    [[ -f "$task_md" ]] || framework_release_topology_die "task.md not found: $task_md" || return $?
    task_id="$(framework_release_topology_task_id "$task_md")"
    branch="$(framework_release_topology_table_field "Task branch" "$task_md")"
    base="$(framework_release_topology_table_field "Base branch" "$task_md")"
    [[ -n "$branch" ]] || framework_release_topology_die "missing Task branch in $task_md" || return $?
    [[ -n "$base" ]] || framework_release_topology_die "missing Base branch in $task_md" || return $?
    printf 'topology=single_pr task=%s base=%s head_branch=%s\n' "${task_id:-$branch}" "$base" "$branch"
    return 0
  fi

  for task_md in "${task_mds[@]}"; do
    [[ -f "$task_md" ]] || framework_release_topology_die "task.md not found: $task_md" || return $?
    task_id="$(framework_release_topology_task_id "$task_md")"
    base="$(framework_release_topology_table_field "Base branch" "$task_md")"
    branch="$(framework_release_topology_table_field "Task branch" "$task_md")"
    [[ -n "$base" ]] || framework_release_topology_die "missing Base branch in $task_md" || return $?
    [[ -n "$branch" ]] || framework_release_topology_die "missing Task branch in $task_md" || return $?
    [[ "$branch" == task/* ]] || framework_release_topology_die "invalid task branch for ${task_id:-$task_md}: $branch" || return $?

    if [[ "$idx" -eq 0 ]]; then
      same_base="$base"
      same_base_count=1
    else
      [[ "$base" == "$same_base" ]] && same_base_count=$((same_base_count + 1))
      [[ "$base" == "$previous_branch" ]] && stack_edges=$((stack_edges + 1))
    fi

    previous_branch="$branch"
    idx=$((idx + 1))
  done

  if [[ "$stack_edges" -eq $((count - 1)) ]]; then
    printf 'topology=stack_pr tasks=%s\n' "$count"
    return 0
  fi

  if [[ "$same_base_count" -eq "$count" && "$same_base" == feat/DP-* ]]; then
    framework_release_topology_die "invalid topology=sibling_parallel_invalid base=${same_base} tasks=${count}; framework DP release must be one single source-level PR or a declared stack PR chain. Rebase downstream task PRs onto their direct predecessor, or collapse implementation into one PR before framework-release."
    return $?
  fi

  framework_release_topology_die "invalid topology=undeclared_stack tasks=${count}; task.md Base branch values must form one declared stack chain, not unrelated heads."
}

framework_release_topology_validate_pr_records() {
  local count=0
  local previous_head_branch=""
  local same_base=""
  local same_base_count=0
  local stack_edges=0
  local record task_id task_branch task_base pr_number pr_base pr_head_branch pr_head_sha

  while IFS='|' read -r task_id task_branch task_base pr_number pr_base pr_head_branch pr_head_sha; do
    [[ -n "${task_id}${task_branch}${task_base}${pr_number}${pr_base}${pr_head_branch}${pr_head_sha}" ]] || continue
    [[ "$task_id" != "task_id" ]] || continue
    count=$((count + 1))

    [[ -n "$task_branch" && "$task_branch" == task/* ]] || framework_release_topology_die "invalid task branch for ${task_id}: ${task_branch}" || return $?
    [[ -n "$pr_number" ]] || framework_release_topology_die "missing PR number for ${task_id}" || return $?
    [[ -n "$pr_head_sha" ]] || framework_release_topology_die "missing PR head SHA for ${task_id} PR #${pr_number}" || return $?
    [[ "$pr_head_branch" == "$task_branch" ]] || framework_release_topology_die "PR #${pr_number} for ${task_id} head branch is ${pr_head_branch}; expected ${task_branch}" || return $?
    [[ "$pr_base" == "$task_base" || "$pr_base" == main ]] || framework_release_topology_die "PR #${pr_number} for ${task_id} base is ${pr_base}; expected task base ${task_base} or main after upstream merge" || return $?

    if [[ "$count" -eq 1 ]]; then
      same_base="$pr_base"
      same_base_count=1
    else
      [[ "$pr_base" == "$same_base" ]] && same_base_count=$((same_base_count + 1))
      [[ "$pr_base" == "$previous_head_branch" ]] && stack_edges=$((stack_edges + 1))
    fi
    previous_head_branch="$pr_head_branch"
  done

  [[ "$count" -gt 0 ]] || framework_release_topology_die "no PR records supplied" || return $?
  if [[ "$count" -eq 1 ]]; then
    printf 'topology=single_pr prs=1\n'
    return 0
  fi
  if [[ "$stack_edges" -eq $((count - 1)) ]]; then
    printf 'topology=stack_pr prs=%s\n' "$count"
    return 0
  fi
  if [[ "$same_base_count" -eq "$count" && "$same_base" == feat/DP-* ]]; then
    framework_release_topology_die "invalid topology=sibling_parallel_invalid base=${same_base} prs=${count}; offending PRs are sibling heads for one framework DP. Convert to a declared stack or a single source-level PR before release."
    return $?
  fi
  framework_release_topology_die "invalid topology=undeclared_stack prs=${count}; PR base/head metadata does not form a legal framework DP release chain."
}

framework_release_topology_validate_pr_records_with_git() {
  local repo="$1"
  local count=0
  local previous_task_branch=""
  local previous_head_branch=""
  local previous_head_sha=""
  local first_pr_base=""
  local same_base_count=0
  local stack_edges=0
  local task_id task_branch task_base pr_number pr_state pr_base pr_head_branch pr_head_sha
  local task_ids=()
  local task_branches=()
  local task_bases=()
  local pr_numbers=()
  local pr_states=()
  local pr_bases=()
  local pr_head_branches=()
  local pr_head_shas=()

  [[ -d "$repo/.git" || -f "$repo/.git" ]] \
    || framework_release_topology_die "not a git repository: $repo" || return $?

  while IFS='|' read -r task_id task_branch task_base pr_number pr_state pr_base pr_head_branch pr_head_sha; do
    [[ -n "${task_id}${task_branch}${task_base}${pr_number}${pr_state}${pr_base}${pr_head_branch}${pr_head_sha}" ]] || continue
    [[ "$task_id" != "task_id" ]] || continue
    count=$((count + 1))

    [[ -n "$task_branch" && "$task_branch" == task/* ]] || framework_release_topology_die "invalid task branch for ${task_id}: ${task_branch}" || return $?
    [[ -n "$task_base" ]] || framework_release_topology_die "missing task base for ${task_id}" || return $?
    [[ -n "$pr_number" ]] || framework_release_topology_die "missing PR number for ${task_id}" || return $?
    [[ -n "$pr_state" ]] || framework_release_topology_die "missing PR state for ${task_id} PR #${pr_number}" || return $?
    [[ -n "$pr_base" ]] || framework_release_topology_die "missing PR base for ${task_id} PR #${pr_number}" || return $?
    [[ -n "$pr_head_sha" ]] || framework_release_topology_die "missing PR head SHA for ${task_id} PR #${pr_number}" || return $?
    [[ "$pr_head_branch" == "$task_branch" ]] || framework_release_topology_die "PR #${pr_number} for ${task_id} head branch is ${pr_head_branch}; expected ${task_branch}" || return $?

    task_ids+=("$task_id")
    task_branches+=("$task_branch")
    task_bases+=("$task_base")
    pr_numbers+=("$pr_number")
    pr_states+=("$pr_state")
    pr_bases+=("$pr_base")
    pr_head_branches+=("$pr_head_branch")
    pr_head_shas+=("$pr_head_sha")

    if [[ "$count" -eq 1 ]]; then
      first_pr_base="$pr_base"
      same_base_count=1
    else
      [[ "$pr_base" == "$first_pr_base" ]] && same_base_count=$((same_base_count + 1))
    fi
  done

  [[ "$count" -gt 0 ]] || framework_release_topology_die "no PR records supplied" || return $?
  if [[ "$count" -eq 1 ]]; then
    printf 'topology=single_pr prs=1\n'
    return 0
  fi

  local i
  for (( i=0; i<count; i++ )); do
    task_id="${task_ids[$i]}"
    task_branch="${task_branches[$i]}"
    task_base="${task_bases[$i]}"
    pr_number="${pr_numbers[$i]}"
    pr_base="${pr_bases[$i]}"
    pr_head_sha="${pr_head_shas[$i]}"

    if [[ "$i" -eq 0 ]]; then
      [[ "$pr_base" == "$task_base" ]] \
        || framework_release_topology_die "PR #${pr_number} for ${task_id} base is ${pr_base}; expected initial task base ${task_base}" || return $?
    else
      if [[ "$pr_base" == "$previous_head_branch" ]]; then
        stack_edges=$((stack_edges + 1))
      elif [[ "$task_base" == "$previous_task_branch" && "$pr_base" == "$first_pr_base" && "$first_pr_base" == feat/DP-* ]]; then
        git -C "$repo" cat-file -e "${previous_head_sha}^{commit}" >/dev/null 2>&1 \
          || framework_release_topology_die "cannot normalize PR #${pr_number} for ${task_id}: upstream task head ${previous_head_sha} is not a local commit" || return $?
        git -C "$repo" cat-file -e "${pr_head_sha}^{commit}" >/dev/null 2>&1 \
          || framework_release_topology_die "cannot normalize PR #${pr_number} for ${task_id}: PR head ${pr_head_sha} is not a local commit" || return $?
        git -C "$repo" merge-base --is-ancestor "$previous_head_sha" "$pr_head_sha" || {
          framework_release_topology_die "invalid topology=sibling_parallel_invalid base=${first_pr_base} PR #${pr_number} for ${task_id} does not contain upstream task head ${previous_head_sha}; rebase downstream task PRs onto their direct predecessor or collapse implementation into one PR before framework-release."
          return $?
        }
        stack_edges=$((stack_edges + 1))
      else
        framework_release_topology_die "PR #${pr_number} for ${task_id} base is ${pr_base}; expected declared stack base ${previous_head_branch} or ancestry-proven retarget to ${first_pr_base}"
        return $?
      fi
    fi

    previous_task_branch="$task_branch"
    previous_head_branch="$task_branch"
    previous_head_sha="$pr_head_sha"
  done

  if [[ "$stack_edges" -eq $((count - 1)) ]]; then
    printf 'topology=stack_pr prs=%s normalized_base=%s\n' "$count" "$first_pr_base"
    return 0
  fi

  if [[ "$same_base_count" -eq "$count" && "$first_pr_base" == feat/DP-* ]]; then
    framework_release_topology_die "invalid topology=sibling_parallel_invalid base=${first_pr_base} prs=${count}; offending PRs are sibling heads for one framework DP. Convert to a declared stack or a single source-level PR before release."
    return $?
  fi
  framework_release_topology_die "invalid topology=undeclared_stack prs=${count}; PR base/head metadata does not form a legal framework DP release chain."
}

framework_release_topology_validate_ancestor_trace() {
  local repo="$1"
  local final_head="$2"
  shift 2
  local entry task_id head

  [[ -d "$repo/.git" || -f "$repo/.git" ]] || framework_release_topology_die "not a git repository: $repo" || return $?
  [[ -n "$final_head" ]] || framework_release_topology_die "final release head is required" || return $?
  git -C "$repo" cat-file -e "${final_head}^{commit}" >/dev/null 2>&1 || {
    framework_release_topology_die "final release head not found: $final_head"
    return $?
  }

  for entry in "$@"; do
    task_id="${entry%%=*}"
    head="${entry#*=}"
    [[ -n "$task_id" && -n "$head" && "$task_id" != "$head" ]] \
      || framework_release_topology_die "task head entry must be TASK_ID=SHA: $entry" || return $?
    git -C "$repo" cat-file -e "${head}^{commit}" >/dev/null 2>&1 || {
      framework_release_topology_die "task head for ${task_id} not found: ${head}"
      return $?
    }
    git -C "$repo" merge-base --is-ancestor "$head" "$final_head" || {
      framework_release_topology_die "squash-like trace loss: ${task_id} head ${head} is not an ancestor of final release head ${final_head}. Rebuild the release as a fast-forward stack; do not repair with squash, soft reset, or metadata-only bundle alias."
      return $?
    }
  done

  printf 'ancestor_trace=pass final_head=%s tasks=%s\n' "$final_head" "$#"
}
