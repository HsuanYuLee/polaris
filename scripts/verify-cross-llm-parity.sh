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
#   1) .agents/skills mirror mode
#   2) .claude/skills -> .agents/skills parity
#   3) .claude/rules -> .codex/AGENTS.md parity

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CODEX_AGENTS="$ROOT_DIR/.codex/AGENTS.md"
CODEX_MANIFEST="$ROOT_DIR/.codex/.generated/rules-manifest.txt"

refresh_codex_rules_target() {
  echo "INFO: Refreshing ignored Codex generated rule target from .claude/rules/**/*.md"
  bash "$SCRIPT_DIR/transpile-rules-to-codex.sh"
}

echo "[1/4] Verify skills mirror mode"
bash "$SCRIPT_DIR/check-skills-mirror-mode.sh"

echo
echo "[2/4] Verify Claude/Codex skills parity"
bash "$SCRIPT_DIR/mechanism-parity.sh" --strict

echo
echo "[3/4] Verify Codex rules transpile parity"
if [[ ! -f "$CODEX_AGENTS" || ! -f "$CODEX_MANIFEST" ]]; then
  echo "INFO: Codex generated rule target is missing; materializing before parity check."
  refresh_codex_rules_target
fi

if ! bash "$SCRIPT_DIR/transpile-rules-to-codex.sh" --check; then
  echo "INFO: Codex generated rule target drift detected; regenerating once and rechecking."
  refresh_codex_rules_target
  bash "$SCRIPT_DIR/transpile-rules-to-codex.sh" --check
fi

echo
echo "[4/4] Verify Codex fallback gate wiring"
test -x "$SCRIPT_DIR/codex-guarded-git-commit.sh"
test -x "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh"
test -x "$SCRIPT_DIR/codex-guarded-git-push.sh"
test -x "$SCRIPT_DIR/codex-guarded-bash.sh"
test -x "$SCRIPT_DIR/codex-mark-design-plan-implemented.sh"
test -x "$SCRIPT_DIR/close-parent-spec-if-complete.sh"
bash "$SCRIPT_DIR/codex-guarded-git-commit.sh" --dry-run >/dev/null
POLARIS_SKIP_EVIDENCE=1 bash "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh" --dry-run >/dev/null
bash "$SCRIPT_DIR/codex-guarded-git-push.sh" --dry-run >/dev/null
bash "$SCRIPT_DIR/codex-guarded-bash.sh" --dry-run -- "echo parity-smoke" >/dev/null
CLOSE_PARENT_SPEC_SELFTEST=1 bash "$SCRIPT_DIR/close-parent-spec-if-complete.sh" >/dev/null

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
