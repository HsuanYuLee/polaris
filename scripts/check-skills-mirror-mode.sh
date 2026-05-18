#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_SKILLS="$ROOT_DIR/.agents/skills"
EXPECTED_TARGET="../.claude/skills"
PUBLIC_TASKS=(
  bootstrap
  doctor
  doctor-mise
  onboard-doctor
  release-preflight
  pr-create
  spec-close-parent
  script-audit
  docs-health
  verify
  cross-runtime-sync
)

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

for task in "${PUBLIC_TASKS[@]}"; do
  if ! grep -q "\\[tasks.${task}\\]" "$ROOT_DIR/mise.toml"; then
    echo "FAIL: public task missing from mise.toml: $task" >&2
    exit 1
  fi
  if ! grep -q "^[[:space:]]*${task}:" "$ROOT_DIR/polaris-toolchain.yaml"; then
    echo "FAIL: public task missing from polaris-toolchain.yaml: $task" >&2
    exit 1
  fi
done

echo "OK: .agents/skills -> $EXPECTED_TARGET"
echo "PASS: public task mirror surface (${#PUBLIC_TASKS[@]} tasks)"
