#!/usr/bin/env bash
# Purpose: check-framework-pr-gate.sh wiring selftest — asserts W12 parity and the
#   DP-422 T8 W19 transition source-closeout gate are blocking aggregate members.
#   The aggregate is composed of many cwd/content-sensitive gates, so this selftest
#   does NOT run the whole aggregate end-to-end; instead it verifies the W12 wiring
#   deterministically:
#     1. the aggregate source references the W12 gate binary + run_gate label
#     2. the W12 gate is overridable via POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN
#     3. when the W12 gate stub FAILS, the aggregate fails closed at W12 (all other
#        gates stubbed PASS) → proves W12 is a blocking member, not advisory
#     4. when every gate stub PASSes, the aggregate prints the terminal PASS line
# Inputs:  none (stubs each gate binary via POLARIS_*_BIN env in a tmpdir).
# Outputs: PASS/FAIL lines per case; exit 0 if all pass, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGG="$ROOT/scripts/check-framework-pr-gate.sh"

if [[ ! -f "$AGG" ]]; then
  echo "FAIL: aggregate missing: $AGG" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_grep() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (missing '$needle')" >&2
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Case 1: aggregate source references the W12 gate binary default + label.
# ---------------------------------------------------------------------------
assert_grep "case1 W12 binary default present" \
  "scripts/validate-refinement-consumer-schema-binding.sh" "$AGG"
assert_grep "case1 W12 run_gate label present" \
  "W12 refinement consumer schema binding" "$AGG"
assert_grep "case1 W12 override env present" \
  "POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN" "$AGG"
assert_grep "case1 parity binary default present" \
  "scripts/validate-spec-check-contract-parity.sh" "$AGG"
assert_grep "case1 parity run_gate label present" \
  "W12 producer-consumer-validator parity" "$AGG"
assert_grep "case1 parity override env present" \
  "POLARIS_VALIDATE_SPEC_CHECK_CONTRACT_PARITY_BIN" "$AGG"
assert_grep "case1 W19 binary default present" \
  "scripts/validate-skill-flow-transition-registry.sh" "$AGG"
assert_grep "case1 W19 run_gate label present" \
  "W19 DP-422 transition source closeout" "$AGG"
assert_grep "case1 W19 override env present" \
  "POLARIS_VALIDATE_SKILL_FLOW_TRANSITION_REGISTRY_BIN" "$AGG"

# ---------------------------------------------------------------------------
# Build PASS / FAIL gate stubs.
# ---------------------------------------------------------------------------
pass_stub="$tmpdir/pass-stub.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$pass_stub"
chmod +x "$pass_stub"

fail_stub="$tmpdir/fail-stub.sh"
printf '#!/usr/bin/env bash\necho "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:stub failure" >&2\nexit 2\n' >"$fail_stub"
chmod +x "$fail_stub"

