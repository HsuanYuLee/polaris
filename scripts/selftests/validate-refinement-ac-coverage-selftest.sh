#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-refinement-ac-coverage.sh"
WORKDIR="$(mktemp -d -t dp207-ac-coverage.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

HANDBOOK="$WORKDIR/ac-required-by-surface.yaml"
cat >"$HANDBOOK" <<'YAML'
version: 1
surfaces:
  - id: skill-beavior-fixture
    file_globs:
      - ".claude/skills/**"
    required_acceptance:
      - id: framework-behavior-contract
        accepted_verification_methods:
          - unit_test
YAML

write_refinement() {
  local path="$1"
  local body="$2"
  printf '%s\n' "$body" >"$path"
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$WORKDIR/${label}.out" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$WORKDIR/${label}.out" >&2
    exit 1
  fi
}

MISSING="$WORKDIR/missing-changed-files.json"
write_refinement "$MISSING" '{
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "unit_test"}}
  ]
}'
expect_fail "missing-changed-files" "$VALIDATOR" "$MISSING" --handbook "$HANDBOOK"
rg -n 'changed_files is required' "$WORKDIR/missing-changed-files.out" >/dev/null

MISSING_AC="$WORKDIR/missing-required-ac.json"
write_refinement "$MISSING_AC" '{
  "changed_files": [".claude/skills/auto-pass/SKILL.md"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "manual"}}
  ]
}'
expect_fail "missing-required-ac" "$VALIDATOR" "$MISSING_AC" --handbook "$HANDBOOK"
rg -n 'missing required AC framework-behavior-contract' "$WORKDIR/missing-required-ac.out" >/dev/null

PASSING="$WORKDIR/passing.json"
write_refinement "$PASSING" '{
  "changed_files": [".claude/skills/auto-pass/SKILL.md"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "unit_test"}}
  ]
}'
"$VALIDATOR" "$PASSING" --handbook "$HANDBOOK" >/tmp/dp207-ac-coverage-pass.out

echo "PASS: validate refinement AC coverage selftest"
