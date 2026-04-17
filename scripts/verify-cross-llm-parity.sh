#!/usr/bin/env bash
set -euo pipefail

# verify-cross-llm-parity.sh
#
# Verify that generated Codex artifacts are in sync with Claude source-of-truth.
#
# Usage:
#   bash scripts/verify-cross-llm-parity.sh
#
# This script checks:
#   1) .claude/skills -> .agents/skills parity
#   2) .claude/rules -> .codex/AGENTS.md parity

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/3] Verify Claude/Codex skills parity"
bash "$SCRIPT_DIR/mechanism-parity.sh" --strict

echo
echo "[2/3] Verify Codex rules transpile parity"
bash "$SCRIPT_DIR/transpile-rules-to-codex.sh" --check

echo
echo "[3/3] Verify Codex fallback gate wiring"
test -x "$SCRIPT_DIR/codex-guarded-git-commit.sh"
test -x "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh"
test -x "$SCRIPT_DIR/codex-guarded-git-push.sh"
test -x "$SCRIPT_DIR/codex-guarded-bash.sh"
test -x "$SCRIPT_DIR/codex-mark-design-plan-implemented.sh"
bash "$SCRIPT_DIR/codex-guarded-git-commit.sh" --dry-run >/dev/null
POLARIS_SKIP_EVIDENCE=1 bash "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh" --dry-run >/dev/null
bash "$SCRIPT_DIR/codex-guarded-git-push.sh" --dry-run >/dev/null
bash "$SCRIPT_DIR/codex-guarded-bash.sh" --dry-run -- "echo parity-smoke" >/dev/null

tmp_root="$(mktemp -d)"
tmp_dir="$tmp_root/specs/design-plans/DP-999-parity-smoke"
tmp_plan="$tmp_dir/plan.md"
mkdir -p "$tmp_dir"
cat > "$tmp_plan" <<'EOF'
---
topic: parity-smoke
created: 2026-04-17
status: LOCKED
locked_at: 2026-04-17
---

## Implementation Checklist

- [ ] pending item
EOF

if bash "$SCRIPT_DIR/codex-mark-design-plan-implemented.sh" --dry-run "$tmp_plan" >/dev/null 2>&1; then
  echo "FAIL: expected design-plan gate to block unchecked checklist" >&2
  rm -rf "$tmp_root"
  exit 1
fi
rm -rf "$tmp_root"

echo
echo "Result: CROSS-LLM PARITY OK"
