#!/usr/bin/env bash
# Purpose: Verify the check that refuses to let a blocking gate go unaccounted
#          for — every discovered gate is either covered locally or disclosed.
# Inputs:  codecov and declaration fixtures under mktemp. The GitHub ruleset
#          source is deliberately unreachable here (a nonexistent repo), which
#          exercises the gap path rather than mocking a remote.
# Outputs: PASS when a fully accounted-for set passes, an unaccounted gate is
#          reported as a silent third state, coverage read from per-flag statuses
#          rather than the global switch, and an unreadable source is reported as
#          a gap rather than silently skipped.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-gate-coverage.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# The shape that reads backwards if you only look at the global switch: patch
# coverage is off globally while a per-flag status sets the real threshold.
cat > "$WORK/codecov.yml" <<'YAML'
coverage:
  status:
    patch: false
    project: false
flag_management:
  individual_flags:
    - name: main-core
      statuses:
        - type: patch
          target: 60%
YAML

run_check() {
  # Description: run the check against a declaration fixture.
  # Args: $1 = declaration path
  python3 "$CHECK" --repo example-org/does-not-exist \
    --codecov "$WORK/codecov.yml" --declaration "$1" 2>&1
}

echo "check-gate-coverage selftest"

# Everything discovered is accounted for, so the run is clean apart from the
# unreachable remote.
cat > "$WORK/accounted.yaml" <<'YAML'
covered:
  - gate: codecov/patch/main-core
    command: pnpm test --coverage
disclosed:
  - gate: Milestone Required
    reason: enforced on the PR only
YAML
out="$(run_check "$WORK/accounted.yaml")" || fail "an accounted-for set should pass: $out"
echo "  ok  fully accounted set passes"

# The one this check exists for: a gate that blocks people but appears in
# neither list. Passing quietly here is the silent third state.
cat > "$WORK/unaccounted.yaml" <<'YAML'
covered: []
disclosed: []
YAML
if out="$(run_check "$WORK/unaccounted.yaml")"; then
  fail "an unaccounted gate should not pass: $out"
fi
printf '%s' "$out" | grep -q 'POLARIS_GATE_SILENT_THIRD_STATE' \
  || fail "an unaccounted gate must be reported as a silent third state"
printf '%s' "$out" | grep -q 'codecov/patch/main-core' \
  || fail "the per-flag status must be discovered despite the global switch being off"
echo "  ok  unaccounted gate reported, per-flag status discovered"

# An unreadable source must be visible as a gap, never treated as "no gates
# found here" — that would turn a tooling failure into a clean bill of health.
out="$(run_check "$WORK/accounted.yaml")" || true
printf '%s' "$out" | grep -q 'GAP:' \
  || fail "an unreachable ruleset source must be reported as a gap"
echo "  ok  unreadable source reported as a gap"

# A missing codecov file is itself a gap, not a pass.
out="$(python3 "$CHECK" --repo example-org/does-not-exist \
  --codecov "$WORK/absent.yml" --declaration "$WORK/accounted.yaml" 2>&1 || true)"
printf '%s' "$out" | grep -q 'GAP:' \
  || fail "a missing codecov file must be reported as a gap"
echo "  ok  missing codecov file reported as a gap"

echo "PASS: check-gate-coverage"
