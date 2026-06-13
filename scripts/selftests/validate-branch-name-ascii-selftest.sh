#!/usr/bin/env bash
# Purpose: selftest for the DP-307 T2 branch-name ASCII gate —
#   scripts/validate-branch-name-ascii.sh must fail-close (exit 2 +
#   POLARIS_BRANCH_NAME_NON_ASCII) on any non-ASCII byte in a branch name,
#   must NOT false-block legal ASCII conventions (task/ slash, bundle dot,
#   hyphen, underscore), and scripts/validate-breakdown-ready.sh must inherit
#   the same fail-closed verdict for the task.md "Task branch" field.
# Inputs:  none (hermetic tmpdir fixtures; a throwaway git repo for the
#          check-ref-format comparison)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# AC coverage (DP-307):
#   AC3     : CJK branch name -> validator exit 2 + marker.
#   AC4     : task.md "Task branch" with CJK -> validate-breakdown-ready
#             fail-closed (exit 2 + marker); ASCII -> PASS.
#   AC-NEG1 : legal ASCII branch conventions (task/ slash, bundle-DP-NNN
#             dot, hyphen, underscore) -> exit 0, zero false-block.
#   AC-NEG5 : side-by-side proof — git check-ref-format --branch accepts the
#             same CJK name (exit 0) while the validator exits 2, so
#             check-ref-format cannot serve as the sole gate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-branch-name-ascii.sh"
READINESS="$ROOT_DIR/scripts/validate-breakdown-ready.sh"

[[ -f "$VALIDATOR" ]] || { echo "FAIL: validator missing: $VALIDATOR" >&2; exit 1; }
[[ -f "$READINESS" ]] || { echo "FAIL: validate-breakdown-ready.sh missing: $READINESS" >&2; exit 1; }

tmpdir="$(mktemp -d -t branch-name-ascii.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

CJK_BRANCH='task/DP-231-T9-d39-engineering-no-bypass-固定點'

# ---------------------------------------------------------------------------
# Case 1 (AC3): CJK branch name -> exit 2 + POLARIS_BRANCH_NAME_NON_ASCII.
# ---------------------------------------------------------------------------
set +e
c1_err="$(bash "$VALIDATOR" "$CJK_BRANCH" 2>&1 >/dev/null)"
c1_rc=$?
set -e
if [[ "$c1_rc" -ne 2 ]]; then
  echo "FAIL [case 1 / AC3]: CJK branch must exit 2 (got rc=$c1_rc)" >&2
  exit 1
fi
if ! grep -q "POLARIS_BRANCH_NAME_NON_ASCII:$CJK_BRANCH" <<<"$c1_err"; then
  echo "FAIL [case 1 / AC3]: stderr missing POLARIS_BRANCH_NAME_NON_ASCII:{branch} marker" >&2
  printf '%s\n' "$c1_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 2 (AC-NEG1): legal ASCII conventions -> exit 0, zero false-block.
# task/ slash, bundle-DP-NNN-vX.Y.Z dot, hyphen, underscore all stay legal.
# ---------------------------------------------------------------------------
ascii_branches=(
  'task/DP-307-T2-branch-name-ascii-validator'
  'bundle-DP-305-v3.76.5'
  'feat/some_branch_name-x2'
)
for branch in "${ascii_branches[@]}"; do
  if ! bash "$VALIDATOR" "$branch" >/dev/null; then
    echo "FAIL [case 2 / AC-NEG1]: legal ASCII branch was falsely blocked: $branch" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG5): side-by-side — git check-ref-format --branch accepts the
# SAME CJK name (exit 0) while the validator exits 2. This proves
# check-ref-format cannot be the sole gate and the validator may not
# delegate to it (D3).
# ---------------------------------------------------------------------------
gitrepo="$tmpdir/gitrepo"
mkdir -p "$gitrepo"
git -C "$gitrepo" init -q
if ! git -C "$gitrepo" check-ref-format --branch "$CJK_BRANCH" >/dev/null; then
  echo "FAIL [case 3 / AC-NEG5]: expected git check-ref-format --branch to ACCEPT the CJK name; premise broken" >&2
  exit 1
fi
set +e
bash "$VALIDATOR" "$CJK_BRANCH" >/dev/null 2>&1
c3_rc=$?
set -e
if [[ "$c3_rc" -ne 2 ]]; then
  echo "FAIL [case 3 / AC-NEG5]: validator must exit 2 on the same CJK name check-ref-format accepted (got rc=$c3_rc)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture: a task.md that fully passes validate-breakdown-ready (mirrors the
# validator's own --self-test valid fixture) with an ASCII Task branch.
# ---------------------------------------------------------------------------
mkdir -p "$tmpdir/tasks"
ascii_task="$tmpdir/tasks/T1.md"
cat >"$ascii_task" <<'MD'
---
title: "T1: 建立 branch-name ascii fixture (2 pt)"
status: PLANNED
---

# T1: 建立 branch-name ascii fixture (2 pt)

> Source: DP-082 | Task: DP-082-T1 | JIRA: N/A | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-082 |
| Task ID | DP-082-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-082-T1-breakdown-readiness-gate |
| References to load | - `.claude/skills/references/task-md-schema.md` |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

