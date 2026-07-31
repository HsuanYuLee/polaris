#!/usr/bin/env bash
# Purpose: Selftest for DP-231 T11 framework source mutation no-bypass authority.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-framework-source-write.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local label="$1" file="$2" needle="$3"
  grep -q "$needle" "$file" || fail "$label missing '$needle': $(cat "$file")"
}

TASK_MD="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$TASK_MD" "$OUT"' EXIT

cat >"$TASK_MD" <<'MD'
---
status: IN_PROGRESS
---

# T1: fixture (1 pt)

## Allowed Files

- `.claude/skills/example/SKILL.md`
- `scripts/example.sh`
- `.codex/hooks/pre-framework-source-write.*`
MD

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer engineering \
  --task-md "$TASK_MD" --path ".claude/skills/example/SKILL.md" >"$OUT" 2>&1 \
  || fail "allowed framework path should pass"
assert_contains "allowed path" "$OUT" "PASS: framework source write allowed"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer engineering \
  --path ".claude/skills/example/SKILL.md" >"$OUT" 2>&1 && fail "missing task-md should block"
assert_contains "missing task" "$OUT" "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:missing-task-md"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer engineering \
  --task-md "$TASK_MD" --path ".claude/rules/not-allowed.md" >"$OUT" 2>&1 \
  && fail "outside Allowed Files should block"
assert_contains "outside allowed" "$OUT" "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:outside-allowed-files"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer unknown-writer \
  --task-md "$TASK_MD" --path ".claude/skills/example/SKILL.md" >"$OUT" 2>&1 \
  && fail "unknown writer should block"
assert_contains "unknown writer" "$OUT" "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:unknown-writer"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer engineering \
  --path "src/product-file.ts" >"$OUT" 2>&1 || fail "non-framework path should pass"
assert_contains "non framework" "$OUT" "PASS: no framework source write detected"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer codex-guarded-bash \
  --command "printf ok > .claude/skills/example/SKILL.md" >"$OUT" 2>&1 \
  && fail "shell framework write without task should block"
assert_contains "shell missing task" "$OUT" "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:missing-task-md"

bash "$VALIDATOR" --repo "$ROOT" --mode pre-write --writer codex-guarded-bash \
  --task-md "$TASK_MD" --command "printf ok > .claude/skills/example/SKILL.md" >"$OUT" 2>&1 \
  || fail "shell framework write with task should pass"
assert_contains "shell pass" "$OUT" "PASS: framework source write allowed"

bash "$VALIDATOR" --repo "$ROOT" --self-check-wiring >"$OUT" 2>&1 \
  || fail "wiring self-check should pass: $(cat "$OUT")"
assert_contains "wiring" "$OUT" "PASS: framework source write wiring"

# 每次寫入攔截的 PreToolUse / Codex hook 已隨 B 桶退役；框架 source write 授權
# 現在只有一條 runtime-neutral 執行面：PR gate W17 與 codex bash wrapper 都直接
# 呼叫 validate-framework-source-write.sh。
for file in \
  "$ROOT/scripts/codex-guarded-bash.sh" \
  "$ROOT/scripts/check-framework-pr-gate.sh"; do
  grep -q "validate-framework-source-write\\|W17 framework source write authority" "$file" \
    || fail "missing framework source wiring in $file"
done


echo "PASS: framework-source-mutation-no-bypass selftest"
