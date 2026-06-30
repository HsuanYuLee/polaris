#!/usr/bin/env bash
set -euo pipefail

# framework-release-pr-lane.sh
#
# Deterministic preflight / executor for DP-backed framework workspace PR lanes.
# It verifies that a task chain's PR bases match the task.md Branch chain before
# framework-release syncs workspace main to the Polaris template repo.
#
# DP-295 T6: version + CHANGELOG are now consumed changeset-driven INSIDE the PR
# via `mise run release:version` (scripts/release-version.sh) so they ride the
# verified PR HEAD. This lane no longer runs a separate pre-merge VERSION-bump
# gate and no longer defers a post-merge VERSION/CHANGELOG release-metadata step;
# it converges to lineage validation + merge, leaving tag / sync / GitHub release
# / closeout to framework-release. release-readiness (changeset present +
# VERSION ≡ package.json + CHANGELOG) is enforced earlier in ci-local / remote
# CI (T4).

PREFIX="[framework-release-pr-lane]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"
SCRIPT_MANIFEST_CHECKER="${SCRIPT_DIR}/check-script-manifest.sh"
SCRIPT_HEADER_VALIDATOR="${SCRIPT_DIR}/validate-script-header-comment.sh"
SCRIPT_CATEGORIZATION_VALIDATOR="${SCRIPT_DIR}/validate-script-categorization.sh"
GOVERNED_SCRIPT_TEST_RUNNER="${SCRIPT_DIR}/run-governed-script-tests.sh"
WORKSPACE_REPO=""
MAIN_BRANCH="main"
EXECUTE=0
REQUIRE_MAIN_CONTAINS_FINAL=0
DAG_MODE=0
GH_BIN="${GH_BIN:-gh}"
TERMINAL_TASK_MD=""
TASK_MDS=()
# DP-270: set to the shared bundle_branch_alias when all resolved task.md are
# bundle members; empty in the unchanged per-task release path (AC-NEG1).
BUNDLE_ALIAS=""

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi
# shellcheck source=lib/tool-resolution.sh
. "${SCRIPT_DIR}/lib/tool-resolution.sh"

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
  --allow-dag                Validate explicit --task-md list as a topological DAG,
                             not as one linear branch chain
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

