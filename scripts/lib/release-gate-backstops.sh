#!/usr/bin/env bash
# Purpose: release-lane script governance and upstream backstop gates for framework-release-pr-lane.sh.

run_script_manifest_release_gate() {
  [[ -f "$SCRIPT_MANIFEST_CHECKER" ]] || die "missing checker: $SCRIPT_MANIFEST_CHECKER"
  [[ -f "$REPO_PATH/scripts/manifest.json" ]] || die "release preflight blocked: missing scripts/manifest.json"

  info "running script manifest release gate"
  bash "$SCRIPT_MANIFEST_CHECKER" --root "$REPO_PATH" --quiet \
    || die "release preflight blocked: script manifest drift"
}

run_script_authoring_backstop_gates() {
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

run_upstream_backstop_gates_if_requested() {
  if [[ "$FULL_BACKSTOP" != "1" ]]; then
    info "running mandatory pre-promotion aggregate selftest backstop; --full-backstop additionally enables upstream script-authoring/governed stages"
    run_aggregate_selftests_release_gate
    return 0
  fi

  info "running explicit --full-backstop upstream-owned release preflight stages (R2-R6)"
  run_script_authoring_backstop_gates
  run_governed_script_tests_release_gate
  run_aggregate_selftests_release_gate
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