新增 breakdown readiness gate。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/validate-breakdown-ready.sh` | create | readiness gate |

## Allowed Files

- `scripts/validate-breakdown-ready.sh`
- `scripts/validate-breakdown-ready-selftest.sh`
- `VERSION`

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| readiness gate validates valid and invalid task.md files | `scripts/validate-breakdown-ready.sh`, `scripts/validate-breakdown-ready-selftest.sh` | CLI validator output | `bash scripts/validate-breakdown-ready.sh --self-test` |
| version bump is part of release metadata | `VERSION` | release metadata | `bash scripts/gates/gate-version-lint.sh --repo /tmp/repo` |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | selftest pass | breakdown |
| verify | yes | smoke pass | breakdown |
| ci-local | no | N/A | no repo CI required |

## 估點理由

2 pt，單一 validator 與 selftest。

## 測試計畫（code-level）

- selftest covers valid and invalid task.md。

## Test Command

```bash
echo test
```

## Test Environment

- **Level**: static
- **Dev env config**: `workspace-config.yaml` → `projects[work].dev_environment`
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo verify
```
MD

# ---------------------------------------------------------------------------
# Case 4 (AC3 task.md mode): validator reads the "Task branch" field itself.
# ASCII -> exit 0; CJK -> exit 2 + marker; missing field -> fail-closed.
# ---------------------------------------------------------------------------
if ! bash "$VALIDATOR" --task-md "$ascii_task" >/dev/null; then
  echo "FAIL [case 4]: --task-md with ASCII Task branch was falsely blocked" >&2
  exit 1
fi

mkdir -p "$tmpdir/cjk/tasks"
cjk_task="$tmpdir/cjk/tasks/T1.md"
sed 's|task/DP-082-T1-breakdown-readiness-gate|task/DP-082-T1-中文分支名|' "$ascii_task" >"$cjk_task"
set +e
c4_err="$(bash "$VALIDATOR" --task-md "$cjk_task" 2>&1 >/dev/null)"
c4_rc=$?
set -e
if [[ "$c4_rc" -ne 2 ]] || ! grep -q 'POLARIS_BRANCH_NAME_NON_ASCII:task/DP-082-T1-中文分支名' <<<"$c4_err"; then
  echo "FAIL [case 4]: --task-md with CJK Task branch must exit 2 with marker (got rc=$c4_rc)" >&2
  printf '%s\n' "$c4_err" >&2
  exit 1
fi

no_field_task="$tmpdir/no-field.md"
grep -v 'Task branch' "$ascii_task" >"$no_field_task"
set +e
c4b_err="$(bash "$VALIDATOR" --task-md "$no_field_task" 2>&1 >/dev/null)"
c4b_rc=$?
set -e
if [[ "$c4b_rc" -ne 2 ]] || ! grep -q "POLARIS_BRANCH_NAME_FIELD_MISSING:$no_field_task" <<<"$c4b_err"; then
  echo "FAIL [case 4]: missing Task branch field must fail-close with FIELD_MISSING marker (got rc=$c4b_rc)" >&2
  printf '%s\n' "$c4b_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 5 (AC4): validate-breakdown-ready inherits the gate on the task.md
# "Task branch" field — ASCII PASS, CJK fail-closed exit 2 + marker.
# ---------------------------------------------------------------------------
if ! bash "$READINESS" "$ascii_task" >/dev/null; then
  echo "FAIL [case 5 / AC4]: ASCII Task branch task.md was falsely blocked by validate-breakdown-ready" >&2
  bash "$READINESS" "$ascii_task" >&2 || true
  exit 1
fi

c5_err="$tmpdir/readiness-cjk.err"
set +e
bash "$READINESS" "$cjk_task" >/dev/null 2>"$c5_err"
c5_rc=$?
set -e
if [[ "$c5_rc" -ne 2 ]]; then
  echo "FAIL [case 5 / AC4]: CJK Task branch must make validate-breakdown-ready exit 2 (got rc=$c5_rc)" >&2
  cat "$c5_err" >&2
  exit 1
fi
if ! grep -q 'POLARIS_BRANCH_NAME_NON_ASCII:task/DP-082-T1-中文分支名' "$c5_err"; then
  echo "FAIL [case 5 / AC4]: validate-breakdown-ready stderr missing POLARIS_BRANCH_NAME_NON_ASCII marker" >&2
  cat "$c5_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 6 (AC4 directory mode): the same fail-closed verdict in directory scan
# (the shape validate-refinement-lock-preflight delegates into).
# ---------------------------------------------------------------------------
c6_err="$tmpdir/readiness-dir.err"
set +e
bash "$READINESS" "$tmpdir/cjk/tasks" >/dev/null 2>"$c6_err"
c6_rc=$?
set -e
if [[ "$c6_rc" -ne 2 ]] || ! grep -q 'POLARIS_BRANCH_NAME_NON_ASCII' "$c6_err"; then
  echo "FAIL [case 6 / AC4]: directory scan must exit 2 with marker on CJK Task branch (got rc=$c6_rc)" >&2
  cat "$c6_err" >&2
  exit 1
fi

echo "PASS: validate-branch-name-ascii selftest"