# DP-270: extract `bundle_branch_alias` from a task.md leading YAML frontmatter
# block. Same parse shape as resolve-task-md-by-branch.sh / gate-work-source.sh.
# Empty stdout when the task.md is not a bundle member.
task_md_bundle_alias() {
  local file="$1"
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^bundle_branch_alias:/ {
      sub(/^bundle_branch_alias:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
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

is_feat_aggregation_branch() {
  local branch="$1"
  [[ "$branch" == feat/DP-* ]]
}

gh_repo_args=()
refresh_gh_repo_args() {
  gh_repo_args=()
  if [[ -n "$WORKSPACE_REPO" ]]; then
    gh_repo_args=(--repo "$WORKSPACE_REPO")
  fi
}

resolve_gh_bin() {
  if [[ -n "${GH_BIN:-}" && "$GH_BIN" != "gh" ]]; then
    [[ -x "$GH_BIN" ]] || die "POLARIS_TOOL_MISSING tool=gh owner=delivery install_authority=system hint=GH_BIN is not executable: $GH_BIN"
    "$GH_BIN" auth status >/dev/null 2>&1 || die "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery install_authority=system hint=GitHub CLI is installed but not authenticated"
    return 0
  fi
  GH_BIN="$(polaris_require_delivery_tool gh)" || die "GitHub CLI delivery preflight failed"
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

run_script_manifest_release_gate() {
  [[ -f "$SCRIPT_MANIFEST_CHECKER" ]] || die "missing checker: $SCRIPT_MANIFEST_CHECKER"
  [[ -f "$REPO_PATH/scripts/manifest.json" ]] || die "release preflight blocked: missing scripts/manifest.json"

  info "running script manifest release gate"
  bash "$SCRIPT_MANIFEST_CHECKER" --root "$REPO_PATH" --quiet \
    || die "release preflight blocked: script manifest drift"

  # DP-240 T5 / AC8: same script-audit aggregate as `mise run script-audit`
  # and `check-framework-pr-gate.sh`. Header + categorization run in diff mode
  # against HEAD (no diff in a clean release branch → exit 0).
  if [[ -f "$SCRIPT_HEADER_VALIDATOR" ]]; then
    info "running script header release gate (DP-240 T5)"
    bash "$SCRIPT_HEADER_VALIDATOR" --mode diff --base HEAD \
      || die "release preflight blocked: script header gate"
  fi
  if [[ -f "$SCRIPT_CATEGORIZATION_VALIDATOR" ]]; then
    info "running script categorization release gate (DP-240 T5)"
    bash "$SCRIPT_CATEGORIZATION_VALIDATOR" --mode diff --base HEAD \
      || die "release preflight blocked: script categorization gate"
  fi
}

run_governed_script_tests_release_gate() {
  local final_task_md gate_head_ref
  [[ -f "$GOVERNED_SCRIPT_TEST_RUNNER" ]] || die "missing runner: $GOVERNED_SCRIPT_TEST_RUNNER"

  # DP-270 (AC3): bundle mode runs the governed script test suite against the
  # bundle branch; per-task mode keeps the terminal task branch (AC-NEG1).
  if [[ -n "$BUNDLE_ALIAS" ]]; then
    gate_head_ref="$BUNDLE_ALIAS"
  else
    final_task_md="${TASK_MDS[$((${#TASK_MDS[@]} - 1))]}"
    gate_head_ref="$(table_field "Task branch" "$final_task_md")"
    [[ -n "$gate_head_ref" ]] || die "missing Task branch in terminal task.md: $final_task_md"
  fi

  info "running governed script test suite for ${gate_head_ref}"
  bash "$GOVERNED_SCRIPT_TEST_RUNNER" \
    --root "$REPO_PATH" \
    --profile release \
    --base "origin/${MAIN_BRANCH}" \
    --head-ref "$gate_head_ref" \
    || die "release preflight blocked: governed script tests failed"
}

# run_aggregate_selftests_release_gate — DP-325 T2 / AC3: the release lane must no
# longer rely solely on the 38 governed selftests. Enforce selftest enrollment and
# then execute the full filesystem selftest corpus; any non-quarantined red blocks
# the release. Args: none. Side effects: runs both validators; die() on failure.
# Description: Probe whether a scripts dir ships any *-selftest.sh corpus file.
# Args:        $1 = scripts directory to probe
# Returns:     0 if at least one *-selftest.sh exists (maxdepth 2), 1 if none.
# Side effects: none (read-only filesystem probe). Uses `find -print -quit` — find
#   exits after the first hit, so a populated corpus does NOT leak a SIGPIPE rc=141
#   the way `find ... | head -1` does when head closes the pipe early under
#   `set -o pipefail` (DP-352 Bug #4 hygiene).
release_lane_corpus_present() {
  local scripts_dir="$1"
  local first_hit
  first_hit="$(find "$scripts_dir" -maxdepth 2 -type f -name '*-selftest.sh' -print -quit 2>/dev/null)"
  [[ -n "$first_hit" ]]
}

run_aggregate_selftests_release_gate() {
  local enrollment_gate="${SCRIPT_DIR}/validate-selftest-enrollment.sh"
  local aggregate_runner="${SCRIPT_DIR}/run-aggregate-selftests.sh"

  # Skip-with-log when the target repo has no selftest corpus at all (i.e. not a
  # framework workspace, e.g. a synthetic release-lane fixture). This is NOT a
  # fail-open on real input: a workspace that ships the selftest corpus is gated
  # fail-closed below. A repo with zero *-selftest.sh files is simply out of the
  # selftest-enrollment contract scope.
  if ! release_lane_corpus_present "$REPO_PATH/scripts"; then
    info "no selftest corpus under ${REPO_PATH}/scripts — skipping aggregate selftest release gate (non-framework repo)"
    return 0
  fi

  [[ -f "$enrollment_gate" ]] || die "missing enrollment gate: $enrollment_gate"
  [[ -f "$aggregate_runner" ]] || die "missing aggregate runner: $aggregate_runner"

  info "running selftest enrollment gate (DP-325 T2 / AC2)"
  bash "$enrollment_gate" --root "$REPO_PATH" \
    || die "release preflight blocked: selftest enrollment gap"

  info "running aggregate selftest corpus (DP-325 T2 / AC1+AC3)"
  bash "$aggregate_runner" --root "$REPO_PATH" \
    || die "release preflight blocked: aggregate selftests failed"
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
    verify_pr_task_lineage "$task_md" "$task_id" "$task_branch" "$number" "$head_branch"

    if is_feat_aggregation_branch "$base"; then
      if [[ "$state" == "MERGED" ]]; then
        action="already merged into $base"
      else
        action="merge into $base before release"
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
        :
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

# Source-guard the CLI exec flow so test harnesses (e.g. the corpus-count
# robustness selftest) can `source` this script to call individual helpers like
# release_lane_corpus_present without triggering the full release-lane run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
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
      --allow-dag) DAG_MODE=1; shift ;;
      --require-main-contains-final) REQUIRE_MAIN_CONTAINS_FINAL=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  REPO_PATH="$(abs_path "$REPO_PATH")"
  refresh_gh_repo_args
  resolve_gh_bin

  if [[ ${#TASK_MDS[@]} -eq 0 ]]; then
    resolve_task_mds_from_terminal
  fi

  # DP-270: classify bundle vs per-task before the release gates so the
  # governed-script gates evaluate the correct head ref.
  # DP-295 T6: the pre-merge VERSION-bump gate is removed; version/CHANGELOG are
  # consumed changeset-driven inside the PR (mise run release:version) and ride the
  # verified PR HEAD, so the lane only runs the script-governance gates + merge.
  detect_bundle

  run_script_manifest_release_gate
  run_governed_script_tests_release_gate
  run_aggregate_selftests_release_gate
  if [[ -n "$BUNDLE_ALIAS" ]]; then
    validate_and_plan_bundle
  else
    validate_and_plan
  fi
  echo "$PREFIX PASS"
fi
