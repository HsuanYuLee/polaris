#!/usr/bin/env bash
# Purpose: aggregate blocking framework PR gate — runs each validator (W1..W16) and
#          fails closed if any one fails. W11 (DP-293 T1) is the runtime-instruction
#          parity step: compile-runtime-instructions --check + mechanism-parity --strict.
#          W14 runs the full selftest corpus (run-aggregate-selftests.sh) — this makes
#          THIS script the canonical full-corpus backstop entrypoint (DP-360 T-backstop):
#          it is wired into both the release lane (framework-release-pr-lane.sh, PR tail)
#          and is the local DP-iteration entrypoint (run it directly to exercise the
#          full corpus before pushing a DP). The full corpus is hour-scale (319
#          selftests), so per AC-NF1 it MUST NOT be wired onto the commit/push hot path
#          (pre-commit fast-lint + pre-push affected-scoped only); the three-layer split
#          keeps the full corpus on the DP-iteration/release backstop lanes exclusively.
# Inputs:  env BIN overrides (POLARIS_*_BIN) for each gate; POLARIS_FRAMEWORK_PR_BODY/BASE.
#          --list-stages   introspection: print one "Wn <label>" line per aggregate stage
#                          (including the W14 full-corpus backstop) and exit 0, without
#                          running any gate. Lets the backstop-wiring selftest assert the
#                          full corpus is part of this backstop deterministically.
# Outputs: stdout "PASS: framework PR gate"; non-zero exit + "framework-pr-gate failed: …".
set -euo pipefail

list_stage_owners() {
  cat <<'OWNERS'
stage	label	owner	route_back	release_tail_only_reason
W1	runtime annotations	upstream:mechanism-governance	mechanism-registry	N/A
W2	graduation audit	upstream:mechanism-governance	mechanism-registry	N/A
W3	reference line-count policy	upstream:docs-governance	docs-health	N/A
W4	quarantine duplication	upstream:framework-pr-gate	engineering	N/A
W5	spec source parity	upstream:refinement-breakdown	refinement	N/A
W6	template leaks (workspace)	upstream:workspace-template-gate	engineering	N/A
W7	bash $VAR UTF-8 boundary	upstream:script-authoring	engineering	N/A
W8	mise dependency change	upstream:dependency-governance	engineering	N/A
W9	script header comment	upstream:script-authoring	engineering	N/A
W10	script categorization	upstream:script-governance	engineering	N/A
W11	runtime-instruction parity	upstream:runtime-instruction-governance	engineering	N/A
W12	refinement consumer schema binding	upstream:refinement-breakdown	breakdown	N/A
W13	selftest enrollment	upstream:selftest-governance	engineering	N/A
W14	aggregate selftest run (full-corpus backstop)	upstream:selftest-governance	engineering	N/A
W15	naive section-parse lint	upstream:markdown-parser-governance	engineering	N/A
W16	cross-LLM mechanism parity	upstream:mechanism-governance	engineering	N/A
W17	framework source write authority	upstream:framework-source-governance	engineering	N/A
W18	config-driven authoring audit	upstream:language-governance	engineering	N/A
OWNERS
}

# --list-stages / --list-stage-owners: deterministic introspection of the aggregate
# stage list. Emitting this does NOT run any gate (so it is safe on the hot path /
# in selftests) — it only declares which stages this DP-iteration/release backstop
# entrypoint covers, including the W14 full-corpus run. Keep both lists in sync
# with the run_gate calls below.
if [[ "${1:-}" == "--list-stage-owners" ]]; then
  list_stage_owners
  exit 0
fi

if [[ "${1:-}" == "--list-stages" ]]; then
  cat <<'STAGES'
W1 runtime annotations
W2 graduation audit
W3 reference line-count policy
W4 quarantine duplication
W5 spec source parity
W6 template leaks (workspace)
W7 bash $VAR UTF-8 boundary
W8 mise dependency change
W9 script header comment
W10 script categorization
W11 runtime-instruction parity
W12 refinement consumer schema binding
W13 selftest enrollment
W14 aggregate selftest run (full-corpus backstop)
W15 naive section-parse lint
W16 cross-LLM mechanism parity
W17 framework source write authority
W18 config-driven authoring audit
STAGES
  exit 0
fi

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
# W15 (DP-345 T2 / AC5): naive markdown section-parse lint. Fail-closed when a new
# blob-level `.find`/`.index`/`.split` for a `## heading` over un-frontmatter-stripped
# text reappears (the DP-344-T1 collision shape DP-345 T1 converged). `--self-check`
# scans the converged scripts/** + .claude/** source tree.
LINT_NAIVE_SECTION_PARSE="${POLARIS_LINT_NAIVE_SECTION_PARSE_BIN:-scripts/lint-naive-section-parse.sh}"
# W11 (DP-293 T1): runtime-instruction parity. compile --check catches drifted
# generated targets (CLAUDE.md / AGENTS.md / .codex / copilot) before merge;
# mechanism-parity --strict catches cross-runtime skill/mechanism divergence.
COMPILE_RUNTIME_INSTRUCTIONS="${POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN:-scripts/compile-runtime-instructions.sh}"
MECHANISM_PARITY="${POLARIS_MECHANISM_PARITY_BIN:-scripts/mechanism-parity.sh}"
# W16 (DP-343 T1 / AC43): Claude/Codex dual-platform mechanism parity. Blocking —
# an active hook lacking a Codex-equivalent enforcement path (fallback callsite,
# adapter target/registration, golden digest parity) or a recorded parity_exception
# must fail the PR gate before merge, not only at release preflight.
VALIDATE_CROSS_LLM_PARITY="${POLARIS_VALIDATE_CROSS_LLM_PARITY_BIN:-scripts/validate-cross-llm-mechanism-parity.sh}"
# W17 (DP-231 T11 / D41): framework source write authority. This PR-time lane
# asserts that Claude hooks, Codex adapters, guarded bash, and registry rows all
# delegate to the single validator.
VALIDATE_FRAMEWORK_SOURCE_WRITE="${POLARIS_VALIDATE_FRAMEWORK_SOURCE_WRITE_BIN:-scripts/validate-framework-source-write.sh}"
VALIDATE_CONFIG_DRIVEN_AUTHORING="${POLARIS_VALIDATE_CONFIG_DRIVEN_AUTHORING_BIN:-scripts/validate-config-driven-authoring.sh}"

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
# W15: naive section-parse lint (DP-345 T2 / AC5). Fail-closed when a naive
# blob-level `## heading` find/index/split over un-frontmatter-stripped markdown
# reappears in the converged source tree.
run_gate "W15 naive section-parse lint" "$LINT_NAIVE_SECTION_PARSE" --self-check
# W16: cross-LLM mechanism parity (DP-343 T1 / AC43). Blocking — an active hook
# lacking a Codex-equivalent enforcement path or a recorded parity_exception must
# fail before merge.
run_gate "W16 cross-LLM mechanism parity" "$VALIDATE_CROSS_LLM_PARITY"
run_gate "W17 framework source write authority" "$VALIDATE_FRAMEWORK_SOURCE_WRITE" --repo "$(pwd)" --self-check-wiring
run_gate "W18 config-driven authoring audit" "$VALIDATE_CONFIG_DRIVEN_AUTHORING" --root "$(pwd)"

echo "PASS: framework PR gate"
