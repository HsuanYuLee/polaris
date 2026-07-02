#!/usr/bin/env bash
# Purpose: task chain, bundle detection, and PR lineage planning for framework-release-pr-lane.sh.

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
    task_md="$(abs_path "$task_md")"
    if [[ "$task_md" != "$REPO_PATH"/* || ! -d "$REPO_PATH/docs-manager/src/content/docs/specs" ]]; then
      rm -f "$resolver_err" "$resolver_out"
      return 0
    fi
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

  local terminal_abs terminal_source_container
  local seen_tasks=()
  terminal_abs="$(abs_path "$TERMINAL_TASK_MD")"
  terminal_source_container="${terminal_abs%%/tasks/*}"

  resolve_task_for_branch() {
    local branch="$1"
    local fallback="$2"
    local resolved="" candidate
    resolved="$(bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --scan-root "$REPO_PATH" "$branch" | head -1 || true)"
    if [[ -z "$resolved" && -d "$terminal_source_container/tasks" ]]; then
      while IFS= read -r candidate; do
        if [[ "$(table_field "Task branch" "$candidate")" == "$branch" ]]; then
          resolved="$candidate"
          break
        fi
      done < <(find "$terminal_source_container/tasks" -type f \( -name 'index.md' -o -name 'T*.md' \) | sort)
    fi
    if [[ -z "$resolved" && -n "$fallback" ]]; then
      resolved="$fallback"
    fi
    [[ -n "$resolved" ]] || die "could not resolve task.md for branch in chain: $branch"
    abs_path "$resolved"
  }

  append_task_with_upstream() {
    local task_md="$1"
    local task_abs base upstream
    task_abs="$(abs_path "$task_md")"
    if [[ ${#seen_tasks[@]} -gt 0 ]] && line_in_list "$task_abs" "${seen_tasks[@]}"; then
      return 0
    fi
    seen_tasks+=("$task_abs")
    base="$(table_field "Base branch" "$task_abs")"
    if [[ "$base" == task/* ]]; then
      upstream="$(resolve_task_for_branch "$base" "")"
      append_task_with_upstream "$upstream"
    fi
    TASK_MDS+=("$task_abs")
  }

  append_task_with_upstream "$terminal_abs"
  [[ ${#TASK_MDS[@]} -gt 0 ]] || die "no task branches found in terminal Branch chain"

  if [[ "$MAIN_BRANCH_EXPLICIT" -eq 0 ]]; then
    local first_base
    first_base="$(table_field "Base branch" "${TASK_MDS[0]}")"
    if is_feat_aggregation_branch "$first_base"; then
      MAIN_BRANCH="$first_base"
    fi
  fi
}

# DP-270 (D1/D2 + AC-NEG2): inspect the resolved TASK_MDS for a shared
# bundle_branch_alias frontmatter.
#   * none of the task.md declare an alias -> per-task mode (BUNDLE_ALIAS stays
#     empty; unchanged behavior, AC-NEG1).
#   * all task.md share one alias              -> bundle mode (BUNDLE_ALIAS set).
#   * aliases inconsistent / partially present -> fail-closed (AC-NEG2): a
#     bundle must group exactly one shared alias; no partial / mixed plan.
detect_bundle() {
  local task_md alias first_alias="" with_alias=0 total=0
  for task_md in "${TASK_MDS[@]}"; do
    total=$((total + 1))
    alias="$(task_md_bundle_alias "$task_md")"
    if [[ -n "$alias" ]]; then
      with_alias=$((with_alias + 1))
      if [[ -z "$first_alias" ]]; then
        first_alias="$alias"
      elif [[ "$alias" != "$first_alias" ]]; then
        die "release preflight blocked: bundle members declare inconsistent bundle_branch_alias ('$first_alias' vs '$alias'). All members of one bundle must share a single alias; refusing to plan a mixed merge."
      fi
    fi
  done

  if [[ "$with_alias" -eq 0 ]]; then
    BUNDLE_ALIAS=""
    return 0
  fi
  if [[ "$with_alias" -ne "$total" ]]; then
    die "release preflight blocked: bundle is partially declared ($with_alias of $total task.md carry bundle_branch_alias='$first_alias'). Every bundle member must share the alias; refusing to plan a partial merge."
  fi
  BUNDLE_ALIAS="$first_alias"
}

# DP-270 (D2/AC1 + AC-NEG2): bundle release plan.
#   * one `gh pr view` on the bundle branch (the shared alias);
#   * per-member lineage: each member task.md must resolve from the bundle
#     branch (resolver multi-match) and pr_head must equal the bundle alias;
#   * exactly one merge planned (no per-task merge, no no-PR-found die);
#   * fail-closed (AC-NEG2) when the bundle branch has no PR.
validate_and_plan_bundle() {
  local json number state base head head_branch url
  local task_md task_id member_branch
  local resolver_err resolver_out resolver_status resolved

  echo "$PREFIX release lane plan (bundle ${BUNDLE_ALIAS}):"

  set +e
  json="$(pr_view_json "$BUNDLE_ALIAS" 2>/dev/null)"
  local pr_view_status=$?
  set -e
  if [[ "$pr_view_status" -ne 0 || -z "$json" ]]; then
    die "release preflight blocked: bundle_branch_alias '$BUNDLE_ALIAS' has no open PR. Every bundle member points at this branch; refusing to plan a partial merge."
  fi

  number="$(json_field "$json" "d.get('number')")"
  state="$(json_field "$json" "d.get('state')")"
  base="$(json_field "$json" "d.get('baseRefName')")"
  head="$(json_field "$json" "d.get('headRefOid')")"
  head_branch="$(json_field "$json" "d.get('headRefName')")"
  url="$(json_field "$json" "d.get('url')")"

  [[ -n "$number" ]] || die "release preflight blocked: bundle_branch_alias '$BUNDLE_ALIAS' has no open PR (empty PR number). Refusing to plan a partial merge."
  [[ "$state" != "CLOSED" ]] || die "bundle PR #$number for '$BUNDLE_ALIAS' is CLOSED: $url"
  [[ -n "$head" ]] || die "bundle PR #$number for '$BUNDLE_ALIAS' has empty headRefOid"
  [[ "$head_branch" == "$BUNDLE_ALIAS" ]] || die "bundle PR #$number head is '$head_branch'; expected bundle branch '$BUNDLE_ALIAS'"
  [[ "$base" == "$MAIN_BRANCH" ]] || die "bundle PR #$number base is '$base'; expected '$MAIN_BRANCH'"

  # Resolve the bundle branch back to its members once; the resolver returns
  # every task.md sharing the alias (multi-match is legal).
  resolver_err="$(mktemp -t framework-release-pr-lane-bundle-err.XXXXXX)"
  resolver_out="$(mktemp -t framework-release-pr-lane-bundle-out.XXXXXX)"
  set +e
  bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --scan-root "$REPO_PATH" "$BUNDLE_ALIAS" >"$resolver_out" 2>"$resolver_err"
  resolver_status=$?
  set -e
  resolved=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && resolved+=("$line")
  done < "$resolver_out"
  rm -f "$resolver_err" "$resolver_out"
  [[ "$resolver_status" -eq 0 && ${#resolved[@]} -gt 0 ]] \
    || die "release preflight blocked: bundle branch '$BUNDLE_ALIAS' resolves to no task.md lineage."

  # Verify every supplied member is in the resolved set and carries the alias.
  for task_md in "${TASK_MDS[@]}"; do
    [[ -f "$task_md" ]] || die "task.md not found: $task_md"
    task_id="$(table_field "Task ID" "$task_md")"
    [[ -n "$task_id" ]] || task_id="$(table_field "Task JIRA key" "$task_md")"
    member_branch="$(table_field "Task branch" "$task_md")"
    [[ "$member_branch" == task/* ]] || die "release preflight blocked: bundle member $task_id uses Task branch '$member_branch', not a DP task branch."
    check_task_upstream_evidence_freshness "$task_md" "${task_id:-$member_branch}" "$head"
    if ! line_in_list "$(abs_path "$task_md")" "${resolved[@]}"; then
      die "release preflight blocked: bundle member $task_id ($task_md) does not resolve from bundle branch '$BUNDLE_ALIAS'. Resolved members: ${resolved[*]}"
    fi
    printf '  - member %s task_branch=%s (verified against bundle PR #%s)\n' \
      "${task_id:-$member_branch}" "$member_branch" "$number"
  done

  printf '  => bundle PR #%s base=%s state=%s head=%s action=merge into %s (single merge for %d member(s))\n' \
    "$number" "$base" "$state" "$head" "$MAIN_BRANCH" "${#TASK_MDS[@]}"

  if [[ "$EXECUTE" == "1" && "$state" != "MERGED" ]]; then
    info "merging bundle PR #$number ($BUNDLE_ALIAS)"
    "$GH_BIN" pr merge "$number" ${gh_repo_args[@]+"${gh_repo_args[@]}"} --merge
  fi

  if [[ "$REQUIRE_MAIN_CONTAINS_FINAL" == "1" ]]; then
    [[ -n "$head" ]] || die "cannot check final ancestry without bundle head"
    git -C "$REPO_PATH" fetch origin "$MAIN_BRANCH" >/dev/null
    git -C "$REPO_PATH" merge-base --is-ancestor "$head" "origin/$MAIN_BRANCH" \
      || die "origin/$MAIN_BRANCH does not contain bundle head $head"
    info "origin/$MAIN_BRANCH contains bundle head $head"
  fi
}

validate_and_plan() {
  local previous_branch=""
  local previous_state=""
  local idx=0
  local final_head=""
  local task_md task_id task_branch expected_initial_base json number state base head head_branch url action
  local expected_base upstream_state
  local seen_branches=()
  local seen_states=()

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
    check_task_upstream_evidence_freshness "$task_md" "${task_id:-$task_branch}" "$head"
    verify_pr_task_lineage "$task_md" "$task_id" "$task_branch" "$number" "$head_branch"

    if is_feat_aggregation_branch "$base"; then
      if [[ "$state" == "MERGED" ]]; then
        action="already merged into $base"
      elif remote_branch_contains_head "$base" "$head"; then
        action="already integrated into $base"
      else
        action="fast-forward $base to task head before release"
      fi
    elif [[ "$DAG_MODE" == "1" ]]; then
      expected_base="$(table_field "Base branch" "$task_md")"
      [[ -n "$expected_base" ]] || die "missing Base branch in $task_md"
      action="merge into $MAIN_BRANCH"
      if [[ "$base" == "$expected_base" ]]; then
        if [[ "$base" != "$MAIN_BRANCH" ]]; then
          upstream_state=""
          for (( i=0; i<${#seen_branches[@]}; i++ )); do
            if [[ "${seen_branches[$i]}" == "$base" ]]; then
              upstream_state="${seen_states[$i]}"
              break
            fi
          done
          [[ -n "$upstream_state" ]] || die "$task_id PR #$number base is '$base', but upstream base branch was not seen earlier in --task-md DAG order"
          if [[ "$EXECUTE" == "1" ]]; then
            [[ "$upstream_state" == "MERGED" ]] || die "$task_id PR #$number cannot be retargeted because upstream base '$base' is not merged yet"
            action="retarget to $MAIN_BRANCH, then merge"
          else
            action="retarget to $MAIN_BRANCH after upstream merge"
          fi
        fi
      elif [[ "$base" == "$MAIN_BRANCH" ]]; then
        action="merge into $MAIN_BRANCH"
      else
        die "$task_id PR #$number base is '$base'; expected task.md Base branch '$expected_base' or '$MAIN_BRANCH' after upstream merge"
      fi
    elif [[ $idx -eq 0 ]]; then
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
      if is_feat_aggregation_branch "$base"; then
        if remote_branch_contains_head "$base" "$head"; then
          info "PR #$number ($task_id) head already integrated into $base"
        else
          fast_forward_feat_task_pr "$task_id" "$number" "$base" "$head_branch" "$head"
        fi
      elif [[ "$DAG_MODE" == "1" && "$base" != "$MAIN_BRANCH" ]]; then
        info "retargeting PR #$number ($task_id) from $base to $MAIN_BRANCH"
        "$GH_BIN" pr edit "$number" ${gh_repo_args[@]+"${gh_repo_args[@]}"} --base "$MAIN_BRANCH"
        json="$(pr_view_json "$task_branch")"
        base="$(json_field "$json" "d.get('baseRefName')")"
        [[ "$base" == "$MAIN_BRANCH" ]] || die "PR #$number retarget verification failed; base is '$base'"
      elif [[ $idx -gt 0 && "$base" == "$previous_branch" ]]; then
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
    seen_branches+=("$task_branch")
    seen_states+=("$state")
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
