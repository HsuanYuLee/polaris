#!/usr/bin/env bash
# Purpose: selftest for the `## Verification Handoff` section conditionalization in
#   scripts/derive-task-md-from-refinement-json.sh (DP-335 T1 / AC1). Asserts the
#   handoff paragraph is driven by the task's AUTHORITATIVE verification declaration
#   fields (verification.behavior_contract.applies / verification.visual_regression)
#   rather than an unconditional heredoc literal — aligning with the
#   `consumer-reads-authoritative-field` canary (no path / filename heuristic).
# Inputs:  none (constructs refinement.json fixtures in a tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# AC coverage (DP-335):
#   AC1     : a task with NO V acceptance ticket that IS product UI
#             (behavior_contract.applies=true OR visual_regression declared) derives
#             a `## Verification Handoff` that reflects its OWN behavior_contract /
#             visual_regression wiring and does NOT emit the phantom
#             `{source_id}-V1（umbrella regression）` text nor the「framework work
#             order」label.
#   DP-359  : a framework-infra task (behavior_contract.applies=false, no
#             visual_regression) now derives a PER-TASK SELF-CONTAINED handoff (D6) —
#             no phantom `{source_id}-V1（umbrella regression）` delegation. This
#             supersedes the DP-335 framework-DP umbrella-delegation default.
#   AC-NEG1 : no large VR / mobile capability structure is exercised here (this
#             selftest only inspects derived prose, no run-visual-snapshot wiring).
#
# RED→GREEN shape: Case A asserts the phantom text is ABSENT for a product-UI task;
# against the UNPATCHED derive script this case FAILS (the literal handoff line is
# emitted unconditionally), proving the test drives the fix.

set -euo pipefail

# ROOT_DIR resolves from this selftest's own location so the test is CWD-independent
# and runs hermetically from the worktree checkout (DP-301 env-leak discipline: the
# derive script is invoked by absolute path; no POLARIS_WORKSPACE_ROOT dependence).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-vh.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Phantom anchors: the unconditional heredoc literal we are conditionalizing.
PHANTOM_LABEL='framework work order'
PHANTOM_DELEGATION='V1（umbrella regression）'

# Extract just the `## Verification Handoff` section body from a derived task.md.
# Reads from the heading line up to (but excluding) the next `## ` heading.
extract_handoff() {
  local md="$1"
  awk '
    /^## Verification Handoff$/ { capture=1; next }
    capture && /^## / { capture=0 }
    capture { print }
  ' "$md"
}

fail_case() {
  echo "FAIL: $1" >&2
  echo "----- derived Verification Handoff -----" >&2
  cat "$2" >&2
  echo "----------------------------------------" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Case A (RED-driving / AC1): product-UI task with behavior_contract.applies=true
# (full required sub-fields so derive does not fail-loud). The derived handoff
# must NOT carry the phantom umbrella-V1 delegation nor the「framework work order」
# label; it must reflect this task's own behavior_contract wiring.
# ---------------------------------------------------------------------------
case_a_json="$tmpdir/case-a.json"
cat >"$case_a_json" <<'JSON'
{
  "source": {
    "type": "jira",
    "id": "DEMO-4357",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/DEMO-4357",
    "repo": "b2c-web",
    "base_branch": "feat/DEMO-4357",
    "jira_key": "DEMO-4357"
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DEMO-4357-T3",
      "kind": "implementation",
      "jira_key": "DEMO-4364",
      "title": "jQuery → Design-System mobile lib-swap",
      "scope": "把 product UI 的 jQuery 互動換成 Design-System，並以 behavior parity 驗收。",
      "allowed_files": ["apps/main/pages/product/sample.vue"],
      "modules": ["apps/main/pages/product/sample.vue"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 3,
      "verification": {
        "method": "behavior_contract",
        "detail": "node scripts/run-behavior-contract.sh --task DEMO-4357-T3",
        "verify_command": "node scripts/run-behavior-contract.sh --task DEMO-4357-T3",
        "behavior_contract": {
          "applies": true,
          "mode": "parity",
          "source_of_truth": "pre_swap_baseline",
          "fixture_policy": "mockoon_optional",
          "viewport": "mobile",
          "flow": "node scripts/behavior-flows/gt478-jquery-flow-runner.mjs",
          "assertions": ["互動 parity 通過", "視覺 parity 通過"]
        },
        "test_environment": { "level": "runtime" },
        "references": ["scripts/run-behavior-contract.sh"]
      }
    }
  ]
}
JSON

case_a_out="$tmpdir/case-a-task.md"
bash "$SCRIPT" --refinement-json "$case_a_json" --task-id "DEMO-4357-T3" > "$case_a_out"

case_a_handoff="$tmpdir/case-a-handoff.txt"
extract_handoff "$case_a_out" > "$case_a_handoff"

if grep -qF "$PHANTOM_DELEGATION" "$case_a_handoff"; then
  fail_case "Case A (applies=true product UI): handoff still emits phantom umbrella-V1 delegation '$PHANTOM_DELEGATION'" "$case_a_handoff"
fi
if grep -qF "$PHANTOM_LABEL" "$case_a_handoff"; then
  fail_case "Case A (applies=true product UI): handoff still emits phantom「$PHANTOM_LABEL」label" "$case_a_handoff"
fi
# Positive: the conditionalized handoff reflects the task's own behavior_contract.
if ! grep -qF "behavior_contract" "$case_a_handoff"; then
  fail_case "Case A (applies=true product UI): handoff does not reference the task's own behavior_contract wiring" "$case_a_handoff"
fi
echo "PASS: Case A — applies=true product-UI handoff reflects own behavior_contract, no phantom umbrella-V1"

# ---------------------------------------------------------------------------
# Case B (DP-359 D6 / AC1): framework-infra task with behavior_contract.applies=false
# and NO visual_regression. The framework-infra default is now per-task
# self-contained — the derived handoff must NOT carry the phantom umbrella-V1
# delegation `驗收委派給 {source_id}-V1（umbrella regression）` and must reflect the
# task's own verify_command wiring (no umbrella V delegation).
# RED→GREEN shape: against the UNPATCHED derive script the `else` branch still emits
# the phantom delegation line, so this case FAILS pre-fix, proving the test drives
# the DP-359 supersede.
# ---------------------------------------------------------------------------
case_b_json="$tmpdir/case-b.json"
cat >"$case_b_json" <<'JSON'
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
      "title": "framework deterministic derive 條件化",
      "scope": "純 framework deterministic gate / selftest；無 runtime / UI 行為變更。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh",
        "verify_command": "bash scripts/selftests/sample-selftest.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" },
        "test_environment": { "level": "static" },
        "references": ["scripts/sample.sh"]
      }
    }
  ]
}
JSON

