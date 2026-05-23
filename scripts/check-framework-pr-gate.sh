#!/usr/bin/env bash
set -euo pipefail

VALIDATE_RUNTIME="${POLARIS_VALIDATE_RUNTIME_BIN:-scripts/validate-mechanism-runtime-annotations.sh}"
AUDIT_GRADUATION="${POLARIS_AUDIT_GRADUATION_BIN:-scripts/audit-mechanism-graduation.sh}"
LINT_REFERENCE_LINE_COUNT="${POLARIS_LINT_REFERENCE_LINE_COUNT_BIN:-scripts/lint-reference-line-count.sh}"
CHECK_QUARANTINE="${POLARIS_CHECK_QUARANTINE_BIN:-scripts/check-quarantine-duplication.sh}"
VALIDATE_SPEC_SOURCE_PARITY="${POLARIS_VALIDATE_SPEC_SOURCE_PARITY_BIN:-scripts/validate-spec-source-parity.sh}"
GATE_TEMPLATE_LEAKS="${POLARIS_GATE_TEMPLATE_LEAKS_BIN:-scripts/gates/gate-template-leaks.sh}"

run_gate() {
  local label="$1"
  local bin="$2"
  shift 2
  if ! bash "$bin" "$@"; then
    echo "framework-pr-gate failed: $label ($bin)" >&2
    return 1
  fi
}

run_gate "W1 runtime annotations" "$VALIDATE_RUNTIME"
run_gate "W2 graduation audit" "$AUDIT_GRADUATION"
run_gate "W3 reference line-count policy" "$LINT_REFERENCE_LINE_COUNT"
run_gate "W4 quarantine duplication" "$CHECK_QUARANTINE"
run_gate "W5 spec source parity" "$VALIDATE_SPEC_SOURCE_PARITY"
# W6: workspace template leak scan (DP-228 recurrence prevention).
# Catches live company slug / JIRA prefix / Slack ID / internal URL in tracked
# files BEFORE the workspace PR is opened, instead of only at sync-to-polaris
# post-merge.
run_gate "W6 template leaks (workspace)" "$GATE_TEMPLATE_LEAKS"

echo "PASS: framework PR gate"