# All non-W12 gate overrides point at the PASS stub so the aggregate reaches W12
# regardless of the live workspace state. W12 itself is varied per case.
common_env=(
  "POLARIS_VALIDATE_RUNTIME_BIN=$pass_stub"
  "POLARIS_AUDIT_GRADUATION_BIN=$pass_stub"
  "POLARIS_LINT_REFERENCE_LINE_COUNT_BIN=$pass_stub"
  "POLARIS_CHECK_QUARANTINE_BIN=$pass_stub"
  "POLARIS_VALIDATE_SPEC_SOURCE_PARITY_BIN=$pass_stub"
  "POLARIS_GATE_TEMPLATE_LEAKS_BIN=$pass_stub"
  "POLARIS_LINT_BASH_VAR_UTF8_BOUNDARY_BIN=$pass_stub"
  "POLARIS_VALIDATE_MISE_DEPENDENCY_BIN=$pass_stub"
  "POLARIS_VALIDATE_SCRIPT_HEADER_BIN=$pass_stub"
  "POLARIS_VALIDATE_SCRIPT_CATEGORIZATION_BIN=$pass_stub"
  "POLARIS_VALIDATE_SPEC_CHECK_CONTRACT_PARITY_BIN=$pass_stub"
  "POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN=$pass_stub"
  "POLARIS_MECHANISM_PARITY_BIN=$pass_stub"
  # W13/W14 must point at the PASS stub: the real binaries are
  # scripts/validate-selftest-enrollment.sh and scripts/run-aggregate-selftests.sh,
  # and the latter executes the ENTIRE selftest corpus — including this very
  # selftest, which re-enters check-framework-pr-gate.sh. Leaving them unstubbed
  # causes unbounded recursion (~hours of wall-clock). Stubbing keeps cases 2/3
  # asserting wiring (W12 fail/pass behaviour) without spawning the full corpus.
  "POLARIS_VALIDATE_SELFTEST_ENROLLMENT_BIN=$pass_stub"
  "POLARIS_RUN_AGGREGATE_SELFTESTS_BIN=$pass_stub"
  "POLARIS_LINT_NAIVE_SECTION_PARSE_BIN=$pass_stub"
  "POLARIS_VALIDATE_CROSS_LLM_PARITY_BIN=$pass_stub"
  "POLARIS_VALIDATE_FRAMEWORK_SOURCE_WRITE_BIN=$pass_stub"
  "POLARIS_VALIDATE_CONFIG_DRIVEN_AUTHORING_BIN=$pass_stub"
  "POLARIS_VALIDATE_SKILL_FLOW_TRANSITION_REGISTRY_BIN=$pass_stub"
)

# ---------------------------------------------------------------------------
# Case 2: W12 gate FAILS → aggregate fails closed at W12.
# ---------------------------------------------------------------------------
set +e
env "${common_env[@]}" "POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN=$fail_stub" \
  bash "$AGG" >"$tmpdir/case2.out" 2>"$tmpdir/case2.err"; rc2=$?
set -e
assert_exit "case2 W12 failure blocks aggregate" 1 "$rc2"
assert_grep "case2 aggregate names W12" "W12 refinement consumer schema binding" "$tmpdir/case2.err"

# ---------------------------------------------------------------------------
# Case 3: producer-consumer-validator parity FAILS → aggregate fails closed.
# ---------------------------------------------------------------------------
set +e
env "${common_env[@]}" \
  "POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN=$pass_stub" \
  "POLARIS_VALIDATE_SPEC_CHECK_CONTRACT_PARITY_BIN=$fail_stub" \
  bash "$AGG" >"$tmpdir/case3.out" 2>"$tmpdir/case3.err"; rc3=$?
set -e
assert_exit "case3 parity failure blocks aggregate" 1 "$rc3"
assert_grep "case3 aggregate names parity stage" "W12 producer-consumer-validator parity" "$tmpdir/case3.err"

# ---------------------------------------------------------------------------
# Case 4: W19 source closeout FAILS → aggregate fails closed after current
# reproducer stages.
# ---------------------------------------------------------------------------
set +e
env "${common_env[@]}" \
  "POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN=$pass_stub" \
  "POLARIS_VALIDATE_SKILL_FLOW_TRANSITION_REGISTRY_BIN=$fail_stub" \
  bash "$AGG" >"$tmpdir/case4.out" 2>"$tmpdir/case4.err"; rc4=$?
set -e
assert_exit "case4 W19 failure blocks aggregate" 1 "$rc4"
assert_grep "case4 aggregate names W19" "W19 DP-422 transition source closeout" "$tmpdir/case4.err"

# ---------------------------------------------------------------------------
# Case 5: every gate (including W12 and W19) PASSes → terminal PASS.
# ---------------------------------------------------------------------------
set +e
env "${common_env[@]}" "POLARIS_VALIDATE_CONSUMER_SCHEMA_BINDING_BIN=$pass_stub" \
  bash "$AGG" >"$tmpdir/case5.out" 2>"$tmpdir/case5.err"; rc5=$?
set -e
assert_exit "case5 all-pass aggregate" 0 "$rc5"
assert_grep "case5 terminal PASS line" "PASS: framework PR gate" "$tmpdir/case5.out"

# ---------------------------------------------------------------------------
echo "----------------------------------------"
echo "selftest summary: pass=$pass fail=$fail"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: check-framework-pr-gate selftest"
