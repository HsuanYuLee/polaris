#!/usr/bin/env bash
# DP-231 D45: auto-pass must route pre-setup missing worktree to engineering setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/auto-pass/SKILL.md"
FLOW="$ROOT/.claude/skills/references/auto-pass-execution-flow.md"
VERIFY_SKILL="$ROOT/.claude/skills/verify-AC/SKILL.md"

grep -q "engineering first-cut pre-setup" "$SKILL"
grep -q "engineering-branch-setup.sh" "$SKILL"
grep -q "post-setup / resume / verify-AC" "$SKILL"
grep -q "blocked_by_missing_worktree" "$SKILL"
grep -q "kind=verify_integration" "$FLOW"
grep -q "verify-integration-{source}-{Vn}" "$FLOW"
grep -q "不得 fall back 到 main checkout" "$FLOW"
grep -q "worktree_resolution.kind=verify_integration" "$VERIFY_SKILL"
grep -q "不得改用 main checkout" "$VERIFY_SKILL"

echo "PASS: auto-pass engineering worktree dispatch selftest"
