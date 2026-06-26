#!/usr/bin/env bash
# Purpose: Selftest for the DP-324 T1 vacuous-pass guard in
#          validate-breakdown-ready.sh. The validator previously printed PASS
#          silently for two empty inputs: (a) a single-file target whose path
#          does not resolve to a recognized task id (loose .md, e.g. /tmp/foo.md)
#          and is not under tasks/pr-release/ or /archive/, and (b) a directory
#          target whose task-file glob yields 0 recognized task files. Both must
#          now fail-closed (exit 2 + POLARIS_VACUOUS_PASS) without printing PASS.
#          Covers AC1 (loose single-file fail-closed), AC2 (zero-task dir
#          fail-closed), and AC-NEG1 (carve-out regressions: pr-release/archive
#          per-file skip, audit/confirmation specs-only Allowed Files, and a
#          real T{n}/index.md placeholder of the shape the lock-preflight
#          synthesizes all keep their prior PASS / exit behavior, never tripping
#          the new guard).
# Inputs:  none (builds tmpdir fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"

VACUOUS_PASS_MARKER="POLARIS_VACUOUS_PASS"

tmpdir="$(mktemp -d -t validate-breakdown-ready-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail=0

# write_task <dir> <task_id> <task_shape> <allowed_entry> <owning_file>
# Produces a DP-backed folder-native T{n}/index.md whose body passes the base
# readiness gate. An empty task_shape yields the implementation default; an
# audit/confirmation shape pairs with a specs-only Allowed Files entry (the
# legitimate carve-out form).
write_task() {
  local dir="$1" task_id="$2" task_shape="$3" allowed_entry="$4" owning_file="$5"
  local target_dir="$dir/$task_id"
  local file="$target_dir/index.md"
  mkdir -p "$target_dir"

  local shape_fm=""
  if [[ -n "$task_shape" ]]; then
    shape_fm="task_shape: $task_shape"
  fi

  cat >"$file" <<EOF
---
title: "Work Order - ${task_id}: vacuous-pass guard fixture"
description: "validate-breakdown-ready vacuous-pass guard selftest fixture."
status: IN_PROGRESS
task_kind: T
${shape_fm}
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# ${task_id}: vacuous-pass guard fixture (1 pt)

> Source: DP-324 | Task: DP-324-${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-324 |
| Task ID | DP-324-${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | feat/DP-324 |
| Branch chain | feat/DP-324 -> task/DP-324-${task_id}-fixture |
| Task branch | task/DP-324-${task_id}-fixture |
| Depends on | N/A |
| References to load | - refinement.json |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

vacuous-pass guard fixture for ${task_id}.

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

1 pt - vacuous-pass guard fixture。

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

IMPL_ENTRY="scripts/dp324-fixture.sh"
SPEC_ENTRY="docs-manager/src/content/docs/specs/design-plans/DP-324-example/index.md"

# run_validator_expect_exit <expected_rc> <label> <target>
# Runs the validator against a file or directory target, captures stdout+stderr,
# and asserts the exit code. On mismatch prints the captured output and fails.
run_validator_expect_exit() {
  local expected="$1" label="$2" target="$3" rc
  local out="$tmpdir/$label.out" err="$tmpdir/$label.err"
  set +e
  bash "$VALIDATOR" "$target" >"$out" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "[selftest] FAIL ($label): expected exit $expected, got $rc" >&2
    echo "--- stdout ---" >&2
    cat "$out" >&2
    echo "--- stderr ---" >&2
    cat "$err" >&2
    return 1
  fi
}

# assert_marker <label> <marker>
# Asserts the captured stderr contains the POLARIS_* marker.
assert_marker() {
  local label="$1" marker="$2"
  if ! grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): expected marker '$marker' in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

# assert_no_pass_line <label>
# Asserts the validator did NOT print its PASS line for a fail-closed input.
assert_no_pass_line() {
  local label="$1"
  if grep -q "validate-breakdown-ready.sh PASS" "$tmpdir/$label.out"; then
    echo "[selftest] FAIL ($label): validator printed PASS for a vacuous input" >&2
    cat "$tmpdir/$label.out" >&2
    return 1
  fi
}

# --- Case 1 (AC1): loose single-file, no resolvable task id -> exit 2 ----------
# A target that exists but whose basename is not T{n}.md / T{n}/index.md and is
# not under pr-release/ or /archive/ must fail-closed, not silently PASS.
loose_file="$tmpdir/foo.md"
cat >"$loose_file" <<'MD'
# Just some markdown, not a task work order.
MD
run_validator_expect_exit 2 "loose-file" "$loose_file" || fail=1
assert_marker "loose-file" "$VACUOUS_PASS_MARKER" || fail=1
assert_no_pass_line "loose-file" || fail=1

# --- Case 2 (AC2): directory target with 0 recognized task files -> exit 2 -----
# A tasks/ directory that only contains non-task .md files (no T{n}.md /
# T{n}/index.md) yields an empty glob and must fail-closed.
zero_dir="$tmpdir/zero/tasks"
mkdir -p "$zero_dir"
cat >"$zero_dir/README.md" <<'MD'
# Not a task file.
MD
cat >"$zero_dir/notes.md" <<'MD'
# Also not a task file.
MD
run_validator_expect_exit 2 "zero-dir" "$zero_dir" || fail=1
assert_marker "zero-dir" "$VACUOUS_PASS_MARKER" || fail=1
assert_no_pass_line "zero-dir" || fail=1

# --- Case 2b (AC2): completely empty directory -> exit 2 ----------------------
empty_dir="$tmpdir/empty/tasks"
mkdir -p "$empty_dir"
run_validator_expect_exit 2 "empty-dir" "$empty_dir" || fail=1
assert_marker "empty-dir" "$VACUOUS_PASS_MARKER" || fail=1

# --- Case 3 (AC-NEG1): recognized single-file task still PASSes ----------------
# A valid implementation T{n}/index.md must keep exit 0; the guard only fires for
# UNrecognized targets.
neg_pass_dir="$tmpdir/neg-pass/tasks"
write_task "$neg_pass_dir" "T1" "implementation" "$IMPL_ENTRY" "$IMPL_ENTRY"
run_validator_expect_exit 0 "neg-pass-single" "$neg_pass_dir/T1/index.md" || fail=1

# --- Case 4 (AC-NEG1): recognized directory task still PASSes ------------------
run_validator_expect_exit 0 "neg-pass-dir" "$neg_pass_dir" || fail=1

# --- Case 5 (AC-NEG1): pr-release/ single-file skip preserved ------------------
# A task.md under tasks/pr-release/ is intentionally skipped per-file (it carries
# a delivered closeout artifact). Targeting it directly must NOT trip the guard:
# it stays exit 0 (skipped, no errors), matching the prior behavior.
pr_release_dir="$tmpdir/pr-release-case/tasks/pr-release"
mkdir -p "$pr_release_dir"
cp "$neg_pass_dir/T1/index.md" "$pr_release_dir/T1.md"
run_validator_expect_exit 0 "pr-release-skip" "$pr_release_dir/T1.md" || fail=1

# --- Case 6 (AC-NEG1): /archive/ single-file skip preserved -------------------
archive_dir="$tmpdir/archive-case/archive/tasks"
mkdir -p "$archive_dir"
cp "$neg_pass_dir/T1/index.md" "$archive_dir/T1.md"
run_validator_expect_exit 0 "archive-skip" "$archive_dir/T1.md" || fail=1

# --- Case 7 (AC-NEG1): audit task with specs-only Allowed Files still PASSes ---
# The DP-262 carve-out: audit/confirmation tasks may declare specs-only Allowed
# Files. A recognized audit task must keep its prior exit, untouched by the guard.
audit_dir="$tmpdir/audit/tasks"
write_task "$audit_dir" "T1" "audit" "$SPEC_ENTRY" "$SPEC_ENTRY"
run_validator_expect_exit 0 "audit-single" "$audit_dir/T1/index.md" || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo "validate-breakdown-ready vacuous-pass guard selftest FAIL" >&2
  exit 1
fi

echo "validate-breakdown-ready vacuous-pass guard selftest PASS"
