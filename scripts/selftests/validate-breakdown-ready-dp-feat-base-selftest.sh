#!/usr/bin/env bash
# Purpose: Selftest for the DP-337 T2 delivery-boundary required gate in
#          validate-breakdown-ready.sh. When a dp-backed source enters breakdown
#          (a directory target resolvable to its sibling refinement.json), the
#          source MUST carry source.base_branch=feat/{source.id}. Covers AC3
#          (missing base_branch → fail-closed POLARIS_DP_FEAT_BASE_REQUIRED; a
#          feat/{id} base_branch → PASS) and AC-NEG3 (the required gate cannot be
#          silenced by POLARIS_* bypass env). The ~230 historical dp
#          refinement.json (base_branch=None) stay schema-optional at the
#          refinement-json layer (T1); the required enforcement only fires at the
#          delivery boundary here, i.e. when the source actually walks breakdown.
# Inputs:  none (builds tmpdir DP-backed source containers with refinement.json
#          + folder-native tasks/)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"

tmpdir="$(mktemp -d -t validate-breakdown-ready-dp-feat-base-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

FEAT_BASE_REQUIRED_MARKER="POLARIS_DP_FEAT_BASE_REQUIRED"
IMPL_ENTRY="scripts/dp337-fixture.sh"

# write_task <tasks_dir> <source_id> <task_id>
# Produces a DP-backed folder-native T{n}/index.md whose body passes the base
# readiness gate (schema + Scope Trace Matrix + Gate Closure Matrix). The
# implementation task carries a tracked script entry so the source is a
# legitimate delivery unit (>= 1 implementation task) and is not flagged by the
# unrelated D4 delivery-unit shape gate.
write_task() {
  local tasks_dir="$1"
  local source_id="$2"
  local task_id="$3"
  local dir="$tasks_dir/$task_id"
  local file="$dir/index.md"
  mkdir -p "$dir"

  cat >"$file" <<EOF
---
title: "Work Order - ${task_id}: DP-337 feat-base fixture"
description: "validate-breakdown-ready DP-337 delivery-boundary feat-base selftest fixture."
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# ${task_id}: DP-337 feat-base fixture (1 pt)

> Source: ${source_id} | Task: ${source_id}-${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | ${source_id} |
| Task ID | ${source_id}-${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | feat/${source_id} |
| Branch chain | feat/${source_id} -> task/${source_id}-${task_id}-fixture |
| Task branch | task/${source_id}-${task_id}-fixture |
| Depends on | N/A |
| References to load | - refinement.json |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

DP-337 feat-base fixture for ${task_id}.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| ${IMPL_ENTRY} | modify | fixture deliverable |

## Allowed Files

- ${IMPL_ENTRY}

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| fixture deliverable proof | ${IMPL_ENTRY} | framework deterministic gate | bash scripts/validate-breakdown-ready.sh fixture |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | gate pass | breakdown |
| verify | yes | gate pass | breakdown |
| ci-local | no | N/A - no repo CI required | breakdown |

## 估點理由

1 pt - DP-337 fixture。

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

# write_source <container_dir> <source_id> <base_branch_value|__ABSENT__>
# Builds a DP-backed source container: refinement.json (with or without
# source.base_branch) + index.md + a folder-native tasks/ holding one
# implementation task. base_branch=__ABSENT__ omits the field entirely (the
# historical / schema-optional shape).
write_source() {
  local container="$1"
  local source_id="$2"
  local base_value="$3"
  mkdir -p "$container"
  touch "$container/index.md"

  local base_line=""
  if [[ "$base_value" != "__ABSENT__" ]]; then
    base_line="\"base_branch\": \"${base_value}\","
  fi

  cat >"$container/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "${source_id}",
    "container": "${container}",
    "plan_path": "${container}/index.md",
    "jira_key": null,
    ${base_line}
    "_selftest_marker": true
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-18T00:00:00Z",
  "tasks": []
}
JSON

  write_task "$container/tasks" "$source_id" "T1"
}

# run_validator_expect_exit <expected_rc> <label> <target> [env_kv...]
# Runs validate-breakdown-ready against a target and asserts the exit code. Any
# trailing KEY=VALUE args are exported into the validator's environment (used for
# the AC-NEG3 bypass-env cases). On a non-match it prints captured stderr.
run_validator_expect_exit() {
  local expected="$1" label="$2" target="$3"
  shift 3
  local err rc
  err="$tmpdir/$label.err"
  set +e
  env "$@" bash "$VALIDATOR" "$target" >/dev/null 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "[selftest] FAIL ($label): expected exit $expected, got $rc" >&2
    cat "$err" >&2
    return 1
  fi
}

# assert_marker <label> <marker>
assert_marker() {
  local label="$1" marker="$2"
  if ! grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): expected marker '$marker' in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

# assert_no_marker <label> <marker>
assert_no_marker() {
  local label="$1" marker="$2"
  if grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): marker '$marker' should be absent in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

fail=0

# --- Case 1 (AC3 positive): dp source carrying source.base_branch=feat/{id}
# entering breakdown PASSes. The tasks/ dir resolves to the sibling
# refinement.json which carries the required feat-lane base. ---
ok_dir="$tmpdir/feat-ok"
write_source "$ok_dir" "DP-337" "feat/DP-337"
run_validator_expect_exit 0 "feat-ok-dir" "$ok_dir/tasks" || fail=1
# The same source passed via a single task.md index target must also PASS (the
# breakdown per-task invocation form: validate-breakdown-ready {dp}/tasks/T1/index.md).
run_validator_expect_exit 0 "feat-ok-file" "$ok_dir/tasks/T1/index.md" || fail=1
assert_no_marker "feat-ok-dir" "$FEAT_BASE_REQUIRED_MARKER" || fail=1

# --- Case 2 (AC3): dp source MISSING source.base_branch entering breakdown
# fail-closed (exit 2) with POLARIS_DP_FEAT_BASE_REQUIRED. ---
absent_dir="$tmpdir/feat-absent"
write_source "$absent_dir" "DP-337" "__ABSENT__"
run_validator_expect_exit 2 "feat-absent-dir" "$absent_dir/tasks" || fail=1
assert_marker "feat-absent-dir" "$FEAT_BASE_REQUIRED_MARKER" || fail=1
# Per-task target form must fail-close identically (the gate is not a
# directory-only escape hatch).
run_validator_expect_exit 2 "feat-absent-file" "$absent_dir/tasks/T1/index.md" || fail=1
assert_marker "feat-absent-file" "$FEAT_BASE_REQUIRED_MARKER" || fail=1

# --- Case 3 (AC-NEG3): POLARIS_* bypass env must NOT silence the required gate.
# A dp source still missing base_branch fail-closes even with every plausible
# bypass env set. ---
run_validator_expect_exit 2 "feat-absent-bypass" "$absent_dir/tasks" \
  POLARIS_SKILL_BOUNDARY_BYPASS=1 \
  POLARIS_LANGUAGE_POLICY_BYPASS=1 \
  POLARIS_MEMORY_HYGIENE_APPLY=1 \
  POLARIS_DP_FEAT_BASE_REQUIRED_BYPASS=1 \
  POLARIS_BYPASS=1 || fail=1
assert_marker "feat-absent-bypass" "$FEAT_BASE_REQUIRED_MARKER" || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo "validate-breakdown-ready dp-feat-base selftest FAIL" >&2
  exit 1
fi

echo "validate-breakdown-ready dp-feat-base selftest PASS"
