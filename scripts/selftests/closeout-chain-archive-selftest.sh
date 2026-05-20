#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MARK_SPEC_IMPLEMENTED_SELFTEST=1 bash "$ROOT/scripts/mark-spec-implemented.sh" >/tmp/dp207-mark-spec-auto-archive.out
rg -n 'archive-terminal-parent|mark-spec-implemented.sh' "$ROOT/scripts/framework-release-closeout.sh" >/tmp/dp207-framework-closeout-archive.out
rg -n 'terminal complete|auto-archive|archive-spec.sh' "$ROOT/.claude/skills/references/auto-pass-execution-flow.md" "$ROOT/.claude/skills/auto-pass/SKILL.md" >/tmp/dp207-auto-pass-closeout-docs.out
rg -n 'closeout-chain-archive-not-deterministic|closeout-chain-auto-archive' "$ROOT/.claude/rules/mechanism-registry.md" >/tmp/dp207-closeout-mechanism.out

echo "PASS: closeout chain archive selftest"