case_b_out="$tmpdir/case-b-task.md"
bash "$SCRIPT" --refinement-json "$case_b_json" --task-id "DP-999-T1" > "$case_b_out"

case_b_handoff="$tmpdir/case-b-handoff.txt"
extract_handoff "$case_b_out" > "$case_b_handoff"

# DP-359 D6: framework-infra default is per-task self-contained — no umbrella V
# delegation. The phantom delegation literal and its '驗收委派給' verb must be ABSENT.
if grep -qF "$PHANTOM_DELEGATION" "$case_b_handoff"; then
  fail_case "Case B (applies=false framework-infra): handoff still emits phantom umbrella-V1 delegation '$PHANTOM_DELEGATION'" "$case_b_handoff"
fi
if grep -qF "驗收委派給" "$case_b_handoff"; then
  fail_case "Case B (applies=false framework-infra): handoff still delegates verification to an umbrella V ('驗收委派給')" "$case_b_handoff"
fi
# Positive: the per-task self-contained framework handoff reflects own wiring.
if ! grep -qF "framework work order" "$case_b_handoff"; then
  fail_case "Case B (applies=false framework-infra): handoff dropped the「framework work order」classifier" "$case_b_handoff"
fi
if ! grep -qF "per-task self-contained" "$case_b_handoff"; then
  fail_case "Case B (applies=false framework-infra): handoff does not state per-task self-contained verification" "$case_b_handoff"
fi
echo "PASS: Case B — applies=false framework-infra handoff is per-task self-contained, no umbrella-V delegation"

# ---------------------------------------------------------------------------
# Case C (AC1, visual_regression authoritative field): a task with
# behavior_contract.applies=false BUT verification.visual_regression declared is a
# product-UI task (its own VR wiring); the handoff must reflect visual_regression
# and must NOT emit the phantom umbrella-V1 text nor the「framework work order」label.
# This exercises the second authoritative field required by AC1.
# ---------------------------------------------------------------------------
case_c_json="$tmpdir/case-c.json"
cat >"$case_c_json" <<'JSON'
{
  "source": {
    "type": "jira",
    "id": "DEMO-4357",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/DEMO-4357",
    "repo": "b2c-web",
    "base_branch": "feat/DEMO-4357",
    "jira_key": "DEMO-4357"
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DEMO-4357-T5",
      "kind": "implementation",
      "jira_key": "DEMO-4366",
      "title": "product UI 視覺回歸守門",
      "scope": "對 product UI 改動加 Layer C visual_regression 守門。",
      "allowed_files": ["apps/main/pages/product/other.vue"],
      "modules": ["apps/main/pages/product/other.vue"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "visual_regression",
        "detail": "bash scripts/run-visual-snapshot.sh --task DEMO-4357-T5",
        "verify_command": "bash scripts/run-visual-snapshot.sh --task DEMO-4357-T5",
        "behavior_contract": { "applies": false, "reason": "視覺以 Layer C visual_regression 守門" },
        "visual_regression": { "pages": ["/product/sample"], "devices": ["desktop"] },
        "test_environment": { "level": "runtime" },
        "references": ["scripts/run-visual-snapshot.sh"]
      }
    }
  ]
}
JSON

case_c_out="$tmpdir/case-c-task.md"
bash "$SCRIPT" --refinement-json "$case_c_json" --task-id "DEMO-4357-T5" > "$case_c_out"

case_c_handoff="$tmpdir/case-c-handoff.txt"
extract_handoff "$case_c_out" > "$case_c_handoff"

if grep -qF "$PHANTOM_DELEGATION" "$case_c_handoff"; then
  fail_case "Case C (visual_regression declared): handoff still emits phantom umbrella-V1 delegation '$PHANTOM_DELEGATION'" "$case_c_handoff"
fi
if grep -qF "$PHANTOM_LABEL" "$case_c_handoff"; then
  fail_case "Case C (visual_regression declared): handoff still emits phantom「$PHANTOM_LABEL」label" "$case_c_handoff"
fi
if ! grep -qF "visual_regression" "$case_c_handoff"; then
  fail_case "Case C (visual_regression declared): handoff does not reference the task's own visual_regression wiring" "$case_c_handoff"
fi
echo "PASS: Case C — visual_regression product-UI handoff reflects own VR wiring, no phantom umbrella-V1"

echo "PASS: derive-task-md-verification-handoff-selftest (all cases)"
