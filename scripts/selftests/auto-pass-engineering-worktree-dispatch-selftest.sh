#!/usr/bin/env bash
# DP-231 D45: auto-pass must route pre-setup missing worktree to engineering setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/auto-pass/SKILL.md"

grep -q "engineering first-cut pre-setup" "$SKILL"
grep -q "engineering-branch-setup.sh" "$SKILL"
grep -q "post-setup / resume / verify-AC" "$SKILL"
grep -q "blocked_by_missing_worktree" "$SKILL"

echo "PASS: auto-pass engineering worktree dispatch selftest"
