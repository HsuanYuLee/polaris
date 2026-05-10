#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-source-template-drift.sh"

bash "$SCRIPT" --repo "$ROOT_DIR" --refinement-json docs-manager/src/content/docs/specs/design-plans/DP-140-secondary-llm-main-development-chain-mechanical-enforcement/refinement.json

tmpdir="$(mktemp -d -t source-template-drift.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.claude/skills/references" "$tmpdir/scripts"
cp "$ROOT_DIR/.claude/skills/references/refinement-source-template.md" "$tmpdir/.claude/skills/references/refinement-source-template.md"
cp "$ROOT_DIR/scripts/create-design-plan.sh" "$tmpdir/scripts/create-design-plan.sh"
cat >"$tmpdir/.claude/skills/references/epic-template.md" <<'MD'
# Bad Epic Template
MD
if bash "$SCRIPT" --repo "$tmpdir" >/dev/null 2>&1; then
  echo "FAIL: bad epic template drift passed" >&2
  exit 1
fi

echo "PASS: check-source-template-drift selftest"
