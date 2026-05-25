#!/usr/bin/env bash
# DP-230 T2 — D15 task schema validator parity selftest.
#
# 對應 AC11：
#   1. scripts/validate-task-md.sh 對 V task `ac_verification` schema doc fixture
#      （`disposition: pending` / `last_run: null` / `evidence: null` 形態）走 PASS。
#   2. scripts/validate-task-md-deps.sh 對 short-form `T1` 與 full-form
#      `DP-228-T1` deps fixture 都 PASS；混合 deps `T1, DP-228-T2` PASS。
#
# Adversarial fixtures：兩條規則各自的 broken case 必須仍 FAIL，避免「兩條一起鬆」。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_TASK_MD="$ROOT_DIR/scripts/validate-task-md.sh"
VALIDATE_TASK_MD_DEPS="$ROOT_DIR/scripts/validate-task-md-deps.sh"

tmpdir="$(mktemp -d -t validate-task-md-shape-parity-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Helper: write a V task fixture mirroring the canonical
# `.claude/skills/references/v-task-md-schema.md` schema doc body (pending form).
# -----------------------------------------------------------------------------
write_v_task_pending_fixture() {
  local file="$1"
  local disposition="${2:-pending}"
  cat >"$file" <<EOF
---
title: "DP-999 V1: pending verification fixture (1 pt)"
description: "V mode ac_verification pending schema doc fixture (pre verify-AC run)."
status: PLANNED
ac_verification:
  disposition: ${disposition}
  last_run: null
  evidence: null
ac_verification_log: []
jira_transition_log: []
depends_on:
  - DP-999-T1
---

# V1: pending verification fixture (1 pt)

> Source: DP-999 | Task: DP-999-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-V1 |
| JIRA key | N/A |
| Implementation tasks | DP-999-T1 |
| AC 範圍 | AC1, AC2 |
| Base branch | main |
| Branch chain | main -> task/DP-999-V1-fixture |
| Depends on | DP-999-T1 |
| References to load | - \`docs-manager/src/content/docs/specs/design-plans/DP-999-*/refinement.md\` |

## Verification Handoff

驗收將由 verify-AC 觸發，產出寫回本檔 \`ac_verification\` + \`ac_verification_log[]\`。

## 目標

驗證 V mode ac_verification pending lifecycle 形態。

## 驗收項目

| AC | 描述 | Verification method |
|----|------|---------------------|
| AC1 | 驗證 schema doc fixture 走 PASS | manual |
| AC2 | adversarial 形態仍 FAIL | manual |

## 估點理由

1 pt - validator fixture。

## 驗收計畫（AC level）

- 對應 schema doc fixture 跑 validator。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## 驗收步驟

\`\`\`bash
# Entry: verify-AC consumes this V*.md per AC step list below.
echo "AC steps defined below — verify-AC executes this V*.md."
\`\`\`
EOF
}

# -----------------------------------------------------------------------------
# Helper: build a tasks/ tree to exercise validate-task-md-deps.sh.
# -----------------------------------------------------------------------------
write_t_task_with_deps() {
  local file="$1"
  local deps="$2"   # e.g. '[T1]', '[DP-228-T1]', '[T1, DP-228-T2]', '[]'
  local id="$3"
  cat >"$file" <<EOF
---
depends_on: ${deps}
---

# ${id}: deps fixture (1 pt)

- **Fixtures**: N/A
EOF
}

# =============================================================================
# Part 1: validate-task-md.sh V mode ac_verification pending fixture
# =============================================================================

v_pending_pass="$tmpdir/V1-pending-pass.md"
write_v_task_pending_fixture "$v_pending_pass" "pending"
if ! bash "$VALIDATE_TASK_MD" "$v_pending_pass" >"$tmpdir/v-pending-pass.out" 2>&1; then
  echo "----- v-pending-pass.out -----" >&2
  cat "$tmpdir/v-pending-pass.out" >&2
  fail "validate-task-md.sh should PASS for V task ac_verification pending fixture"
fi

# adversarial: unknown disposition enum value still fails
v_pending_bad="$tmpdir/V1-pending-bad.md"
write_v_task_pending_fixture "$v_pending_bad" "weird_state"
if bash "$VALIDATE_TASK_MD" "$v_pending_bad" >"$tmpdir/v-pending-bad.out" 2>&1; then
  fail "validate-task-md.sh should FAIL for V task ac_verification unknown disposition"
fi
if ! grep -qE "ac_verification\.disposition" "$tmpdir/v-pending-bad.out"; then
  cat "$tmpdir/v-pending-bad.out" >&2
  fail "expected ac_verification.disposition diagnostic for unknown disposition"
fi

# =============================================================================
# Part 2: validate-task-md-deps.sh short-form / full-form / mixed deps parity
# =============================================================================

# 2a — short-form deps `[T1]` PASS
short_dir="$tmpdir/short-form/tasks"
mkdir -p "$short_dir/T1" "$short_dir/T2"
write_t_task_with_deps "$short_dir/T1/index.md" "[]" "T1"
write_t_task_with_deps "$short_dir/T2/index.md" "[T1]" "T2"
if ! bash "$VALIDATE_TASK_MD_DEPS" "$short_dir" >"$tmpdir/short.out" 2>&1; then
  cat "$tmpdir/short.out" >&2
  fail "validate-task-md-deps.sh should PASS for short-form T1 deps fixture"
fi

# 2b — full-form deps `[DP-228-T1]` PASS (cross-DP external dep)
full_dir="$tmpdir/full-form/tasks"
mkdir -p "$full_dir/T1"
write_t_task_with_deps "$full_dir/T1/index.md" "[DP-228-T1]" "T1"
if ! bash "$VALIDATE_TASK_MD_DEPS" "$full_dir" >"$tmpdir/full.out" 2>&1; then
  cat "$tmpdir/full.out" >&2
  fail "validate-task-md-deps.sh should PASS for full-form DP-228-T1 deps fixture"
fi

# 2c — mixed deps `[T1, DP-228-T2]` PASS
mixed_dir="$tmpdir/mixed/tasks"
mkdir -p "$mixed_dir/T1" "$mixed_dir/T2"
write_t_task_with_deps "$mixed_dir/T1/index.md" "[]" "T1"
write_t_task_with_deps "$mixed_dir/T2/index.md" "[T1, DP-228-T2]" "T2"
if ! bash "$VALIDATE_TASK_MD_DEPS" "$mixed_dir" >"$tmpdir/mixed.out" 2>&1; then
  cat "$tmpdir/mixed.out" >&2
  fail "validate-task-md-deps.sh should PASS for mixed deps fixture (T1 + DP-228-T2)"
fi

# 2d — adversarial: malformed full-form `[DP-228-X9]` (not a valid task id pattern) must FAIL
bad_full_dir="$tmpdir/bad-full/tasks"
mkdir -p "$bad_full_dir/T1"
write_t_task_with_deps "$bad_full_dir/T1/index.md" "[DP-228-X9]" "T1"
if bash "$VALIDATE_TASK_MD_DEPS" "$bad_full_dir" >"$tmpdir/bad-full.out" 2>&1; then
  fail "validate-task-md-deps.sh should FAIL for malformed full-form deps DP-228-X9"
fi

# 2e — adversarial: unknown short-form (no such local task) must FAIL
unknown_short="$tmpdir/unknown-short/tasks"
mkdir -p "$unknown_short/T1"
write_t_task_with_deps "$unknown_short/T1/index.md" "[T7]" "T1"
if bash "$VALIDATE_TASK_MD_DEPS" "$unknown_short" >"$tmpdir/unknown-short.out" 2>&1; then
  fail "validate-task-md-deps.sh should FAIL for unknown short-form local deps T7"
fi

# 2f — adversarial: linear-chain violation with two local short-form deps must still FAIL
two_local_dir="$tmpdir/two-local/tasks"
mkdir -p "$two_local_dir/T1" "$two_local_dir/T2" "$two_local_dir/T3"
write_t_task_with_deps "$two_local_dir/T1/index.md" "[]" "T1"
write_t_task_with_deps "$two_local_dir/T2/index.md" "[]" "T2"
write_t_task_with_deps "$two_local_dir/T3/index.md" "[T1, T2]" "T3"
if bash "$VALIDATE_TASK_MD_DEPS" "$two_local_dir" >"$tmpdir/two-local.out" 2>&1; then
  fail "validate-task-md-deps.sh should FAIL for two same-DP short-form deps (non-linear)"
fi

echo "PASS: validate-task-md-shape-parity selftest"
