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
TASK_HEAD_SHA_MAP=""
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

# Purpose: DP-419 T4 (D5) framework-release promotion-後 tail self-referential-window guard.
#   When THIS release stack is self-referential (its planned-task Allowed Files intersect the
#   delivery-gate script set, which includes framework-release-pr-lane.sh itself), the promotion
#   tail would run the just-merged NEW gate/lane version; a bug there blows up closeout. So a
#   self-referential release requires the full governed selftest corpus to be green BEFORE
#   promotion. Non-green corpus is the ONLY hard-block (fail-closed). Mirrors T3 selfref_self_verify.
# Args: $1 = repo_root ; $2.. = Allowed Files paths (aggregated across the release stack)
# Returns: 0 = proceed (not self-ref, OR self-ref + corpus green) ; 10 = carve-out N/A
#   (undeterminable scope: no files / classifier absent / classifier can't decide) ;
#   1 = self-ref CONFIRMED but corpus red/unavailable (hard-block)
# POLARIS_DETECT_SELFREF_BIN / POLARIS_AGGREGATE_SELFTESTS_BIN are *_BIN test-injection seams
# (NOT *_BYPASS): they only relocate the two external commands for hermetic selftests; the normal
# tail path leaves them at their canonical repo paths and never silences the corpus requirement.
release_lane_selfref_tail_guard() {
  local repo_root="$1"; shift
  local -a allowed=("$@")
  # (1) missing input -> self-ref scope undeterminable -> carve-out N/A (proceed to the normal
  #     lane), NOT a hard block: an underivable Allowed Files set must not block every release.
  [[ "${#allowed[@]}" -gt 0 ]] || return 10
  local classifier="${POLARIS_DETECT_SELFREF_BIN:-$repo_root/scripts/detect-self-referential-delivery.sh}"
  local corpus="${POLARIS_AGGREGATE_SELFTESTS_BIN:-$repo_root/scripts/run-aggregate-selftests.sh}"
  local out
  # (2) run the classifier; if it cannot run/decide (absent binary, exit != 0) the self-ref scope
  #     is undeterminable -> carve-out N/A (return 10), NOT a hard block.
  out="$(printf '%s\n' "${allowed[@]}" | bash "$classifier" --stdin --repo-root "$repo_root" 2>/dev/null)" || return 10
  # (3) not self-referential -> carve-out N/A; caller proceeds to the normal lane.
  if ! printf '%s' "$out" | grep -Eq '"self_referential"[[:space:]]*:[[:space:]]*true'; then
    return 10
  fi
  # (4) self-referential CONFIRMED -> the CURRENT full governed selftest corpus must be green.
  #     Green -> proceed (0); red / unavailable -> this is the ONLY hard-block (fail-closed).
  bash "$corpus" >/dev/null 2>&1 || return 1
  return 0
}


