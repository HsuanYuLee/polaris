#!/usr/bin/env bash
set -euo pipefail

# verify-cross-llm-parity.sh
#
# Verify that generated runtime artifacts are in sync with Polaris source-of-truth.
#
# Usage:
#   bash scripts/verify-cross-llm-parity.sh
#
# This script checks:
#   1) .agents/skills mirror mode
#   2) .claude/skills -> .agents/skills parity
#   3) .claude/instructions -> runtime target parity
#   4) polaris-config migration closure for active runtime paths
#   5) repo handbook path contract for shared runtime/docs sources
#   6) revision rebase gate wiring and behavior
#   7) Codex fallback gate wiring

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

refresh_runtime_targets() {
  echo "INFO: Refreshing runtime instruction targets from .claude/instructions/manifest.yaml"
  bash "$SCRIPT_DIR/compile-runtime-instructions.sh"
}

echo "[1/7] Verify skills mirror mode"
bash "$SCRIPT_DIR/check-skills-mirror-mode.sh"

echo
echo "[2/7] Verify Claude/Codex skills parity"
bash "$SCRIPT_DIR/mechanism-parity.sh" --strict

echo
echo "[3/7] Verify runtime instruction target parity"
if ! bash "$SCRIPT_DIR/compile-runtime-instructions.sh" --check; then
  echo "INFO: runtime instruction target drift detected; regenerating once and rechecking."
  refresh_runtime_targets
  bash "$SCRIPT_DIR/compile-runtime-instructions.sh" --check
fi

echo
echo
echo "[4/7] Verify polaris-config migration closure"
bash "$SCRIPT_DIR/validate-polaris-config-migration.sh"

echo
echo "[5/7] Verify repo handbook path contract"
bash "$SCRIPT_DIR/validate-handbook-path-contract.sh"

echo
echo "[6/7] Verify revision rebase gate"
bash "$SCRIPT_DIR/gates/gate-revision-rebase-selftest.sh"
grep -q 'gate-revision-rebase.sh' "$ROOT_DIR/.claude/hooks/pre-push-quality-gate.sh"
grep -q 'revision-rebase-required' "$ROOT_DIR/.claude/skills/references/deterministic-hooks-registry.md"

echo
echo "[7/7] Verify Codex fallback gate wiring"
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
