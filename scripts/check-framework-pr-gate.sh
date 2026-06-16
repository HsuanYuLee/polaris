#!/usr/bin/env bash
# Purpose: aggregate blocking framework PR gate — runs each validator (W1..W11) and
#          fails closed if any one fails. W11 (DP-293 T1) is the runtime-instruction
#          parity step: compile-runtime-instructions --check + mechanism-parity --strict.
# Inputs:  env BIN overrides (POLARIS_*_BIN) for each gate; POLARIS_FRAMEWORK_PR_BODY/BASE.
# Outputs: stdout "PASS: framework PR gate"; non-zero exit + "framework-pr-gate failed: …".
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
# W12 (DP-296 T4 / AC3): refinement.json consumer schema binding. Binds every
# declared tasks[] consumer to the canonical schema field whitelist (the field set
# validated by validate-refinement-json.sh) and fails closed on out-of-schema reads
# or unregistered consumers.
VALIDATE_CONSUMER_SCHEMA_BINDING="${POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN:-scripts/validate-refinement-consumer-schema-binding.sh}"
# W13/W14 (DP-325 T2 / AC1+AC2+AC3): aggregate selftest enrollment + execution.
# W13 fail-closes when a filesystem selftest is not enrolled in the aggregate
# runner; W14 runs the full selftest corpus (any red => non-zero). Together they
# stop the framework PR gate from only exercising the 38 governed selftests.
VALIDATE_SELFTEST_ENROLLMENT="${POLARIS_VALIDATE_SELFTEST_ENROLLMENT_BIN:-scripts/validate-selftest-enrollment.sh}"
RUN_AGGREGATE_SELFTESTS="${POLARIS_RUN_AGGREGATE_SELFTESTS_BIN:-scripts/run-aggregate-selftests.sh}"
# W11 (DP-293 T1): runtime-instruction parity. compile --check catches drifted
# generated targets (CLAUDE.md / AGENTS.md / .codex / copilot) before merge;
# mechanism-parity --strict catches cross-runtime skill/mechanism divergence.
COMPILE_RUNTIME_INSTRUCTIONS="${POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN:-scripts/compile-runtime-instructions.sh}"
MECHANISM_PARITY="${POLARIS_MECHANISM_PARITY_BIN:-scripts/mechanism-parity.sh}"

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
# W11: runtime-instruction parity (DP-293 T1 / AC1). Blocking — a drifted generated
# target or cross-runtime divergence must fail the PR gate, not slip to post-merge.
run_gate "W11 runtime-instruction parity (compile --check)" "$COMPILE_RUNTIME_INSTRUCTIONS" --check
run_gate "W11 runtime-instruction parity (mechanism-parity --strict)" "$MECHANISM_PARITY" --strict
# W12: refinement.json consumer schema binding (DP-296 T4 / AC3). Blocking — a
# declared consumer reading an out-of-schema tasks[] field, or a new unregistered
# tasks[] consumer, must fail the PR gate before merge.
run_gate "W12 refinement consumer schema binding" "$VALIDATE_CONSUMER_SCHEMA_BINDING"
# W13: selftest enrollment gate (DP-325 T2 / AC2). Fail-closed when any filesystem
# selftest is not enrolled in the aggregate runner.
run_gate "W13 selftest enrollment" "$VALIDATE_SELFTEST_ENROLLMENT"
# W14: aggregate selftest execution (DP-325 T2 / AC1+AC3). Runs the full
# filesystem selftest corpus; any non-quarantined red fails the PR gate.
run_gate "W14 aggregate selftest run" "$RUN_AGGREGATE_SELFTESTS"

echo "PASS: framework PR gate"
