#!/usr/bin/env bash
# Purpose: selftest for the DP-316 canonical level projection in
#   derive-task-md-from-refinement-json.sh. The derive bridge projects the wider
#   refinement.json `test_environment.level` enum onto the narrower task.md Level
#   enum (static / build / runtime) that validate-task-md.sh accepts, instead of
#   copying the refinement value verbatim.
# Inputs:  none (constructs refinement.json fixtures in a tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# AC coverage (DP-316-T1):
#   AC1     : refinement level=component -> task.md Level=build, and the derived
#             task.md passes validate-task-md.sh.
#   AC2     : projection identity + many-to-one — static->static,
#             integration->build, runtime->runtime asserted individually.
#   AC-NEG1 : unknown / not-in-table level -> derive fail-louds (exit != 0); no
#             silent fallback to static.
#   AC-NEG2 : existing build/static/runtime derived task.md still passes
#             validate-task-md.sh (the validator enum line is untouched).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
VALIDATE_TASK_MD="$ROOT_DIR/scripts/validate-task-md.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }
[[ -x "$VALIDATE_TASK_MD" ]] || { echo "FAIL: validate-task-md.sh not executable" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-level-projection.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Description: write a single-task refinement.json fixture whose only varying
#   input is test_environment.level, then return its path on stdout.
# Args:        $1 = refinement-side test_environment.level value
# Side effects: creates a file under $tmpdir
make_fixture() {
  local level="$1"
  local path="$tmpdir/refinement-level-$level.json"
  cat >"$path" <<JSON
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-999-sample",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "level projection fixture task",
      "scope": "驗證 derive bridge 把 refinement level 投影到 task.md Level enum。",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/sample-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh",
        "verify_command": "bash scripts/selftests/sample-selftest.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" },
        "test_environment": { "level": "$level" }
      }
    }
  ]
}
JSON
  printf '%s\n' "$path"
}

# Description: derive a task.md for the given refinement level and assert the
#   rendered '- **Level**:' line matches the expected projected value. When
#   $4 == "validate", also assert the derived task.md passes validate-task-md.sh.
#   The runtime target is asserted for the projected Level only (identity): a
#   minimal level-runtime fixture cannot satisfy the validator's runtime
#   cross-field contract (live URL / Runtime verify target / Env bootstrap),
#   which is out of scope for the level-projection bridge.
# Args:        $1 = refinement level, $2 = expected task.md Level, $3 = AC label,
#              $4 = "validate" to additionally run validate-task-md.sh (optional)
# Side effects: none beyond reads/writes under $tmpdir
assert_projects_to() {
  local in_level="$1" expected="$2" label="$3" validate="${4:-}"
  local fixture out
  fixture="$(make_fixture "$in_level")"
  out="$tmpdir/task-$in_level.md"
  bash "$SCRIPT" --refinement-json "$fixture" --task-id "DP-999-T1" >"$out" || {
    echo "FAIL [$label]: derive failed for projectable level '$in_level'" >&2
    exit 1
  }
  if ! grep -qF -- "- **Level**: $expected" "$out"; then
    echo "FAIL [$label]: level '$in_level' did not project to Level '$expected'" >&2
    echo "--- rendered Test Environment ---" >&2
    grep -nE '^\- \*\*Level\*\*' "$out" >&2 || true
    exit 1
  fi
  if [[ "$validate" == "validate" ]]; then
    bash "$VALIDATE_TASK_MD" "$out" >/dev/null 2>&1 || {
      echo "FAIL [$label]: projected (Level=$expected) task.md does not pass validate-task-md.sh" >&2
      bash "$VALIDATE_TASK_MD" "$out" >&2 || true
      exit 1
    }
  fi
}

# ---------------------------------------------------------------------------
# Case 1 (AC1 / AC-NEG2): component -> build, derived task.md valid.
# ---------------------------------------------------------------------------
assert_projects_to "component" "build" "case 1 / AC1" validate

# ---------------------------------------------------------------------------
# Case 2 (AC2 / AC-NEG2): identity + many-to-one mappings. static->static and
# integration->build also pass validate-task-md.sh (regression: those Level
# values are the validator-accepted enum, untouched by this change).
# runtime->runtime asserts the identity projection only; a minimal runtime
# fixture cannot satisfy the validator's runtime cross-field contract, which is
# out of the level-projection scope.
# ---------------------------------------------------------------------------
assert_projects_to "static" "static" "case 2 / AC2 static->static" validate
assert_projects_to "integration" "build" "case 2 / AC2 integration->build" validate
assert_projects_to "runtime" "runtime" "case 2 / AC2 runtime->runtime"

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG1): an unknown / not-in-table level fail-louds (exit != 0) and
# does NOT silently fall back to static.
# ---------------------------------------------------------------------------
unknown_fixture="$(make_fixture "componnt")"  # deliberate typo of "component"
unknown_out="$tmpdir/task-unknown.md"
unknown_err="$tmpdir/task-unknown.err"
set +e
bash "$SCRIPT" --refinement-json "$unknown_fixture" --task-id "DP-999-T1" >"$unknown_out" 2>"$unknown_err"
unknown_rc=$?
set -e
if [[ "$unknown_rc" -eq 0 ]]; then
  echo "FAIL [case 3 / AC-NEG1]: unknown level was accepted (exit 0) instead of fail-loud" >&2
  echo "--- rendered output ---" >&2
  cat "$unknown_out" >&2
  exit 1
fi
if grep -qF -- "- **Level**: static" "$unknown_out" 2>/dev/null; then
  echo "FAIL [case 3 / AC-NEG1]: unknown level silently fell back to Level=static" >&2
  exit 1
fi
if ! grep -q 'not a projectable level' "$unknown_err"; then
  echo "FAIL [case 3 / AC-NEG1]: fail-loud message missing the projection rationale (rc=$unknown_rc)" >&2
  cat "$unknown_err" >&2
  exit 1
fi

echo "PASS: derive-task-md-level-projection selftest"
