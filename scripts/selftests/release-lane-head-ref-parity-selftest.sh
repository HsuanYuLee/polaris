#!/usr/bin/env bash
# release-lane-head-ref-parity-selftest.sh — DP-293 T1 / AC1, AC2, AC-NEG1.
#
# Purpose: prove the release-lane governed-test head-ref correctness fix and the
#   check-framework-pr-gate.sh runtime-instruction parity step.
# Inputs:  none (hermetic; resolves repo root via git toplevel / BASH_SOURCE,
#          builds throwaway fixture repos + stub validators in a tmp WORKDIR).
# Outputs: prints PASS on success; diagnostic + non-zero exit on any failure.
# Exit code: 0 PASS, 1 contract failure.
#
# Cases:
#   AC2/AC-NEG1  run-governed-script-tests.sh --head-ref checks out the PR head into
#               an isolated worktree and exports POLARIS_GOVERNED_TEST_ROOT, so a
#               compile/parity --check-class probe validates the HEAD tree. main drift
#               + head clean -> governed test (== lane preflight) PASS.
#   AC2 (neg)   main drift + head ALSO drifted -> governed test FAIL (the probe sees
#               the head tree's drift, proving it is not reading the main checkout).
#   AC1 (a)     check-framework-pr-gate.sh invokes the W11 parity step; a failing
#               compile --check stub -> gate exits non-zero.
#   AC1 (b)     a failing mechanism-parity --strict stub -> gate exits non-zero.
#   AC1 (c)     both parity stubs pass (with all prior gates stubbed pass) -> gate PASS.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
RUNNER="$ROOT_DIR/scripts/run-governed-script-tests.sh"
GATE="$ROOT_DIR/scripts/check-framework-pr-gate.sh"
WORKDIR="$(mktemp -d -t dp293-relane.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

for f in "$RUNNER" "$GATE"; do
  [[ -f "$f" ]] || { echo "FAIL: missing script under test: $f" >&2; exit 1; }
done

# --- AC2 / AC-NEG1: head-ref isolated worktree + POLARIS_GOVERNED_TEST_ROOT --------
#
# Fixture repo: a release-profile governed test whose probe asserts sentinel.txt ==
# CLEAN inside $POLARIS_GOVERNED_TEST_ROOT. The main checkout is always DRIFT; the
# head branch carries the chosen sentinel. If the runner did NOT check out the head
# tree and export POLARIS_GOVERNED_TEST_ROOT, the probe would fall back to "." (main,
# DRIFT) and the clean-head case would wrongly FAIL — so a passing clean-head case
# proves the fix.
make_fixture() {
  local fx="$1" head_sentinel="$2"
  mkdir -p "$fx/scripts"
  git -C "$fx" init -q
  git -C "$fx" config user.email t@example.com
  git -C "$fx" config user.name tester
  git -C "$fx" config commit.gpgsign false
  cat >"$fx/scripts/manifest.json" <<'JSON'
{"governed_tests":[{"id":"sentinel-probe","enrolled":true,"profiles":["release"],"changed_paths":[],"command":"bash scripts/probe-sentinel.sh"}]}
JSON
  cat >"$fx/scripts/probe-sentinel.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="${POLARIS_GOVERNED_TEST_ROOT:-.}"
[[ "$(cat "$root/sentinel.txt")" == "CLEAN" ]] || { echo "drift detected in head tree" >&2; exit 1; }
SH
  chmod +x "$fx/scripts/probe-sentinel.sh"
  echo "MAIN_DRIFT" >"$fx/sentinel.txt"
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "base (main drift)"
  BASE_BRANCH="$(git -C "$fx" symbolic-ref --short HEAD)"
  git -C "$fx" checkout -q -b head-ref
  echo "$head_sentinel" >"$fx/sentinel.txt"
  git -C "$fx" commit -q -am "head ($head_sentinel)"
  git -C "$fx" checkout -q "$BASE_BRANCH"
}

