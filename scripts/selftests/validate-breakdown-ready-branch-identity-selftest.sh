#!/usr/bin/env bash
# Purpose: Selftest for the DP-328 T2 branch-identity gate in
#          validate-breakdown-ready.sh. The gate reuses
#          scripts/resolve-task-branch.sh validate_branch (the single canonical
#          branch-identity rule — no second prefix/leak implementation) and maps
#          its exit-1 verdict to a contract violation (exit 2 +
#          POLARIS_TASK_BRANCH_IDENTITY_LEAK), so a composite work_item_id leak
#          (task/{work_item_id}-... when work_item_id != delivery_ticket_key)
#          fails at breakdown-ready instead of leaking through to
#          engineering-branch-setup.
# Covers:  AC4 (leaked composite-Tn JIRA-Epic branch -> exit 2 + marker),
#          AC5 (reuse resolve-task-branch.sh — no second implementation; static
#          assertion on the validator source), AC-NEG1 (DP-backed branch where
#          delivery_ticket_key == work_item_id never trips the gate), AC-NEG2
#          (an unrelated readiness FAIL keeps the legacy exit 1 and does not get
#          escalated/swallowed by the new gate).
# Inputs:  none (builds tmpdir folder-native tasks/Tn/index.md fixtures with
#          GENERIC placeholder identities — EXCO / exampleco-web — never live slugs)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"
IDENTITY_MARKER="POLARIS_TASK_BRANCH_IDENTITY_LEAK"

