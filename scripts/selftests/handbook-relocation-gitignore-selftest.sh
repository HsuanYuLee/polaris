#!/usr/bin/env bash
# Purpose: verify the framework handbook relocation and its narrow gitignore allowlist.
# Inputs:  none; resolves the current repository from this script location.
# Outputs: PASS on stdout; exits non-zero when relocation, identity, or ignore boundaries drift.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEW_ROOT="polaris-config/polaris-framework/handbook"
OLD_ROOT=".claude/rules/handbook/framework"

handbook_files=(
  index.md
  configuration-surface.md
  contract-design.md
  cross-llm-parity.md
  dependency-management.md
  development-standards.md
  release-topology.md
  script-governance.md
  config.yaml
)

for relative in "${handbook_files[@]}"; do
  test -f "$ROOT/$NEW_ROOT/$relative"
  git -C "$ROOT" ls-files --error-unmatch "$NEW_ROOT/$relative" >/dev/null
done

test ! -e "$ROOT/$OLD_ROOT"

grep -qx 'schema_version: 1' "$ROOT/$NEW_ROOT/config.yaml"
grep -qx 'project: polaris-framework' "$ROOT/$NEW_ROOT/config.yaml"
grep -qx 'base_branch: main' "$ROOT/$NEW_ROOT/config.yaml"

if git -C "$ROOT" check-ignore --no-index -q "$NEW_ROOT/index.md"; then
  echo "framework handbook unexpectedly ignored: $NEW_ROOT/index.md" >&2
  exit 1
fi

git -C "$ROOT" check-ignore --no-index -q \
  'exampleco/polaris-config/example-project/handbook/index.md'

grep -Fqx '!/polaris-config/polaris-framework/handbook/**' "$ROOT/.gitignore"

universal_files=(
  .claude/rules/handbook/implementation-language-choice.md
  .claude/rules/handbook/quality-standards.md
  .claude/rules/handbook/working-habits.md
)
git -C "$ROOT" diff --quiet HEAD -- "${universal_files[@]}"

echo "PASS: framework handbook relocation, identity, and gitignore boundary"
