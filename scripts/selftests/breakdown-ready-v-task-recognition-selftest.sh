#!/usr/bin/env bash
# Purpose: Selftest for validate-breakdown-ready.sh V-task recognition (DP-371 T2).
#          task_id_for_file() must resolve V{n}.md and V{n}/index.md to a V-task
#          id, symmetric to the existing T{n} branches, so the DP-324 vacuous-pass
#          guard no longer false-fires on a V-task target. The bug: a V-task is a
#          first-class Polaris task id, yet task_id_for_file() returned None for
#          it, so a bare V1/index.md single-file target tripped POLARIS_VACUOUS_PASS
#          (DP-324 T1 guard, validate-breakdown-ready.sh L1323-1330), and the
#          lock-preflight (which synthesizes one placeholder $tmpdir/V{n}/index.md
#          per V-task and runs validate-breakdown-ready against it) failed for any
#          DP that plans a V-task.
#
# Unit under change: task_id_for_file() — the recognized-task-id resolver that the
#   DP-324 vacuous-pass guard consults. The guard fires POLARIS_VACUOUS_PASS only
#   when the resolver returns None for a single-file / directory target. So the
#   precise, deterministic assertion is: a V-named target is recognized (the
#   vacuous-pass marker no longer fires), while a genuinely-unrecognized name
#   (non-T/V) still trips it. A recognized-but-schema-incomplete target produces a
#   DIFFERENT downstream error (NOT POLARIS_VACUOUS_PASS), which is exactly the
#   recognition boundary this fix moves.
#
# Covers:
#   AC-B1   — V{n}/index.md and V{n}.md are recognized; the vacuous-pass guard no
#             longer fires for them.
#   AC-B2   — genuinely-unrecognized filenames (notes.md / X9/index.md, non-T/V
#             patterns) still trip POLARIS_VACUOUS_PASS (the fix must not weaken
#             the guard).
#   AC-NEG2 — existing T-task recognition is unchanged: T1/index.md still resolves
#             to T1 (full-PASS, never vacuous-pass); a directory target holding
#             T1+V1 is still breakdown-ready.
#
# Inputs:  none (builds tmpdir fixtures; hermetic)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"
VACUOUS_PASS_MARKER="POLARIS_VACUOUS_PASS"

