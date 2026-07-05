#!/usr/bin/env bash
# Purpose: Verify refinement Bug source mode routing docs and stale exception removal.
# Inputs:  Repository checkout containing refinement skill/reference docs.
# Outputs: PASS line on success; exits non-zero on contract drift.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/refinement/SKILL.md"
MODE_REF="$ROOT/.claude/skills/references/refinement-bug-source-mode.md"
SOURCE_REF="$ROOT/.claude/skills/references/refinement-source-mode.md"
INDEX="$ROOT/.claude/skills/references/INDEX.md"

for file in "$SKILL" "$MODE_REF" "$SOURCE_REF" "$INDEX"; do
  [[ -f "$file" ]] || { echo "FAIL: missing file: $file" >&2; exit 1; }
done

required_terms=(
  "source_kind=bug"
  "reproduction"
  "rca_investigation"
  "source_pr_identification"
  "severity_impact_assessment"
  "refinement.md"
  "refinement.json"
)

for term in "${required_terms[@]}"; do
  grep -qF "$term" "$MODE_REF" || {
    echo "FAIL: refinement-bug-source-mode.md missing term: $term" >&2
    exit 1
  }
done

grep -qF "Bug source mode" "$SKILL" || {
  echo "FAIL: refinement SKILL does not route Bug source mode" >&2
  exit 1
}
grep -qF "refinement-bug-source-mode.md" "$SOURCE_REF" || {
  echo "FAIL: refinement-source-mode missing Bug source reference" >&2
  exit 1
}
grep -qF "refinement-bug-source-mode.md" "$INDEX" || {
  echo "FAIL: references INDEX missing Bug source mode row" >&2
  exit 1
}
if grep -qF "Bug 不屬於 refinement-owned source" "$SKILL"; then
  echo "FAIL: stale legacy Bug diagnosis exception remains in refinement SKILL" >&2
  exit 1
fi

echo "PASS: refinement-bug-source-mode selftest"
