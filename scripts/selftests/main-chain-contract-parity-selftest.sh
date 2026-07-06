#!/usr/bin/env bash
# Purpose: DP-406 cross-skill parity guard for refinement -> auto-pass ->
#          framework-release main-chain contract closure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKEN="POLARIS_MAIN_CHAIN_CONTRACT_PARITY_MISSING"
missing=()

require_file() {
  local path="$1"
  [[ -f "$ROOT/$path" ]] || missing+=("file_missing:$path")
}

require_contains() {
  local path="$1" pattern="$2" label="$3"
  if [[ ! -f "$ROOT/$path" ]]; then
    missing+=("file_missing:$path")
    return
  fi
  grep -Eq "$pattern" "$ROOT/$path" || missing+=("${label}:$path")
}

require_not_contains() {
  local path="$1" pattern="$2" label="$3"
  if [[ ! -f "$ROOT/$path" ]]; then
    missing+=("file_missing:$path")
    return
  fi
  if grep -Eq "$pattern" "$ROOT/$path"; then
    missing+=("${label}:$path")
  fi
}

require_file "scripts/selftests/auto-pass-terminal-lifecycle-selftest.sh"
require_file "scripts/selftests/framework-release-execute-head-invariant-selftest.sh"

# auto-pass report terminal enum is the user-facing terminal contract. The legacy
# refinement/session values may appear only as ledger pause.kind prose, never in
# the report terminal set.
require_contains "scripts/validate-auto-pass-report.sh" '"paused_for_user_external_write"' \
  "report_terminal_missing_user_external_write"
require_contains "scripts/validate-auto-pass-report.sh" '"user_aborted"' \
  "report_terminal_missing_user_aborted"
require_not_contains "scripts/validate-auto-pass-report.sh" '"paused_for_refinement"' \
  "report_terminal_allows_paused_for_refinement"
require_not_contains "scripts/validate-auto-pass-report.sh" '"paused_for_session_handoff"' \
  "report_terminal_allows_paused_for_session_handoff"

# auto-pass ledger keeps refinement/session handoff as non-terminal pause.kind.
require_contains "scripts/validate-auto-pass-ledger.sh" 'LEGACY_TERMINAL_PAUSED_FOR_REFINEMENT = "paused_for_refinement"' \
  "ledger_missing_legacy_refinement_terminal_rejection"
require_contains "scripts/validate-auto-pass-ledger.sh" 'kind not in \("paused_for_refinement", "paused_for_user_external_write", "session_handoff"\)' \
  "ledger_pause_kind_enum_drift"
require_contains "scripts/validate-auto-pass-ledger.sh" 'session_handoff pause is non-terminal' \
  "ledger_session_handoff_not_non_terminal"

# Skill/reference prose must match validator behavior.
require_contains ".claude/skills/auto-pass/SKILL.md" '^## Legal Terminal' \
  "auto_pass_skill_missing_legal_terminal_section"
require_contains ".claude/skills/auto-pass/SKILL.md" 'session_handoff.*paused_for_refinement.*ledger `pause.kind`.*non-terminal' \
  "auto_pass_skill_missing_non_terminal_pause_boundary"
require_not_contains ".claude/skills/auto-pass/SKILL.md" '^- `paused_for_session_handoff`' \
  "auto_pass_skill_lists_session_handoff_terminal"
require_contains ".claude/skills/references/auto-pass-report.md" '`paused_for_refinement` 與 `session_handoff` 只存在於 ledger `pause.kind`' \
  "auto_pass_report_ref_missing_pause_boundary"
require_contains ".claude/skills/references/auto-pass-execution-flow.md" '`paused_for_refinement`（non-terminal `pause.kind`）' \
  "auto_pass_flow_missing_refinement_pause_boundary"
require_contains ".claude/skills/references/auto-pass-execution-flow.md" 'session_handoff` pause 的唯一 sanctioned writer' \
  "auto_pass_flow_missing_session_handoff_writer_boundary"
require_not_contains ".claude/skills/references/auto-pass-execution-flow.md" 'paused_for_session_handoff' \
  "auto_pass_flow_lists_legacy_session_terminal"

# Completion ordering and framework-release head invariant must be wired into
# deterministic scripts, not only described in markdown.
require_contains "scripts/auto-pass-runner.sh" 'Before the runner declares terminal_status=complete' \
  "auto_pass_runner_missing_terminal_v_ordering_comment"
require_contains "scripts/framework-release-execute.sh" 'POLARIS_FRAMEWORK_RELEASE_EXECUTE_HEAD_INVARIANT' \
  "framework_release_execute_missing_head_invariant_marker"
require_contains "scripts/framework-release-execute.sh" 'assert_post_cascade_release_head_invariant' \
  "framework_release_execute_missing_head_invariant_function"
require_contains ".claude/skills/framework-release/SKILL.md" 'feat/DP-NNN` HEAD 壓版本' \
  "framework_release_skill_missing_feat_head_boundary"

# The roadmap insertion is part of the source-level dispatch contract for this
# DP; keep the Bucket 2.7 placement and the explicit no-redo boundary visible.
require_contains ".polaris/dp-drain-roadmap.md" '^## Bucket 2\.7' \
  "roadmap_missing_bucket_2_7"
require_contains ".polaris/dp-drain-roadmap.md" 'DP-406' \
  "roadmap_missing_dp_406"
require_contains ".polaris/dp-drain-roadmap.md" '不重做 DP-373 / DP-404 / DP-405 已 release scope' \
  "roadmap_missing_no_redo_boundary"

if (( ${#missing[@]} > 0 )); then
  printf '%s: %s\n' "$TOKEN" "${missing[*]}" >&2
  exit 1
fi

echo "PASS: main-chain contract parity selftest"
