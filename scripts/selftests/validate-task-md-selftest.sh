#!/usr/bin/env bash
# Purpose: DP-296 T5 — folder-native (scripts/selftests/) entrypoint for the
#          validate-task-md.sh selftest. The canonical implementation lives at the
#          manifest-bound path scripts/validate-task-md-selftest.sh (single source
#          of truth, no second writer path); this wrapper exists so DP-296-T5's
#          Verify Command can reference the conventional scripts/selftests/ location
#          without forking the test body.
# Inputs:  none.
# Outputs: delegates stdout/stderr/exit code from the canonical selftest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$SCRIPT_DIR/validate-task-md-selftest.sh" "$@"

TMPROOT="$(mktemp -d -t validate-task-shape-deliverable.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_fixture() {
  local path="$1" shape="$2" delivery="$3"
  cat >"$path" <<EOF
---
title: "Work Order - T1: task shape fixture (1 pt)"
description: "task_shape-first delivery schema fixture."
status: IN_PROGRESS
task_kind: T
task_shape: $shape
verification:
  behavior_contract:
    applies: false
    reason: "framework selftest fixture"
$delivery
---

# T1: task shape fixture (1 pt)

> Source: DP-422 | Task: DP-422-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-422 |
| Work item ID | DP-422-T1 |
| Task ID | DP-422-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - self-contained |
| AC 驗收單 | N/A - self-contained |
| Base branch | main |
| Branch chain | main -> task/DP-422-T1-fixture |
| Task branch | task/DP-422-T1-fixture |
| Depends on | N/A |
| References to load | - \`scripts/validate-task-md.sh\` |

## 目標

驗證 task_shape-first delivery schema。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`scripts/validate-task-md.sh\` | modify | fixture |

## Allowed Files

- \`scripts/validate-task-md.sh\`

## 估點理由

1 pt - fixture。

## 測試計畫（code-level）

- 執行 validator。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: build
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

no_pr_block='deliverable:
  head_sha: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  verification:
    status: PASS
    ac_counts:
      ac_total: 0
      ac_pass: 0
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0'
pr_block='deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

write_fixture "$TMPROOT/audit.md" audit "$no_pr_block"
bash "$SCRIPT_DIR/validate-task-md.sh" "$TMPROOT/audit.md" >/dev/null

write_fixture "$TMPROOT/implementation-no-pr.md" implementation "$no_pr_block"
if bash "$SCRIPT_DIR/validate-task-md.sh" "$TMPROOT/implementation-no-pr.md" >/dev/null 2>&1; then
  echo "FAIL: implementation task accepted no-PR deliverable schema" >&2
  exit 1
fi

write_fixture "$TMPROOT/audit-pr.md" audit "$pr_block"
if bash "$SCRIPT_DIR/validate-task-md.sh" "$TMPROOT/audit-pr.md" >/dev/null 2>&1; then
  echo "FAIL: audit task accepted PR-bearing deliverable schema" >&2
  exit 1
fi

echo "validate-task-md task_shape-first deliverable selftest: PASS"
