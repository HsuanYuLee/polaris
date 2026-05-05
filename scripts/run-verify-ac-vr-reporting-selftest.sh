#!/usr/bin/env bash
# Selftest for verify-AC native VR execution/reporting contract.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: expected $file to contain pattern: $pattern" >&2
    exit 1
  fi
}

assert_contains "$ROOT_DIR/.claude/skills/verify-AC/SKILL.md" 'scripts/run-visual-snapshot\.sh'
assert_contains "$ROOT_DIR/.claude/skills/verify-AC/SKILL.md" 'visual-regression'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-environment-prep.md" 'verification/\{run_id\}/vr'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-environment-prep.md" 'MANUAL_REQUIRED'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-execution-flow.md" 'run-visual-snapshot\.sh'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-execution-flow.md" '\| `PASS` \| `PASS` \|'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-execution-flow.md" '\| `BLOCK` \| `FAIL` \|'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-execution-flow.md" '\| `BLOCKED_ENV` \| `UNCERTAIN` \|'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-execution-flow.md" '\| `MANUAL_REQUIRED` \| `MANUAL_REQUIRED` \|'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-reporting-flow.md" 'polaris-vr-\{ticket\}-\{head_sha\}'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-reporting-flow.md" 'verification/\{run_id\}/vr'
assert_contains "$ROOT_DIR/.claude/skills/references/verify-ac-reporting-flow.md" 'diff artifact'

echo "PASS: verify-AC VR reporting selftest"