tmpdir="$(mktemp -d -t validate-breakdown-ready-branch-identity-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_task <tasks_dir> <folder> <task_identity> <source_type> <source_id> <jira_key> <base_branch> <repo> <task_branch>
# Produces a folder-native tasks/<folder>/index.md whose body passes the base
# readiness gate (schema + Scope Trace Matrix + Gate Closure Matrix) so the ONLY
# readiness dimension left to vary is the Task branch identity. Each fixture is a
# single implementation task so the D4 delivery-unit shape gate sees >= 1
# implementation and never short-circuits as a research/dispatch unit. The folder
# name (Tn) must match the task-discovery pattern; the Task ID cell carries the
# full task_identity (= work_item_id) parse-task-md.sh / resolve-task-branch.sh
# read: Task ID -> work_item_id, JIRA key -> jira_key (= delivery_ticket_key for
# jira source; = work_item_id for dp source).
write_task() {
  local tasks_dir="$1" folder="$2" task_identity="$3" source_type="$4" source_id="$5"
  local jira_key="$6" base_branch="$7" repo="$8" task_branch="$9"
  local dir="$tasks_dir/$folder"
  local file="$dir/index.md"
  local task_id="$task_identity"
  mkdir -p "$dir"
  cat >"$file" <<EOF
---
title: "Work Order - ${task_id}: branch-identity fixture"
description: "validate-breakdown-ready branch-identity selftest fixture."
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest; no runtime behavior"
depends_on: []
---

# ${folder}: branch-identity fixture (1 pt)

> Source: ${source_id} | Task: ${task_id} | JIRA: ${jira_key} | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | ${source_type} |
| Source ID | ${source_id} |
| Task ID | ${task_id} |
| JIRA key | ${jira_key} |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | ${base_branch} |
| Branch chain | ${base_branch} -> ${task_branch} |
| Task branch | ${task_branch} |
| Depends on | N/A |
| References to load | - refinement.json |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

branch-identity fixture for ${task_id}.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/dp328-fixture.sh | modify | fixture deliverable |

## Allowed Files

- scripts/dp328-fixture.sh

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| fixture deliverable proof | scripts/dp328-fixture.sh | framework deterministic gate | bash scripts/validate-breakdown-ready.sh fixture |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | gate pass | breakdown |
| verify | yes | gate pass | breakdown |
| ci-local | no | N/A - no repo CI required | breakdown |

## 估點理由

1 pt - branch-identity fixture。

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

# run_validator_expect_exit <expected_rc> <label> <tasks_dir>
run_validator_expect_exit() {
  local expected="$1" label="$2" dir="$3" rc
  set +e
  bash "$VALIDATOR" "$dir" >/dev/null 2>"$tmpdir/$label.err"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "[selftest] FAIL ($label): expected exit $expected, got $rc" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

assert_marker() {
  local label="$1" marker="$2"
  if ! grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): expected marker '$marker' in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

assert_no_marker() {
  local label="$1" marker="$2"
  if grep -q "$marker" "$tmpdir/$label.err"; then
    echo "[selftest] FAIL ($label): unexpected marker '$marker' in stderr" >&2
    cat "$tmpdir/$label.err" >&2
    return 1
  fi
}

fail=0

# --- Case 1 (AC-NEG1): DP-backed legal branch -> PASS (no false positive) -----
# dp source collapses delivery_ticket_key == work_item_id == DP-328-T1, so a
# well-formed DP branch never trips the leak rule.
dp_dir="$tmpdir/dp-ok/tasks"
write_task "$dp_dir" "T1" "DP-328-T1" "dp" "DP-328" "N/A" "main" "polaris-framework" \
  "task/DP-328-T1-producer-branch-identity"
run_validator_expect_exit 0 "dp-ok" "$dp_dir" || fail=1

# --- Case 2: JIRA-Epic legal branch (delivery_ticket_key prefix) -> PASS -------
# jira source: the Task ID cell holds the real per-task jira_key (EXCO-712), so
# work_item_id == delivery_ticket_key == EXCO-712. A branch with that jira_key
# prefix is the correct product identity and passes validate_branch. Source ID
# (EXCO-700) is the parent Epic — it intentionally differs from the child key.
jira_ok_dir="$tmpdir/jira-ok/tasks"
write_task "$jira_ok_dir" "T1" "EXCO-712" "jira" "EXCO-700" "EXCO-712" "develop" "exampleco-web" \
  "task/EXCO-712-jira-epic-branch-identity"
run_validator_expect_exit 0 "jira-ok" "$jira_ok_dir" || fail=1
assert_no_marker "jira-ok" "$IDENTITY_MARKER" || fail=1

# --- Case 3 (AC4): JIRA-Epic branch leaks the internal composite -> exit 2 + marker
# This is the real-world JIRA-Epic bug shape: validate-task-md accepts the plain
# jira_key Task ID (EXCO-712), but the buggy producer derived the branch from the
# internal composite task_id `{Epic}-T{n}` (task/EXCO-700-T2-...). The branch's
# delivery identity must be task/{jira_key}- (task/EXCO-712-); the composite-Tn
# prefix is what resolve-task-branch.sh validate_branch rejects. The gate must
# catch it at breakdown-ready, not leak it to engineering-branch-setup.
jira_leak_dir="$tmpdir/jira-leak/tasks"
write_task "$jira_leak_dir" "T1" "EXCO-712" "jira" "EXCO-700" "EXCO-712" "develop" "exampleco-web" \
  "task/EXCO-700-T2-jira-epic-branch-identity"
run_validator_expect_exit 2 "jira-leak" "$jira_leak_dir" || fail=1
assert_marker "jira-leak" "$IDENTITY_MARKER" || fail=1

# --- Case 4 (AC-NEG2): unrelated readiness FAIL keeps exit 1, no identity marker
# A legal branch but a body missing the required Gate Closure Matrix is a generic
# readiness failure (exit 1). The new identity gate must NOT escalate it to exit 2
# nor emit its marker — no wider surface change.
readiness_dir="$tmpdir/readiness-fail/tasks"
write_task "$readiness_dir" "T1" "DP-328-T1" "dp" "DP-328" "N/A" "main" "polaris-framework" \
  "task/DP-328-T1-producer-branch-identity"
# Strip the Gate Closure Matrix section to force a readiness-only FAIL.
python3 - "$readiness_dir/T1/index.md" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# Drop the "## Gate Closure Matrix" section (up to the next "## " heading).
text = re.sub(r"\n## Gate Closure Matrix\n.*?(?=\n## )", "\n", text, flags=re.DOTALL)
open(path, "w", encoding="utf-8").write(text)
PY
run_validator_expect_exit 1 "readiness-fail" "$readiness_dir" || fail=1
assert_no_marker "readiness-fail" "$IDENTITY_MARKER" || fail=1

# --- AC5 (static): the gate REUSES resolve-task-branch.sh, no second impl ------
# The branch-identity verdict must come from resolve-task-branch.sh, and the
# validator must not re-implement the prefix/leak rule with its own regex.
if ! grep -q 'resolve-task-branch.sh' "$VALIDATOR"; then
  echo "[selftest] FAIL (AC5): validator must invoke resolve-task-branch.sh (single canonical rule)" >&2
  fail=1
fi
if ! grep -q 'validate_branch_identity_gate' "$VALIDATOR"; then
  echo "[selftest] FAIL (AC5): validator must define validate_branch_identity_gate" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "validate-breakdown-ready branch-identity selftest FAIL" >&2
  exit 1
fi

echo "validate-breakdown-ready branch-identity selftest PASS"
