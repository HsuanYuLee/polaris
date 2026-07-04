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
SCRIPT_MANIFEST_CHECKER="${POLARIS_SCRIPT_MANIFEST_CHECKER:-${SCRIPT_DIR}/check-script-manifest.sh}"
SCRIPT_HEADER_VALIDATOR="${POLARIS_SCRIPT_HEADER_VALIDATOR:-${SCRIPT_DIR}/validate-script-header-comment.sh}"
SCRIPT_CATEGORIZATION_VALIDATOR="${POLARIS_SCRIPT_CATEGORIZATION_VALIDATOR:-${SCRIPT_DIR}/validate-script-categorization.sh}"
GOVERNED_SCRIPT_TEST_RUNNER="${POLARIS_GOVERNED_SCRIPT_TEST_RUNNER:-${SCRIPT_DIR}/run-governed-script-tests.sh}"
TOPOLOGY_LIB="${POLARIS_FRAMEWORK_RELEASE_TOPOLOGY_LIB:-${SCRIPT_DIR}/lib/framework-release-topology.sh}"
WORKSPACE_REPO=""
MAIN_BRANCH="main"
MAIN_BRANCH_EXPLICIT=0
EXECUTE=0
FULL_BACKSTOP=0
REQUIRE_MAIN_CONTAINS_FINAL=0
DAG_MODE=0
GH_BIN="${GH_BIN:-gh}"
TERMINAL_TASK_MD=""
TASK_MDS=()
STACK_TASK_MDS=()
# DP-270: set to the shared bundle_branch_alias when all resolved task.md are
# bundle members; empty in the unchanged per-task release path (AC-NEG1).
BUNDLE_ALIAS=""

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi
# shellcheck source=lib/tool-resolution.sh
. "${SCRIPT_DIR}/lib/tool-resolution.sh"

# shellcheck source=lib/release-gate-core.sh
. "${SCRIPT_DIR}/lib/release-gate-core.sh"
# shellcheck source=lib/release-gate-backstops.sh
. "${SCRIPT_DIR}/lib/release-gate-backstops.sh"
# shellcheck source=lib/release-gate-lineage.sh
. "${SCRIPT_DIR}/lib/release-gate-lineage.sh"
if [[ -f "$TOPOLOGY_LIB" ]]; then
  # shellcheck source=lib/framework-release-topology.sh
  . "$TOPOLOGY_LIB"
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
  --list-stage-owners        Print release-blocking stage owner matrix and exit
  --full-backstop            Transitional explicit mode: also run upstream-owned
                             script-authoring / selftest backstop stages (R2-R6)
  --main <branch>            Main branch name (default: main)
  --execute                  Integrate open PR heads in order. For feat/DP-NNN
                             aggregation lanes, fast-forward feat to each task
                             head without GitHub merge commits; legacy main/DAG
                             lanes retain existing PR merge behavior.
  --allow-dag                Validate explicit --task-md list as a topological DAG,
                             not as one linear branch chain
  --require-main-contains-final
                             After execution/preflight, require origin/main contains final head
  -h, --help                 Show help

Default mode is dry-run preflight: no GitHub writes.
EOF
}

