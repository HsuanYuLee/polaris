#!/usr/bin/env bash
# Purpose: Selftest for validate-breakdown-ready.sh task_shape carve-out (DP-262 T2).
#          Covers AC2 (audit/confirmation DP-backed tasks may declare specs-only
#          Allowed Files without the specs-only rejection firing) and AC-NEG1
#          (implementation — incl. the missing-field default — keeps failing on
#          specs-only Allowed Files; the carve-out must not overflow to
#          implementation).
#
# Note on "empty Allowed Files" (AC2): for a T-mode task.md the schema gate
# (validate-task-md.sh, DP-262 T1 / DP-033 D5) hard-requires a non-empty
# ## Allowed Files bullet list with no grace, so a truly-empty section is not
# schema-valid and cannot reach validate-breakdown-ready's own checks. The
# realizable carve-out form for a T task is therefore specs-only Allowed Files,
# which this selftest exercises. validate-breakdown-ready additionally relaxes
# its own "no entries" check for carve-out shapes (see CARVE_OUT_TASK_SHAPES) so
# the breakdown-ready layer contributes no spurious empty-entry error.
# Inputs:  none (builds tmpdir DP-backed task.md fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"

tmpdir="$(mktemp -d -t validate-breakdown-ready-task-shape-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_task <task_id> <task_shape_fm_line> <allowed_block>
# Produces a DP-backed task.md (folder-native T{n}/index.md so that
# validate-breakdown-ready's task_id_for_file recognizes it) whose body passes
# the base readiness gate (schema + Scope Trace Matrix + Gate Closure Matrix).
# The caller supplies the optional `task_shape:` frontmatter line and the body
# of the Allowed Files section (which may be a specs-only entry, or empty).
# Echoes the created index.md path on stdout.
write_task() {
  local task_id="$1"
  local shape_fm="$2"
  local allowed_block="$3"
  local dir="$tmpdir/$task_id"
  local file="$dir/index.md"
  mkdir -p "$dir"

  cat >"$file" <<EOF
---
title: "Work Order - T1: task_shape carve-out fixture"
description: "validate-breakdown-ready task_shape carve-out fixture."
status: IN_PROGRESS
task_kind: T
${shape_fm}
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# T1: task_shape carve-out fixture (1 pt)

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

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

驗證 task_shape carve-out。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md | modify | spec recut |

## Allowed Files
${allowed_block}
## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| spec recut proof | docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md | local spec surface | bash scripts/validate-breakdown-ready.sh fixture |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | selftest pass | breakdown |
| verify | yes | smoke pass | breakdown |
| ci-local | no | N/A - no repo CI required | breakdown |

## 估點理由

1 pt - carve-out fixture。

## 測試計畫（code-level）

- carve-out fixture。

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

  printf '%s\n' "$file"
}

# A specs-only Allowed Files block: the single entry lives under
# docs-manager/src/content/docs/specs and is also the Scope Trace owning file.
SPECS_ONLY_ALLOWED='
- docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md
'

expect_pass() {
  local label="$1"
  local file="$2"
  if ! bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validate-breakdown-ready pass for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validate-breakdown-ready failure for $label"
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected '$pattern' in stderr for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# AC2 — task_shape ∈ {audit, confirmation} relaxes the specs-only rejection.
# ---------------------------------------------------------------------------

# AC2-a: audit + specs-only Allowed Files → PASS.
audit_specs_only="$(write_task T1 'task_shape: audit' "$SPECS_ONLY_ALLOWED")"
expect_pass "audit-specs-only" "$audit_specs_only"

# AC2-b: confirmation + specs-only Allowed Files → PASS.
confirmation_specs_only="$(write_task T2 'task_shape: confirmation' "$SPECS_ONLY_ALLOWED")"
expect_pass "confirmation-specs-only" "$confirmation_specs_only"

# ---------------------------------------------------------------------------
# AC-NEG1 — implementation (incl. missing field default) keeps failing on
# specs-only Allowed Files. The carve-out must not overflow to implementation.
# ---------------------------------------------------------------------------

# AC-NEG1-a: explicit task_shape: implementation + specs-only → FAIL.
implementation_specs_only="$(write_task T3 'task_shape: implementation' "$SPECS_ONLY_ALLOWED")"
expect_fail_contains "implementation-specs-only" "$implementation_specs_only" \
  "only local spec/sample artifacts"

# AC-NEG1-b: missing task_shape (default implementation) + specs-only → FAIL.
default_specs_only="$(write_task T4 '' "$SPECS_ONLY_ALLOWED")"
expect_fail_contains "default-specs-only" "$default_specs_only" \
  "only local spec/sample artifacts"

echo "PASS: validate-breakdown-ready task_shape carve-out selftest"