tmpdir="$(mktemp -d -t breakdown-ready-v-task-recognition-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_t_task <dir> <task_id> — schema-valid, breakdown-ready T-task.md at
# <dir>/index.md (task_kind: T body shape). Used for full-PASS regression cases.
write_t_task() {
  local dir="$1"
  local task_id="$2"
  mkdir -p "$dir"
  cat >"$dir/index.md" <<EOF
---
title: "Work Order - ${task_id}: V-task recognition fixture"
description: "validate-breakdown-ready V-task recognition selftest fixture."
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# ${task_id}: V-task recognition fixture (1 pt)

> Source: DP-371 | Task: DP-371-${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-371 |
| Task ID | DP-371-${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | feat/DP-371 |
| Task branch | task/DP-371-${task_id}-fixture |
| References to load | - refinement.json |
| Depends on | N/A |

## 目標

V-task recognition fixture body。

## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
| scripts/${task_id}-fixture.sh | create | fixture |

## Allowed Files

- scripts/${task_id}-fixture.sh

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| AC-1 | scripts/${task_id}-fixture.sh | framework deterministic gate | bash scripts/${task_id}-fixture.sh |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files all match Allowed Files | engineering |
| test | yes | bash scripts/${task_id}-fixture.sh PASS | engineering |
| verify | yes | bash scripts/${task_id}-fixture.sh PASS | engineering |
| ci-local | no | N/A framework repo has no ci-local | engineering |

## 估點理由

1 pt — fixture。

## 測試計畫（code-level）

1. fixture。

## Test Command

\`\`\`bash
bash scripts/${task_id}-fixture.sh
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
EOF
}

# write_minimal_index <dir> — writes a minimal index.md (no schema body) at
# <dir>/index.md. Used to probe the recognition boundary: the file's PATH alone
# determines whether task_id_for_file recognizes it; a recognized target gets PAST
# the vacuous-pass guard (failing later on schema, a DIFFERENT error), while an
# unrecognized target trips POLARIS_VACUOUS_PASS at the guard.
write_minimal_index() {
  local dir="$1"
  mkdir -p "$dir"
  printf '%s\n' '# placeholder' >"$dir/index.md"
}

# assert_recognized <label> <target> — target must be recognized: the
# vacuous-pass guard must NOT fire (the recognition boundary moved). The target
# may still fail downstream on schema (that is fine and expected for a minimal
# fixture); the only forbidden outcome is POLARIS_VACUOUS_PASS.
assert_recognized() {
  local label="$1"
  local target="$2"
  bash "$VALIDATOR" "$target" >/dev/null 2>"$tmpdir/$label.err" || true
  if grep -q "$VACUOUS_PASS_MARKER" "$tmpdir/$label.err"; then
    echo "FAIL: $label — expected recognized (no $VACUOUS_PASS_MARKER), but vacuous-pass guard fired"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

# assert_vacuous_pass <label> <target> — target must be unrecognized: the
# vacuous-pass guard MUST fire with POLARIS_VACUOUS_PASS.
assert_vacuous_pass() {
  local label="$1"
  local target="$2"
  if bash "$VALIDATOR" "$target" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: $label — expected FAIL (vacuous-pass), but validator passed"
    exit 1
  fi
  if ! grep -q "$VACUOUS_PASS_MARKER" "$tmpdir/$label.err"; then
    echo "FAIL: $label — expected '$VACUOUS_PASS_MARKER' in stderr"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

# assert_pass <label> <target> — target must fully PASS breakdown-ready.
assert_pass() {
  local label="$1"
  local target="$2"
  if ! bash "$VALIDATOR" "$target" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: $label — expected full PASS"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# AC-B1 — V-named targets are recognized (vacuous-pass guard no longer fires).
# RED before the fix: V1/index.md and a dir holding V1.md trip POLARIS_VACUOUS_PASS
# because task_id_for_file returns None for V-tasks.
# ---------------------------------------------------------------------------

# V{n}/index.md single-file → recognized (no vacuous-pass).
v_index_dir="$tmpdir/v-index/V1"
write_minimal_index "$v_index_dir"
assert_recognized "v-index-single-file" "$v_index_dir/index.md"

# V{n} with a multi-letter suffix (V2a) → recognized (symmetric to T{n}[a-z]*).
v_suffix_dir="$tmpdir/v-suffix/V2a"
write_minimal_index "$v_suffix_dir"
assert_recognized "v-suffix-single-file" "$v_suffix_dir/index.md"

# Directory target holding a flat V{n}.md → recognized (the dir scan finds V1.md).
v_flat_dir="$tmpdir/v-flat"
mkdir -p "$v_flat_dir"
printf '%s\n' '# placeholder' >"$v_flat_dir/V1.md"
assert_recognized "v-flat-file-dir" "$v_flat_dir"

# ---------------------------------------------------------------------------
# AC-B2 — genuinely-unrecognized filenames still trip POLARIS_VACUOUS_PASS.
# The fix must not weaken the guard for non-T/V patterns.
# ---------------------------------------------------------------------------

# notes.md flat single-file → unrecognized → vacuous-pass FAIL.
notes_dir="$tmpdir/notes-case"
mkdir -p "$notes_dir"
printf '%s\n' '# placeholder' >"$notes_dir/notes.md"
assert_vacuous_pass "notes-md-unrecognized" "$notes_dir/notes.md"

# X9/index.md (non-T/V folder) single-file → unrecognized → vacuous-pass FAIL.
x9_dir="$tmpdir/x9-case/X9"
write_minimal_index "$x9_dir"
assert_vacuous_pass "x9-index-unrecognized" "$x9_dir/index.md"

# Directory target whose only files are unrecognized → vacuous-pass FAIL.
unrec_dir="$tmpdir/unrec-dir"
mkdir -p "$unrec_dir"
printf '%s\n' '# placeholder' >"$unrec_dir/notes.md"
assert_vacuous_pass "unrecognized-dir" "$unrec_dir"

# ---------------------------------------------------------------------------
# AC-NEG2 — existing T-task behavior unchanged.
# ---------------------------------------------------------------------------

# T1/index.md single-file still resolves to T1 and fully PASSES (not vacuous-pass).
t_index_dir="$tmpdir/t-index/T1"
write_t_task "$t_index_dir" T1
assert_pass "t-index-single-file" "$t_index_dir/index.md"

# Directory target holding a recognized T1 (plus a recognized V1) → recognized;
# the dir scan finds at least one recognized task file, so the guard does not fire.
mixed_dir="$tmpdir/mixed"
write_t_task "$mixed_dir/T1" T1
write_minimal_index "$mixed_dir/V1"
assert_recognized "mixed-t1-v1-dir" "$mixed_dir"

echo "PASS: validate-breakdown-ready V-task recognition selftest"