validate_structured_pr_topology() {
  [[ -z "$BUNDLE_ALIAS" ]] || return 0
  if ! declare -F framework_release_topology_validate_pr_records_with_git >/dev/null 2>&1; then
    die "release preflight blocked: structured PR topology guard is unavailable. Expected helper: $TOPOLOGY_LIB"
  fi

  local records task_md task_id task_branch task_base json number state base head head_branch
  records="$(mktemp -t framework-release-pr-records.XXXXXX.tsv)"
  printf 'task_id|task_branch|task_base|pr_number|pr_state|pr_base|pr_head_branch|pr_head_sha\n' >"$records"

  for task_md in "${STACK_TASK_MDS[@]}"; do
    [[ -f "$task_md" ]] || die "task.md not found: $task_md"
    task_id="$(table_field "Task ID" "$task_md")"
    [[ -n "$task_id" ]] || task_id="$(table_field "Task JIRA key" "$task_md")"
    task_branch="$(table_field "Task branch" "$task_md")"
    task_base="$(table_field "Base branch" "$task_md")"
    [[ -n "$task_branch" ]] || die "missing Task branch in $task_md"
    [[ -n "$task_base" ]] || die "missing Base branch in $task_md"

    json="$(pr_view_json "$task_branch")" || die "gh pr view failed for $task_branch"
    number="$(json_field "$json" "d.get('number')")"
    state="$(json_field "$json" "d.get('state')")"
    base="$(json_field "$json" "d.get('baseRefName')")"
    head="$(json_field "$json" "d.get('headRefOid')")"
    head_branch="$(json_field "$json" "d.get('headRefName')")"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "${task_id:-$task_branch}" "$task_branch" "$task_base" "$number" "$state" "$base" "$head_branch" "$head" >>"$records"
  done

  framework_release_topology_validate_pr_records_with_git "$REPO_PATH" <"$records" >/dev/null
  rm -f "$records"
}

release_lane_frontmatter_scalar() {
  local field="$1"
  local file="$2"
  awk -v key="$field" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      split($0, parts, ":")
      f = parts[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        sub(/^[^:]*:[[:space:]]*/, "", $0)
        gsub(/^["'\'' ]+|["'\'' ]+$/, "", $0)
        print $0
        exit
      }
    }
  ' "$file"
}

release_lane_build_stack_task_mds() {
  local task_md task_id task_kind task_branch
  STACK_TASK_MDS=()
  for task_md in "${TASK_MDS[@]}"; do
    [[ -f "$task_md" ]] || die "task.md not found: $task_md"
    task_id="$(table_field "Task ID" "$task_md")"
    [[ -n "$task_id" ]] || task_id="$(table_field "Task JIRA key" "$task_md")"
    task_kind="$(release_lane_frontmatter_scalar "task_kind" "$task_md")"
    task_branch="$(table_field "Task branch" "$task_md")"
    if [[ "$task_kind" == "V" && ( -z "$task_branch" || "$task_branch" == "N/A" ) ]]; then
      info "V evidence task ${task_id:-$task_md} has no implementation PR; excluding it from release PR stack topology and leaving it to closeout V enumeration"
      continue
    fi
    STACK_TASK_MDS+=("$task_md")
  done
  [[ "${#STACK_TASK_MDS[@]}" -gt 0 ]] \
    || die "release preflight blocked: no implementation task PRs supplied after V evidence filtering; V-only verification evidence is closed by framework-release closeout, not the PR lane"
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
      --list-stage-owners) list_stage_owners; exit 0 ;;
      --full-backstop) FULL_BACKSTOP=1; shift ;;
      --main) MAIN_BRANCH="$2"; MAIN_BRANCH_EXPLICIT=1; shift 2 ;;
      --main=*) MAIN_BRANCH="${1#--main=}"; MAIN_BRANCH_EXPLICIT=1; shift ;;
      --execute) EXECUTE=1; shift ;;
      --allow-dag) DAG_MODE=1; shift ;;
      --require-main-contains-final) REQUIRE_MAIN_CONTAINS_FINAL=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  REPO_PATH="$(abs_path "$REPO_PATH")"
  resolve_workspace_repo_slug
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
  release_lane_build_stack_task_mds
  TASK_MDS=("${STACK_TASK_MDS[@]}")
  detect_bundle
  if [[ -z "$BUNDLE_ALIAS" ]]; then
    if ! declare -F framework_release_topology_classify_task_mds >/dev/null 2>&1; then
      die "release preflight blocked: framework release topology guard is unavailable. Expected helper: $TOPOLOGY_LIB"
    fi
    framework_release_topology_classify_task_mds "${STACK_TASK_MDS[@]}" >/dev/null
  fi
  validate_structured_pr_topology

  run_script_manifest_release_gate
  if [[ -n "$BUNDLE_ALIAS" ]]; then
    validate_and_plan_bundle
  else
    validate_and_plan
  fi
  run_upstream_backstop_gates_if_requested
  echo "$PREFIX PASS"
fi
