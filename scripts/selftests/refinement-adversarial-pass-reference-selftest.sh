#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
test -f "$ROOT/.claude/skills/references/refinement-adversarial-pass.md"
test "$(wc -l < "$ROOT/.claude/skills/references/refinement-adversarial-pass.md")" -le 700
grep -q "Machine contract" "$ROOT/.claude/skills/references/refinement-adversarial-pass.md"
echo "PASS: refinement adversarial pass reference"
