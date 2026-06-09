#!/usr/bin/env bash
# Purpose: Selftest for the DP-274 D4 delivery-unit shape gate in
#          validate-breakdown-ready.sh (and its LOCK-time delegate
#          validate-refinement-lock-preflight.sh). Covers AC2 (research-unit /
#          dispatch-theme-unit fail-stop at breakdown with a POLARIS_* marker),
#          AC6 (gate banks on the existing task_shape classifier — no second
#          classifier / no extra full-file rescan), and AC-NEG1 (a legitimate
#          implementation DP that also carries audit/confirmation tasks, per the
#          DP-262 carve-out, must NOT be flagged as a research unit).
# Inputs:  none (builds tmpdir DP-backed folder-native task fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"
LOCK_PREFLIGHT="$ROOT_DIR/scripts/validate-refinement-lock-preflight.sh"

tmpdir="$(mktemp -d -t validate-breakdown-ready-research-dispatch-unit-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_task <tasks_dir> <task_id> <task_shape> <allowed_block>
# Produces a DP-backed folder-native T{n}/index.md whose body passes the base
# readiness gate (schema + Scope Trace Matrix + Gate Closure Matrix). The caller
# supplies the task_shape (or empty for the implementation default) and the body
# of the Allowed Files section. audit/confirmation shapes use a specs-only entry
# (the legitimate carve-out form); implementation uses a tracked script entry.
write_task() {
  local tasks_dir="$1"
  local task_id="$2"
  local task_shape="$3"
  local allowed_entry="$4"
  local owning_file="$5"
  local dir="$tasks_dir/$task_id"
  local file="$dir/index.md"
  mkdir -p "$dir"

  local shape_fm=""
  if [[ -n "$task_shape" ]]; then
    shape_fm="task_shape: $task_shape"
  fi

  cat >"$file" <<EOF
---
title: "Work Order - ${task_id}: D4 delivery-unit shape fixture"
description: "validate-breakdown-ready D4 delivery-unit shape selftest fixture."
status: IN_PROGRESS
task_kind: T
${shape_fm}
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# ${task_id}: D4 delivery-unit shape fixture (1 pt)

> Source: DP-274 | Task: DP-274-${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-274 |
| Task ID | DP-274-${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-274-${task_id}-fixture |
| Task branch | task/DP-274-${task_id}-fixture |
| Depends on | N/A |
| References to load | - refinement.json |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

D4 delivery-unit shape fixture for ${task_id}.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| ${owning_file} | modify | fixture deliverable |

## Allowed Files

- ${allowed_entry}

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| fixture deliverable proof | ${owning_file} | framework deterministic gate | bash scripts/validate-breakdown-ready.sh fixture |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | gate pass | breakdown |
| verify | yes | gate pass | breakdown |
| ci-local | no | N/A - no repo CI required | breakdown |

## 估點理由

1 pt - D4 fixture。

## 測試計畫（code-level）

- gate fixture。

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

IMPL_ENTRY="scripts/dp274-fixture.sh"
SPEC_ENTRY="docs-manager/src/content/docs/specs/design-plans/DP-274-example/index.md"

# run_validator_expect_exit <expected_rc> <label> <tasks_dir>
# Runs validate-breakdown-ready against a directory target and asserts the exit
# code. On a non-match it prints captured stderr and fails the selftest.
run_validator_expect_exit() {
  local expected="$1" label="$2" dir="$3" err rc
  err="$tmpdir/$label.err"
  set +e
  bash "$VALIDATOR" "$dir" >/dev/null 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "[selftest] FAIL ($label): expected exit $expected, got $rc" >&2
    cat "$err" >&2
    return 1
  fi
}

# assert_marker <label> <marker>
# Asserts the captured stderr from the matching run contains the POLARIS_* marker.
assert_marker() {
  local label="$1" marker="$2"
  if ! grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): expected marker '$marker' in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

fail=0

# --- Case 1 (AC2 positive): legit implementation DP -> exit 0 ---------------
pos_dir="$tmpdir/positive/tasks"
write_task "$pos_dir" "T1" "implementation" "$IMPL_ENTRY" "$IMPL_ENTRY"
write_task "$pos_dir" "T2" "implementation" "$IMPL_ENTRY" "$IMPL_ENTRY"
run_validator_expect_exit 0 "positive" "$pos_dir" || fail=1

# --- Case 2 (AC2): research unit (all audit, no implementation) -> exit 2 ----
research_dir="$tmpdir/research/tasks"
write_task "$research_dir" "T1" "audit" "$SPEC_ENTRY" "$SPEC_ENTRY"
write_task "$research_dir" "T2" "audit" "$SPEC_ENTRY" "$SPEC_ENTRY"
run_validator_expect_exit 2 "research" "$research_dir" || fail=1
assert_marker "research" "POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION" || fail=1

# --- Case 3 (AC2): dispatch/theme unit (no implementation, confirmation/mix) -> exit 2 ---
dispatch_dir="$tmpdir/dispatch/tasks"
write_task "$dispatch_dir" "T1" "confirmation" "$SPEC_ENTRY" "$SPEC_ENTRY"
write_task "$dispatch_dir" "T2" "audit" "$SPEC_ENTRY" "$SPEC_ENTRY"
run_validator_expect_exit 2 "dispatch" "$dispatch_dir" || fail=1
assert_marker "dispatch" "POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION" || fail=1

# --- Case 4 (AC-NEG1): mixed-task DP (implementation + audit, DP-262 carve-out) -> exit 0 ---
mixed_dir="$tmpdir/mixed/tasks"
write_task "$mixed_dir" "T1" "implementation" "$IMPL_ENTRY" "$IMPL_ENTRY"
write_task "$mixed_dir" "T2" "audit" "$SPEC_ENTRY" "$SPEC_ENTRY"
write_task "$mixed_dir" "T3" "confirmation" "$SPEC_ENTRY" "$SPEC_ENTRY"
run_validator_expect_exit 0 "mixed" "$mixed_dir" || fail=1

# --- Case 5 (AC2 LOCK-time delegation): research unit blocked at LOCK preflight -> exit 2 ---
# validate-refinement-lock-preflight.sh delegates the same D4 detection. A
# refinement.json whose canonical tasks[] are all audit (no implementation) must
# fail-stop at LOCK with the research-unit marker, not just at breakdown.
# DP-296 T3 migrated the preflight to read the canonical tasks[] shape (entry key
# `id`, first-class `task_shape` / `tracked_deliverable_hint`); the legacy
# top-level planned-task array read is gone, so this fixture uses tasks[].
research_json="$tmpdir/research-lock.json"
cat >"$research_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-274" },
  "tasks": [
    { "id": "T1", "task_shape": "audit", "tracked_deliverable_hint": "specs_only" },
    { "id": "T2", "task_shape": "audit", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
set +e
bash "$LOCK_PREFLIGHT" "$research_json" >/dev/null 2>"$tmpdir/research-lock.err"
lock_rc=$?
set -e
if [[ "$lock_rc" -ne 2 ]]; then
  echo "[selftest] FAIL (research-lock): expected LOCK preflight exit 2, got $lock_rc" >&2
  cat "$tmpdir/research-lock.err" >&2
  fail=1
elif ! grep -q "POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION" "$tmpdir/research-lock.err"; then
  echo "[selftest] FAIL (research-lock): expected research-unit marker in LOCK preflight stderr" >&2
  cat "$tmpdir/research-lock.err" >&2
  fail=1
fi

# --- Case 6 (AC-NEG1 LOCK-time): mixed tasks[] at LOCK -> exit 0 -------------
mixed_json="$tmpdir/mixed-lock.json"
cat >"$mixed_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-274" },
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" },
    { "id": "T2", "task_shape": "audit", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
if ! bash "$LOCK_PREFLIGHT" "$mixed_json" >/dev/null 2>"$tmpdir/mixed-lock.err"; then
  echo "[selftest] FAIL (mixed-lock): expected LOCK preflight to PASS for mixed tasks[]" >&2
  cat "$tmpdir/mixed-lock.err" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "validate-breakdown-ready research/dispatch-unit selftest FAIL" >&2
  exit 1
fi

echo "validate-breakdown-ready research/dispatch-unit selftest PASS"
