#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-refinement-ac-coverage.sh"
TRACKED_DEFAULT="$ROOT_DIR/.claude/skills/references/ac-required-by-surface-defaults.yaml"
WORKDIR="$(mktemp -d -t dp207-ac-coverage.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# Tracked-default presence check: validator now defaults to this tracked reference.
if [[ ! -f "$TRACKED_DEFAULT" ]]; then
  echo "FAIL: tracked default yaml not found at $TRACKED_DEFAULT" >&2
  exit 1
fi

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

# --- New case: tracked-default path is the validator's default handbook ---
# When --handbook is omitted, validator must read the tracked reference. We
# verify by running the validator from ROOT_DIR with a refinement that hits the
# tracked default's `skill-behavior` surface.
TRACKED_DEFAULT_REFINEMENT="$WORKDIR/tracked-default.json"
write_refinement "$TRACKED_DEFAULT_REFINEMENT" '{
  "changed_files": [".claude/skills/auto-pass/SKILL.md"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "unit_test"}}
  ]
}'
(
  cd "$ROOT_DIR"
  bash "$VALIDATOR" "$TRACKED_DEFAULT_REFINEMENT"
) >"$WORKDIR/tracked-default.out"
rg -n 'PASS: refinement AC coverage' "$WORKDIR/tracked-default.out" >/dev/null

# --- New case: company override merges on top of defaults ---
# Override adds a brand-new surface id (`company-surface-fixture`) that hits a
# bespoke file glob. Validator should recognise the new surface and enforce its
# required AC even though it does not appear in the tracked defaults.
OVERRIDE="$WORKDIR/company-override.yaml"
cat >"$OVERRIDE" <<'YAML'
version: 1
surfaces:
  - id: company-surface-fixture
    file_globs:
      - "company-only/**"
    required_acceptance:
      - id: company-fixture-contract
        accepted_verification_methods:
          - unit_test
YAML

OVERRIDE_MISSING="$WORKDIR/override-missing.json"
write_refinement "$OVERRIDE_MISSING" '{
  "changed_files": ["company-only/widget.ts"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "manual"}}
  ]
}'
expect_fail "override-missing" "$VALIDATOR" "$OVERRIDE_MISSING" \
  --handbook "$HANDBOOK" --company-override "$OVERRIDE"
rg -n 'missing required AC company-fixture-contract' "$WORKDIR/override-missing.out" >/dev/null

OVERRIDE_PASSING="$WORKDIR/override-passing.json"
write_refinement "$OVERRIDE_PASSING" '{
  "changed_files": ["company-only/widget.ts"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "unit_test"}}
  ]
}'
"$VALIDATOR" "$OVERRIDE_PASSING" --handbook "$HANDBOOK" --company-override "$OVERRIDE" \
  >"$WORKDIR/override-passing.out"
rg -n 'PASS: refinement AC coverage' "$WORKDIR/override-passing.out" >/dev/null

# --- New case: override replaces same-id default surface ---
# Override redefines `skill-beavior-fixture` with a different required AC id so
# the same changed_files set now needs the override's AC, not the defaults'.
OVERRIDE_REPLACE="$WORKDIR/override-replace.yaml"
cat >"$OVERRIDE_REPLACE" <<'YAML'
version: 1
surfaces:
  - id: skill-beavior-fixture
    file_globs:
      - ".claude/skills/**"
    required_acceptance:
      - id: company-replace-contract
        accepted_verification_methods:
          - manual
YAML

REPLACE_MISSING="$WORKDIR/override-replace-missing.json"
write_refinement "$REPLACE_MISSING" '{
  "changed_files": [".claude/skills/auto-pass/SKILL.md"],
  "acceptance_criteria": [
    {"id": "AC1", "verification": {"method": "unit_test"}}
  ]
}'
expect_fail "override-replace-missing" "$VALIDATOR" "$REPLACE_MISSING" \
  --handbook "$HANDBOOK" --company-override "$OVERRIDE_REPLACE"
rg -n 'missing required AC company-replace-contract' "$WORKDIR/override-replace-missing.out" >/dev/null

echo "PASS: validate refinement AC coverage selftest"
