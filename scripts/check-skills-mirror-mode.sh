#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_SKILLS="$ROOT_DIR/.agents/skills"
EXPECTED_TARGET="../.claude/skills"

if [[ ! -L "$AGENTS_SKILLS" ]]; then
  echo "FAIL: $AGENTS_SKILLS is not a symlink." >&2
  echo "Fix: bash scripts/sync-skills-cross-runtime.sh --to-agents --link" >&2
  exit 1
fi

actual_target="$(readlink "$AGENTS_SKILLS")"
if [[ "$actual_target" != "$EXPECTED_TARGET" ]]; then
  echo "FAIL: $AGENTS_SKILLS points to '$actual_target', expected '$EXPECTED_TARGET'." >&2
  echo "Fix: bash scripts/sync-skills-cross-runtime.sh --to-agents --link" >&2
  exit 1
fi

echo "OK: .agents/skills -> $EXPECTED_TARGET"
