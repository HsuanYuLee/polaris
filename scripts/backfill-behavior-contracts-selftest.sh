#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d -t behavior-backfill-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

write_task() {
  local file="$1"
  local title="$2"
  local repo="$3"
  local level="$4"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
---
title: "Work Order - ${title} (1 pt)"
description: "Backfill fixture."
depends_on: []
status: READY
---

# ${title} (1 pt)

> Source: DP-109 | Task: T1 | JIRA: N/A | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-109 |
| Task ID | T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Branch chain | main -> task/T1 |
| Task branch | task/T1 |
| Depends on | N/A |
| References to load | - behavior-contract |

## 目標

${title}

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| example.md | modify | fixture |

## Allowed Files

- example.md

## 估點理由

1 pt - fixture。

## 測試計畫（code-level）

- fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | pass | engineering |
| test | yes | pass | engineering |
| verify | yes | pass | engineering |
| ci-local | no | N/A | planner decision |

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

specs="$WORKDIR/specs"
queue="$WORKDIR/queue.md"
static_task="$specs/design-plans/DP-001-static/tasks/T1.md"
runtime_task="$specs/companies/exampleco/EX-001/tasks/T1.md"
ambiguous_task="$specs/companies/exampleco/EX-002/tasks/T1.md"
archive_task="$specs/companies/exampleco/EX-003/archive/2026/tasks/T1.md"

write_task "$static_task" "schema validator update" "polaris-framework" "static"
write_task "$runtime_task" "replace carousel implementation" "exampleco-web" "runtime"
write_task "$ambiguous_task" "checkout adjustment" "exampleco-web" "runtime"
write_task "$archive_task" "replace archived implementation" "exampleco-web" "runtime"

bash "$ROOT_DIR/scripts/backfill-behavior-contracts.sh" --root "$specs" --queue "$queue" >/dev/null
if grep -q "behavior_contract" "$static_task"; then
  echo "FAIL: dry-run modified static task" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/backfill-behavior-contracts.sh" --root "$specs" --queue "$queue" --write >/dev/null
grep -q "applies: false" "$static_task"
grep -q "mode: \"parity\"" "$runtime_task"
grep -q "$ambiguous_task" "$queue" || grep -q "companies/exampleco/EX-002/tasks/T1.md" "$queue"
if grep -q "behavior_contract" "$archive_task"; then
  echo "FAIL: archive task was modified" >&2
  exit 1
fi
if rg -n "unknown" "$specs" "$queue" >/dev/null; then
  echo "FAIL: backfill wrote unknown" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/backfill-behavior-contracts.sh" --root "$specs" --queue "$queue" --check >/dev/null

echo "PASS: behavior contract backfill selftest"
