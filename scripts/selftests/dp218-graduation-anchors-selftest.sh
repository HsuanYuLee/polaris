#!/usr/bin/env bash
# dp218-graduation-anchors-selftest.sh — DP-218 memory→framework graduation gate.
#
# Verifies the 18 prose feedback memories absorbed into framework canonical
# surface (rules / skills / references) each have a unique grep-anchor string
# in the target file. AC1 / AC-NEG1 evidence.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail=0
check() {
  local label="$1"
  local target="$2"
  local anchor="$3"
  if [[ ! -f "$ROOT_DIR/$target" ]]; then
    echo "FAIL ($label): target missing: $target" >&2
    fail=1
    return
  fi
  if ! grep -F -q "$anchor" "$ROOT_DIR/$target"; then
    echo "FAIL ($label): anchor not found in $target" >&2
    echo "  expected: $anchor" >&2
    fail=1
  fi
}

# 1. feedback_no_checkpoint_as_work_order → rules/skill-routing.md
check no_checkpoint_as_work_order \
  ".claude/rules/skill-routing.md" \
  "## Checkpoint vs Work Order"

# 2. feedback_framework_release_is_self_iteration → rules/framework-iteration.md
check framework_release_is_self_iteration \
  ".claude/rules/framework-iteration.md" \
  "## Self-Iteration Release Boundary"

# 3. feedback_auto_pass_must_not_stop_on_recoverable_halt → skills/auto-pass/SKILL.md
check auto_pass_must_not_stop_on_recoverable_halt \
  ".claude/skills/auto-pass/SKILL.md" \
  "Recoverable HALT 必須繼續 dispatch"

# 4. feedback_refinement_no_unsolicited_lock_prompt → skills/refinement/SKILL.md
check refinement_no_unsolicited_lock_prompt \
  ".claude/skills/refinement/SKILL.md" \
  "## Unsolicited LOCK Prompt Forbidden"

# 5. feedback_pr_resolver_branch_fallback → skills/references/engineer-delivery-flow.md
check pr_resolver_branch_fallback \
  ".claude/skills/references/engineer-delivery-flow.md" \
  "## Revision Mode — Explicit --pr"

# 6. feedback_portable_gate_paths → skills/references/engineer-delivery-flow.md
check portable_gate_paths \
  ".claude/skills/references/engineer-delivery-flow.md" \
  "## Gate Invocation — Portable Paths"

# 7. feedback_aggregate_gate_file_lists → rules/bash-command-splitting.md
check aggregate_gate_file_lists \
  ".claude/rules/bash-command-splitting.md" \
  "## Aggregate File Lists Need xargs"

# 8. feedback_polaris_scripts_require_workspace_root → rules/bash-command-splitting.md
check polaris_scripts_require_workspace_root \
  ".claude/rules/bash-command-splitting.md" \
  "## Helper Script Invocation — Workspace Root"

# 9. feedback_template_examples_must_be_generic → rules/framework-iteration.md
check template_examples_must_be_generic \
  ".claude/rules/framework-iteration.md" \
  "## Template-Facing Examples Must Be Generic"

# 10. feedback_refinement_contract_requires_dp_artifact → skills/refinement/SKILL.md
check refinement_contract_requires_dp_artifact \
  ".claude/skills/refinement/SKILL.md" \
  "## Framework Contract Change Guard"

# 11. feedback_gate_preflight_fail_stop → rules/bash-command-splitting.md
check gate_preflight_fail_stop \
  ".claude/rules/bash-command-splitting.md" \
  "## Gate Preflight Fail-Stop"

# 12. feedback_skill_reference_relative_paths → skills/references/INDEX.md
check skill_reference_relative_paths \
  ".claude/skills/references/INDEX.md" \
  "## Path Resolution — Skill-Relative"

# 13. feedback_dp_completion_audit_must_verify_merged_pr → rules/sub-agent-delegation.md
check dp_completion_audit_must_verify_merged_pr \
  ".claude/rules/sub-agent-delegation.md" \
  "DP completion audit must verify merged PR diff"

# 14. feedback_learning_seed_contract_gap → skills/learning/SKILL.md
check learning_seed_contract_gap \
  ".claude/skills/learning/SKILL.md" \
  "### External Seed Contract — DP Container Authority"

# 15. feedback_refinement_no_overspilt_contract_tasks → skills/breakdown/SKILL.md
check refinement_no_overspilt_contract_tasks \
  ".claude/skills/breakdown/SKILL.md" \
  "## Task Splitting Heuristic — Reviewable PR Boundary"

# 16. feedback_apply_standards_not_ask_user → rules/handbook/working-habits.md
check apply_standards_not_ask_user \
  ".claude/rules/handbook/working-habits.md" \
  "Apply 標準提一個方案，不要列 equivalent 選項給使用者選"

# 17. feedback_kb2cw_close_via_pending → rules/kkday/jira-conventions.md
check kb2cw_close_via_pending \
  ".claude/rules/kkday/jira-conventions.md" \
  "KB2CW 子單「不做了就關掉」走 Pending → 不處理 → 已關閉"

# 18. feedback_small_framework_gap_fix_now → rules/skill-routing.md
check small_framework_gap_fix_now \
  ".claude/rules/skill-routing.md" \
  "## Framework Gap Immediate Routing"

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: dp218-graduation-anchors-selftest (one or more anchors missing)" >&2
  exit 1
fi

echo "PASS: dp218-graduation-anchors-selftest (18/18 anchors found)"
