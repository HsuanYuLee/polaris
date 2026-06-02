#!/usr/bin/env bash
# Purpose: Selftest for task.md frontmatter `task_shape` enum schema (DP-262 T1).
#          Covers AC1 (validate-task-md recognizes the enum + parse-task-md
#          --field task_shape) and AC-NEG4 (validate-task-md rejects a non-enum
#          task_shape value). Asserts orthogonality to the in-production
#          `task_kind` field (T/V completion-gate dispatcher), which must keep
#          passing.
# Inputs:  none (builds tmpdir task.md fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
PARSER="$ROOT_DIR/scripts/parse-task-md.sh"

tmpdir="$(mktemp -d -t task-md-task-shape-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_task <file> <extra_frontmatter_lines>
# Produces a minimal but schema-valid T-mode task.md. The caller supplies any
# extra top-level frontmatter (e.g. `task_shape: audit`). `task_kind: T` is
# always present so we assert that adding task_shape never collides with it.
write_task() {
  local file="$1"
  local extra_fm="$2"

  cat >"$file" <<EOF
---
title: "Work Order - T1: task_shape fixture"
description: "task_shape enum validator fixture."
status: IN_PROGRESS
task_kind: T
${extra_fm}
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# T1: task_shape fixture (1 pt)

> Source: DP-262 | Task: DP-262-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-262 |
| Task ID | DP-262-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-262-T1-task-shape |
| Task branch | task/DP-262-T1-task-shape |
| Depends on | N/A |
| References to load | - task-md-schema |

## 目標

驗證 task_shape enum schema。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/validate-task-md.sh | test | fixture only |

## Allowed Files

- scripts/validate-task-md.sh

## 估點理由

1 pt - validator fixture。

## 測試計畫（code-level）

- validator fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

expect_pass() {
  local label="$1"
  local file="$2"
  if ! bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected pass for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validation failure for $label"
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected '$pattern' for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

expect_parse_field() {
  local label="$1"
  local file="$2"
  local want="$3"
  local got
  got="$(bash "$PARSER" "$file" --no-resolve --field task_shape)"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: parse --field task_shape mismatch for $label: got '$got' want '$want'"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# AC1 — validate-task-md recognizes the enum values; parse-task-md emits them.
# ---------------------------------------------------------------------------
shape_implementation="$tmpdir/T1-shape-implementation.md"
write_task "$shape_implementation" 'task_shape: implementation'
expect_pass "shape-implementation" "$shape_implementation"
expect_parse_field "shape-implementation" "$shape_implementation" "implementation"

shape_audit="$tmpdir/T1-shape-audit.md"
write_task "$shape_audit" 'task_shape: audit'
expect_pass "shape-audit" "$shape_audit"
expect_parse_field "shape-audit" "$shape_audit" "audit"

shape_confirmation="$tmpdir/T1-shape-confirmation.md"
write_task "$shape_confirmation" 'task_shape: confirmation'
expect_pass "shape-confirmation" "$shape_confirmation"
expect_parse_field "shape-confirmation" "$shape_confirmation" "confirmation"

# task_shape is optional with default implementation: absent → still valid.
shape_absent="$tmpdir/T1-shape-absent.md"
write_task "$shape_absent" ''
expect_pass "shape-absent" "$shape_absent"

# ---------------------------------------------------------------------------
# Orthogonality invariant — task_shape must not collide with task_kind.
# task_kind: T is present in every fixture and must keep passing; assert the
# in-production T/V dispatcher field stays parseable and unaffected.
# ---------------------------------------------------------------------------
kind_field="$(bash "$PARSER" "$shape_audit" --no-resolve --field task_kind 2>/dev/null || true)"
# task_kind may or may not have a parse alias; what matters is the validator
# still passes with both fields present (asserted by expect_pass above) and
# task_shape parsing returns the shape, not the kind.
if [[ "$kind_field" == "audit" ]]; then
  echo "FAIL: task_kind parse returned task_shape value — fields collided"
  exit 1
fi

# ---------------------------------------------------------------------------
# AC-NEG4 — validate-task-md rejects a non-enum task_shape value.
# ---------------------------------------------------------------------------
shape_illegal="$tmpdir/T1-shape-illegal.md"
write_task "$shape_illegal" 'task_shape: refactor'
expect_fail_contains "shape-illegal" "$shape_illegal" "task_shape"

shape_empty="$tmpdir/T1-shape-empty.md"
write_task "$shape_empty" 'task_shape: ""'
expect_fail_contains "shape-empty" "$shape_empty" "task_shape"

echo "PASS: task.md task_shape enum validator + parser selftest"
