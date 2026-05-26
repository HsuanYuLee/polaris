#!/usr/bin/env bash
# DP-231 D45: framework source mutation belongs in engineering worktree, not main checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/engineering/SKILL.md"
FIRST_CUT="$ROOT/.claude/skills/references/engineering-first-cut-flow.md"

grep -q "Framework source mutation 只能在 engineering task worktree" "$SKILL"
grep -q "main checkout 上的" "$SKILL"
grep -q "framework-owned dirty source" "$SKILL"
grep -q "WORKTREE_PATH.*唯一 implementation repo" "$FIRST_CUT"
grep -q "內容只能作為參考" "$FIRST_CUT"

echo "PASS: engineering main dirty worktree selftest"
