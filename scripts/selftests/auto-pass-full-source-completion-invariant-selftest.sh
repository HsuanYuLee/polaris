#!/usr/bin/env bash
# auto-pass-full-source-completion-invariant-selftest.sh
#
# Verifies the DP-235 full-source completion invariant is present at the
# constitutional/runtime surfaces that prevent a task-local blocker release from
# being mistaken for full source completion.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANCHOR="Full Source Completion Invariant"
NEGATIVE_ANCHOR="task-local closeout"

required_sources=(
  ".claude/instructions/core/bootstrap.md"
  ".claude/instructions/runtime/claude.md"
  ".claude/instructions/runtime/codex.md"
  ".claude/instructions/runtime/copilot.md"
  ".claude/rules/skill-routing.md"
  ".claude/skills/auto-pass/SKILL.md"
)

generated_targets=(
  "CLAUDE.md"
  "AGENTS.md"
  ".codex/AGENTS.md"
  ".github/copilot-instructions.md"
)

for rel in "${required_sources[@]}"; do
  if ! grep -Fq "$ANCHOR" "$ROOT/$rel"; then
    echo "FAIL: missing $ANCHOR in $rel" >&2
    exit 1
  fi
done

for rel in "${generated_targets[@]}"; do
  if ! grep -Fq "$ANCHOR" "$ROOT/$rel"; then
    echo "FAIL: missing generated $ANCHOR in $rel" >&2
    echo "Hint: run bash scripts/compile-runtime-instructions.sh" >&2
    exit 1
  fi
  if ! grep -Fq "completion is source-level, not task-local" "$ROOT/$rel"; then
    echo "FAIL: generated target lacks source-level completion wording: $rel" >&2
    exit 1
  fi
done

if ! grep -Fq "$NEGATIVE_ANCHOR" "$ROOT/.claude/skills/auto-pass/SKILL.md"; then
  echo "FAIL: auto-pass missing explicit negative task-local closeout guard" >&2
  exit 1
fi

if ! grep -Fq "framework-release closeout" "$ROOT/.claude/rules/skill-routing.md"; then
  echo "FAIL: skill routing missing framework-release closeout guard" >&2
  exit 1
fi

if ! grep -Fq "auto-pass-full-source-completion-invariant-selftest.sh" "$ROOT/scripts/manifest.json"; then
  echo "FAIL: script manifest missing full-source completion invariant selftest" >&2
  exit 1
fi

bash "$ROOT/scripts/compile-runtime-instructions.sh" --check >/tmp/dp235-full-source-compile-check.out 2>&1 || {
  cat /tmp/dp235-full-source-compile-check.out >&2
  echo "FAIL: runtime instruction targets are out of sync" >&2
  exit 1
}

echo "PASS: auto-pass full-source completion invariant selftest"
