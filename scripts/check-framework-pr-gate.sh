#!/usr/bin/env bash
set -euo pipefail

VALIDATE_RUNTIME="${POLARIS_VALIDATE_RUNTIME_BIN:-scripts/validate-mechanism-runtime-annotations.sh}"
AUDIT_GRADUATION="${POLARIS_AUDIT_GRADUATION_BIN:-scripts/audit-mechanism-graduation.sh}"
LINT_REFERENCE_LINE_COUNT="${POLARIS_LINT_REFERENCE_LINE_COUNT_BIN:-scripts/lint-reference-line-count.sh}"
CHECK_QUARANTINE="${POLARIS_CHECK_QUARANTINE_BIN:-scripts/check-quarantine-duplication.sh}"
VALIDATE_SPEC_SOURCE_PARITY="${POLARIS_VALIDATE_SPEC_SOURCE_PARITY_BIN:-scripts/validate-spec-source-parity.sh}"
GATE_TEMPLATE_LEAKS="${POLARIS_GATE_TEMPLATE_LEAKS_BIN:-scripts/gates/gate-template-leaks.sh}"
LINT_BASH_VAR_UTF8_BOUNDARY="${POLARIS_LINT_BASH_VAR_UTF8_BOUNDARY_BIN:-scripts/lint-bash-variable-utf8-boundary.sh}"
VALIDATE_MISE_DEPENDENCY="${POLARIS_VALIDATE_MISE_DEPENDENCY_BIN:-scripts/validate-mise-dependency-change.sh}"
VALIDATE_SCRIPT_HEADER="${POLARIS_VALIDATE_SCRIPT_HEADER_BIN:-scripts/validate-script-header-comment.sh}"
VALIDATE_SCRIPT_CATEGORIZATION="${POLARIS_VALIDATE_SCRIPT_CATEGORIZATION_BIN:-scripts/validate-script-categorization.sh}"

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
# W7: bash $VAR<non-ASCII byte> boundary lint (DP-255).
# Catches `$foo<CJK fullwidth punct>` patterns where bash variable expansion
# under `set -u` parses the multi-byte UTF-8 continuation byte as identifier
# continuation, triggering unbound-variable crashes. Forces brace-delimited
# form `${VAR}<punct>`.
run_gate "W7 bash \$VAR UTF-8 boundary" "$LINT_BASH_VAR_UTF8_BOUNDARY"
# W8: mise.toml dependency change gate (DP-240 T9 / AC11).
# Skips silently when mise.toml is unchanged; fails closed when changed
# without an owning DP-NNN reference in the PR body. PR-time invocation
# (where PR body is known) lives in framework-release-pr-lane.sh; locally
# we only assert the validator exists and is syntactically valid.
if [[ -n "${POLARIS_FRAMEWORK_PR_BODY:-}" ]]; then
  run_gate "W8 mise dependency change" "$VALIDATE_MISE_DEPENDENCY" \
    --diff "${POLARIS_FRAMEWORK_PR_BASE:-HEAD}" \
    --pr-body "$POLARIS_FRAMEWORK_PR_BODY"
else
  bash -n "$VALIDATE_MISE_DEPENDENCY" || {
    echo "framework-pr-gate failed: W8 mise dependency change validator syntax" >&2
    exit 1
  }
fi
# W9/W10: DP-240 T5 / AC8: same script-audit aggregate as `mise run script-audit`
# and `framework-release-pr-lane.sh`. diff mode against HEAD.
if [[ -f "$VALIDATE_SCRIPT_HEADER" ]]; then
  run_gate "W9 script header comment" "$VALIDATE_SCRIPT_HEADER" --mode diff --base HEAD
fi
if [[ -f "$VALIDATE_SCRIPT_CATEGORIZATION" ]]; then
  run_gate "W10 script categorization" "$VALIDATE_SCRIPT_CATEGORIZATION" --mode diff --base HEAD
fi

echo "PASS: framework PR gate"