run_governed() {
  local fx="$1"
  set +e
  env -u POLARIS_GOVERNED_TEST_ROOT bash "$RUNNER" \
    --root "$fx" --profile release --base "$BASE_BRANCH" --head-ref head-ref \
    >"$WORKDIR/governed.out" 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

fx_clean="$WORKDIR/fx-clean"
make_fixture "$fx_clean" "CLEAN"
rc_clean="$(run_governed "$fx_clean")"
if [[ "$rc_clean" -ne 0 ]]; then
  echo "FAIL (AC2/AC-NEG1): main drift + head clean expected governed test PASS, got rc=$rc_clean" >&2
  cat "$WORKDIR/governed.out" >&2
  exit 1
fi

fx_drift="$WORKDIR/fx-drift"
make_fixture "$fx_drift" "DRIFT"
rc_drift="$(run_governed "$fx_drift")"
if [[ "$rc_drift" -eq 0 ]]; then
  echo "FAIL (AC2): head drift expected governed test FAIL, got rc=0" >&2
  cat "$WORKDIR/governed.out" >&2
  exit 1
fi
grep -q 'drift detected in head tree' "$WORKDIR/governed.out" || {
  echo "FAIL (AC2): head-drift failure did not originate from the head tree probe" >&2
  cat "$WORKDIR/governed.out" >&2
  exit 1
}

# --- AC1: check-framework-pr-gate.sh W11 runtime-instruction parity step -----------
cat >"$WORKDIR/pass.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$WORKDIR/fail.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$WORKDIR/pass.sh" "$WORKDIR/fail.sh"

run_pr_gate() {
  local compile_bin="$1" parity_bin="$2"
  set +e
  env -u POLARIS_FRAMEWORK_PR_BODY -u POLARIS_GOVERNED_TEST_ROOT \
    POLARIS_VALIDATE_RUNTIME_BIN="$WORKDIR/pass.sh" \
    POLARIS_AUDIT_GRADUATION_BIN="$WORKDIR/pass.sh" \
    POLARIS_LINT_REFERENCE_LINE_COUNT_BIN="$WORKDIR/pass.sh" \
    POLARIS_CHECK_QUARANTINE_BIN="$WORKDIR/pass.sh" \
    POLARIS_VALIDATE_SPEC_SOURCE_PARITY_BIN="$WORKDIR/pass.sh" \
    POLARIS_GATE_TEMPLATE_LEAKS_BIN="$WORKDIR/pass.sh" \
    POLARIS_LINT_BASH_VAR_UTF8_BOUNDARY_BIN="$WORKDIR/pass.sh" \
    POLARIS_VALIDATE_MISE_DEPENDENCY_BIN="$WORKDIR/pass.sh" \
    POLARIS_VALIDATE_SCRIPT_HEADER_BIN="$WORKDIR/pass.sh" \
    POLARIS_VALIDATE_SCRIPT_CATEGORIZATION_BIN="$WORKDIR/pass.sh" \
    POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN="$compile_bin" \
    POLARIS_MECHANISM_PARITY_BIN="$parity_bin" \
    bash "$GATE" >"$WORKDIR/gate.out" 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# AC1 (a): failing compile --check stub -> gate non-zero, blamed on the W11 step.
rc="$(run_pr_gate "$WORKDIR/fail.sh" "$WORKDIR/pass.sh")"
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL (AC1a): failing compile --check parity step did not fail the gate" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
fi
grep -q 'W11 runtime-instruction parity (compile --check)' "$WORKDIR/gate.out" || {
  echo "FAIL (AC1a): gate failure not attributed to the W11 compile --check step" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
}

# AC1 (b): failing mechanism-parity --strict stub -> gate non-zero.
rc="$(run_pr_gate "$WORKDIR/pass.sh" "$WORKDIR/fail.sh")"
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL (AC1b): failing mechanism-parity --strict step did not fail the gate" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
fi
grep -q 'W11 runtime-instruction parity (mechanism-parity --strict)' "$WORKDIR/gate.out" || {
  echo "FAIL (AC1b): gate failure not attributed to the W11 mechanism-parity step" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
}

# AC1 (c): both parity stubs pass (all prior gates stubbed pass) -> gate PASS.
rc="$(run_pr_gate "$WORKDIR/pass.sh" "$WORKDIR/pass.sh")"
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (AC1c): all-pass gate expected exit 0, got rc=$rc" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
fi
grep -q 'PASS: framework PR gate' "$WORKDIR/gate.out" || {
  echo "FAIL (AC1c): all-pass gate did not emit success line" >&2
  cat "$WORKDIR/gate.out" >&2
  exit 1
}

echo "PASS"
