#!/usr/bin/env bash
set -euo pipefail

# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage:'
  command printf '%s\n' '  bash scripts/verify-cross-llm-parity.sh'
  command printf '%s\n' '  bash scripts/verify-cross-llm-parity.sh --help'
  command printf '%s\n' ''
  command printf '%s\n' 'Verifies generated runtime, skill, hook, and Codex fallback parity.'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/verify-cross-llm-parity.sh
  bash scripts/verify-cross-llm-parity.sh --help

Verifies generated runtime, skill, hook, and Codex fallback parity.
USAGE
}

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
#   8) Runtime-neutral specs-bound write contract gate

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

make_codex_fallback_fixture() {
  local tmp_root="$1"
  local fixture="$tmp_root/repo"
  local dp_dir="$fixture/docs-manager/src/content/docs/specs/design-plans/DP-999-parity-source"

  git init -q -b task/DP-999-T1-parity-fixture "$fixture"
  git -C "$fixture" config user.name "Polaris Selftest"
  git -C "$fixture" config user.email "polaris-selftest@example.com"
  cat > "$fixture/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  cat > "$fixture/mise.toml" <<'TOML'
[tools]
node = "22.12.0"
TOML
  mkdir -p "$dp_dir/tasks/T1"
  cat > "$dp_dir/tasks/T1/index.md" <<'MD'
---
title: "DP-999 T1: 驗證 parity fixture"
description: "驗證 parity fixture task。"
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
    reason: "fixture"
depends_on: []
---

# T1: 驗證 parity fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-parity-fixture |
| Task branch | task/DP-999-T1-parity-fixture |
| Depends on | N/A |
| References to load | - scripts/verify-cross-llm-parity.sh |

## 目標

fixture

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `README.md` | modify | fixture |

## Allowed Files

- `README.md`

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| fixture | `README.md` | fixture | `true` |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | fixture | engineering |
| test | yes | fixture | engineering |
| verify | yes | fixture | engineering |
| ci-local | no | N/A | planner decision |

## Out Of Scope

- fixture

## 估點理由

1 pt - fixture

## 測試計畫（code-level）

- `true`

## Test Command

```bash
true
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
true
```
MD
  echo "# parity fixture" > "$fixture/README.md"
  # task.md is intentionally left untracked: docs-manager specs are local
  # planning/execution artifacts, and PR creation must reject tracked specs.
  git -C "$fixture" add workspace-config.yaml mise.toml README.md
  git -C "$fixture" commit -qm "fixture"
  printf '%s\n' "$fixture"
}

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
# DP-294 AC7: converge the final-response language-guard parity into the canonical
# aggregate. The guard's SoT is the runtime overlays + compiler-emitted core; this
# selftest asserts the overlay three-file SoT and the four generated targets carry
# it. Wiring it here makes the cross-runtime guard presence a blocking parity
# invariant instead of a standalone selftest that the closeout could skip — which
# is what produced the earlier false "closeout parity advisory" (the guard was in
# fact present; the misreport came from a stale bootstrap assertion, fixed in AC3).
bash "$SCRIPT_DIR/selftests/runtime-final-response-language-guard-selftest.sh"

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
echo "[7/8] Verify Codex fallback gate wiring"
test -x "$SCRIPT_DIR/codex-guarded-git-commit.sh"
test -x "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh"
test -x "$SCRIPT_DIR/codex-guarded-git-push.sh"
test -x "$SCRIPT_DIR/codex-guarded-bash.sh"
test -x "$SCRIPT_DIR/codex-mark-design-plan-implemented.sh"
test -x "$SCRIPT_DIR/close-parent-spec-if-complete.sh"
grep -q 'polaris-pr-create.sh' "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh"
if grep -qE 'exec[[:space:]]+gh[[:space:]]+pr[[:space:]]+create' "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh"; then
  echo "FAIL: Codex PR fallback must delegate to polaris-pr-create.sh, not exec bare gh pr create" >&2
  exit 1
fi
tmp_root="$(mktemp -d)"
nonselfref_classifier="$tmp_root/nonselfref-classifier.sh"
cat > "$nonselfref_classifier" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"schema_version":1,"self_referential":false}'
SH
chmod +x "$nonselfref_classifier"
bash "$SCRIPT_DIR/codex-guarded-git-commit.sh" --dry-run >/dev/null
POLARIS_DETECT_SELFREF_BIN="$nonselfref_classifier" \
  POLARIS_SKIP_EVIDENCE=1 \
  bash "$SCRIPT_DIR/codex-guarded-git-push.sh" --dry-run >/dev/null
bash "$SCRIPT_DIR/codex-guarded-bash.sh" --dry-run -- "echo parity-smoke" >/dev/null
CLOSE_PARENT_SPEC_SELFTEST=1 bash "$SCRIPT_DIR/close-parent-spec-if-complete.sh" >/dev/null

fixture_repo="$(make_codex_fallback_fixture "$tmp_root")"
POLARIS_SKIP_EVIDENCE=1 \
  GATE_PROJECT_DIR="$fixture_repo" \
  MISE_TRUSTED_CONFIG_PATHS="$fixture_repo/mise.toml" \
  bash "$SCRIPT_DIR/codex-guarded-gh-pr-create.sh" --dry-run \
    --task-md "$fixture_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-parity-source/tasks/T1/index.md" >/dev/null
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
echo "[8/8] Verify runtime-neutral specs-bound write contract gate"
bash "$SCRIPT_DIR/selftests/validate-specs-bound-write-contract-selftest.sh"
tmp_root="$(mktemp -d)"
invalid="$tmp_root/repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/dogfood-evidence/DP-999/codex-bypass.md"
mkdir -p "$(dirname "$invalid")" "$tmp_root/repo/scripts/lib"
cp "$ROOT_DIR/scripts/lib/evidence-producers.json" "$tmp_root/repo/scripts/lib/evidence-producers.json"
cat >"$invalid" <<'MD'
## Observed

Codex apply_patch or shell bypass fixture without Starlight frontmatter.
MD
if bash "$SCRIPT_DIR/validate-specs-bound-write-contract.sh" --repo "$tmp_root/repo" --files "$invalid" >/tmp/codex-specs-bound-bypass.out 2>&1; then
  echo "FAIL: Codex bypass fixture should fail specs-bound write contract" >&2
  rm -rf "$tmp_root"
  exit 1
fi
grep -q 'missing required frontmatter' /tmp/codex-specs-bound-bypass.out
rm -rf "$tmp_root"

bash "$SCRIPT_DIR/validate-model-tier-policy.sh"

echo
echo "[9/9] Verify Claude/Codex dual-platform mechanism parity (D43)"
# DP-343 T1 / AC43: same deterministic gate the framework PR gate (W16) runs, so
# hook parity is blocked at both PR-merge and release-preflight time.
bash "$SCRIPT_DIR/validate-cross-llm-mechanism-parity.sh" --repo "$ROOT_DIR"

echo
echo "Result: CROSS-LLM PARITY OK"
