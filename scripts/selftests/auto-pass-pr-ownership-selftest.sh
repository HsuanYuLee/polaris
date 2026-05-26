#!/usr/bin/env bash
# DP-231 D45 regression hook: generic publisher / draft PR cannot replace engineering.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTO_PASS="$ROOT/.claude/skills/auto-pass/SKILL.md"
ENGINEERING="$ROOT/.claude/skills/engineering/SKILL.md"

grep -q "generic GitHub PR" "$AUTO_PASS"
grep -q "authoritative task.md" "$AUTO_PASS"
grep -q "non-draft workspace PR" "$AUTO_PASS"
grep -q "PR via .*polaris-pr-create.sh.*不可 draft" "$ROOT/.claude/skills/references/engineering-first-cut-flow.md"
grep -q "唯一施工來源是 authoritative task.md" "$ENGINEERING"

echo "PASS: auto-pass PR ownership selftest"
