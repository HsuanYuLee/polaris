#!/usr/bin/env bash
# validate-refinement-inbox-record-selftest.sh — DP-228 T14 contract.
#
# Verifies that scripts/validate-refinement-inbox-record.sh supports the
# source-neutral schema introduced by DP-228 (AC-NF5 / AC13):
#
#   - `source_id` (string) and `source_type` (`dp` / `jira`) are accepted.
#   - Legacy `epic` field is read-only compatibility; records that only carry
#     `epic` (no `source_id` / `source_type`) still PASS but emit a stderr
#     warning so migration progress stays visible.
#   - DP fixture (`source_type: dp`, `source_id: DP-228`) PASSes.
#   - JIRA fixture (`source_type: jira`, `source_id: EXAMPLE-556`) PASSes.
#   - Malformed fixture (`source_type: github`) FAILs hard.
#
# Exit 0 → PASS (echo `PASS`); any failure prints diagnostic + non-zero exit.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

VALIDATOR="$ROOT_DIR/scripts/validate-refinement-inbox-record.sh"
WORKDIR="$(mktemp -d -t dp228-inbox-record.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$VALIDATOR" ]]; then
  echo "FAIL: validator is not executable: $VALIDATOR" >&2
  exit 1
fi

write_fixture() {
  local file="$1"
  local frontmatter="$2"
  mkdir -p "$(dirname "$file")"
  {
    printf '%s\n' "---"
    printf '%s\n' "$frontmatter"
    printf '%s\n' "---"
    cat <<'EOF'

## Decision

re-classified to refinement: AC boundary must be re-decided.

## Refinement Context

- Gate summary: ci-local remains over threshold after task-level repair.

## Decisions Needed

1. Decide whether the AC budget remains mandatory.

## Source Audit

- Source sidecar path is for audit only; refinement must not open it.
EOF
  } >"$file"
}

run_validator() {
  local file="$1"
  local expected_exit="$2"
  local label="$3"
  local out_file="$WORKDIR/${label}.out"
  set +e
  bash "$VALIDATOR" "$file" >"$out_file" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

# Case 1: DP source_type/source_id PASS.
dp_fixture="$WORKDIR/dp-source.md"
write_fixture "$dp_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: dp
source_id: DP-228
source_task: T3a
source_ticket: N/A
source_sidecar: docs-manager/src/content/docs/specs/design-plans/DP-228-foo/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$dp_fixture" 0 case1-dp-source
grep -q 'PASS' "$WORKDIR/case1-dp-source.out"

# Case 2: JIRA source_type/source_id PASS.
jira_fixture="$WORKDIR/jira-source.md"
write_fixture "$jira_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: jira
source_id: EXAMPLE-556
source_task: T3a
source_ticket: TASK-3711
source_sidecar: docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/escalations/T3a-2.md
escalation_count: 1
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$jira_fixture" 0 case2-jira-source
grep -q 'PASS' "$WORKDIR/case2-jira-source.out"

# Case 3: Legacy `epic` only (no source_type/source_id) → PASS with warning.
legacy_fixture="$WORKDIR/legacy-epic.md"
write_fixture "$legacy_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
epic: EPIC-478
source_task: T3a
source_ticket: TASK-3711
source_sidecar: docs-manager/src/content/docs/specs/companies/exampleco/EPIC-478/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$legacy_fixture" 0 case3-legacy-epic
grep -q 'PASS' "$WORKDIR/case3-legacy-epic.out"
grep -qi 'warn\|legacy\|deprecated' "$WORKDIR/case3-legacy-epic.out" || {
  echo "FAIL (case3-legacy-epic): expected legacy/warning notice in output" >&2
  cat "$WORKDIR/case3-legacy-epic.out" >&2
  exit 1
}

# Case 4: Malformed source_type (unsupported value `github`) → hard FAIL.
malformed_fixture="$WORKDIR/malformed.md"
write_fixture "$malformed_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: github
source_id: PR-1234
source_task: T3a
source_ticket: N/A
source_sidecar: docs-manager/src/content/docs/specs/design-plans/DP-228-foo/escalations/T3a-2.md
escalation_count: 1
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$malformed_fixture" 1 case4-malformed-source-type
grep -q 'FAIL' "$WORKDIR/case4-malformed-source-type.out"

# Case 5: Neither legacy `epic` nor new source_id provided → hard FAIL.
missing_source_fixture="$WORKDIR/missing-source.md"
write_fixture "$missing_source_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_task: T3a
source_ticket: TASK-3711
source_sidecar: docs-manager/src/content/docs/specs/companies/exampleco/EPIC-478/escalations/T3a-2.md
escalation_count: 1
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$missing_source_fixture" 1 case5-missing-source
grep -q 'FAIL' "$WORKDIR/case5-missing-source.out"

# Case 6: source_type=dp but source_id pattern is JIRA-style → hard FAIL.
mismatch_fixture="$WORKDIR/mismatch.md"
write_fixture "$mismatch_fixture" "skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: dp
source_id: EXAMPLE-556
source_task: T3a
source_ticket: TASK-3711
source_sidecar: docs-manager/src/content/docs/specs/design-plans/DP-228-foo/escalations/T3a-2.md
escalation_count: 1
created_at: 2026-04-29T09:30:00Z
consumed: false"
run_validator "$mismatch_fixture" 1 case6-source-type-mismatch
grep -q 'FAIL' "$WORKDIR/case6-source-type-mismatch.out"

# Case 7: Embedded --self-test still PASSes (the existing in-script self-test).
set +e
bash "$VALIDATOR" --self-test >"$WORKDIR/case7-embedded-selftest.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case7-embedded-selftest): embedded --self-test returned $rc" >&2
  cat "$WORKDIR/case7-embedded-selftest.out" >&2
  exit 1
fi

echo "PASS"