# Source-guard the CLI exec flow so test harnesses (e.g. the corpus-count
# robustness selftest) can `source` this script to call individual helpers like
# release_lane_corpus_present without triggering the full release-lane run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --selfref-tail-guard)
        # Hidden test seam (mirrors T3 check-framework-pr-gate.sh --selfref-self-verify): runs ONLY
        # release_lane_selfref_tail_guard and maps its return to the exit code the selftest asserts
        # (0 proceed / 1 fail-closed / 10 carve-out N/A). Short-circuits the rest of arg parsing so
        # the guard is unit-testable without building a whole release stack.
        shift
        _stg_repo="$REPO_PATH"
        _stg_af=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --allowed-file)
              [[ $# -ge 2 ]] || die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --allowed-file requires a value"
              _stg_af+=("$2"); shift 2 ;;
            --repo-root)
              [[ $# -ge 2 ]] || die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --repo-root requires a value"
              _stg_repo="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        set +e
        release_lane_selfref_tail_guard "$_stg_repo" "${_stg_af[@]+"${_stg_af[@]}"}"
        _stg_rc=$?
        set -e
        exit "$_stg_rc"
        ;;
      --repo) REPO_PATH="$2"; shift 2 ;;
      --repo=*) REPO_PATH="${1#--repo=}"; shift ;;
      --workspace-repo) WORKSPACE_REPO="$2"; shift 2 ;;
      --workspace-repo=*) WORKSPACE_REPO="${1#--workspace-repo=}"; shift ;;
      --terminal-task-md) TERMINAL_TASK_MD="$2"; shift 2 ;;
      --terminal-task-md=*) TERMINAL_TASK_MD="${1#--terminal-task-md=}"; shift ;;
      --task-md) TASK_MDS+=("$(abs_path "$2")"); shift 2 ;;
      --task-md=*) TASK_MDS+=("$(abs_path "${1#--task-md=}")"); shift ;;
      --task-head-sha) TASK_HEAD_SHA_MAP="$2"; shift 2 ;;
      --task-head-sha=*) TASK_HEAD_SHA_MAP="${1#--task-head-sha=}"; shift ;;
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

  # DP-417 T15: framework-release delivery-evidence conformance preflight. Runs on the resolved
  # local stack task.md paths BEFORE the first GitHub PR lookup, so a missing / malformed / stale
  # DP-360 deliverable.head_sha delivery block fails closed here with a per-task enumeration
  # (POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT) instead of surfacing as the late generic no-PR error
  # deep in topology validation. Framework-DP-only (no-op on jira source). Reuses the canonical
  # parse-task-md reader; no second delivery-block reader.
  DELIVERY_EVIDENCE_GATE="$SCRIPT_DIR/validate-delivery-evidence-conformance.sh"
  if [[ -f "$DELIVERY_EVIDENCE_GATE" ]]; then
    DEC_ARGS=()
    for _dec_task in "${STACK_TASK_MDS[@]}"; do
      DEC_ARGS+=(--task-md "$_dec_task")
    done
    # Forward the DP-360 authority-order #1 override map so PR-less direct-commit-to-feat tasks can
    # supply their delivered head without a fabricated PR URL (same --task-head-sha map as closeout).
    [[ -n "$TASK_HEAD_SHA_MAP" ]] && DEC_ARGS+=(--task-head-sha "$TASK_HEAD_SHA_MAP")
    bash "$DELIVERY_EVIDENCE_GATE" --mode pre-release "${DEC_ARGS[@]}" \
      || die "release preflight blocked: delivery-evidence conformance gate failed (see POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT above; each required task needs a resolvable delivered head via --task-head-sha override or task.md deliverable.head_sha)"
  fi

  # DP-419 T4 (D5): framework-release promotion-後 tail self-referential-window guard. When THIS
  # release stack is self-referential (its planned-task Allowed Files intersect the delivery-gate
  # script set, which includes framework-release-pr-lane.sh itself), the promotion tail runs the
  # just-merged NEW gate/lane version; a bug there blows up closeout. So a self-referential release
  # requires the full governed selftest corpus to be green BEFORE promotion. Canonical contract:
  # .claude/skills/references/self-referential-dp-delivery.md.
  _selfref_allowed=()
  for _sr_task in "${STACK_TASK_MDS[@]}"; do
    while IFS= read -r _sr_af; do
      [[ -n "$_sr_af" ]] && _selfref_allowed+=("$_sr_af")
    done < <(bash "$SCRIPT_DIR/parse-task-md.sh" "$_sr_task" --field allowed_files 2>/dev/null || true)
  done
  _selfref_rc=0
  release_lane_selfref_tail_guard "$REPO_PATH" "${_selfref_allowed[@]+"${_selfref_allowed[@]}"}" || _selfref_rc=$?
  if [[ "$_selfref_rc" -eq 1 ]]; then
    die "release preflight blocked: self-referential release requires a green governed selftest corpus before the promotion tail (run: bash scripts/run-aggregate-selftests.sh); corpus is red/unavailable at HEAD"
  fi

  validate_structured_pr_topology

  run_script_manifest_release_gate
  if [[ -n "$BUNDLE_ALIAS" ]]; then
    validate_and_plan_bundle
  else
    # validate_and_plan checks freshness against top-level deliverable.head_sha
    # via release-gate-lineage; verification aggregate heads are evidence only.
    validate_and_plan
  fi
  run_upstream_backstop_gates_if_requested
  echo "$PREFIX PASS"
fi
