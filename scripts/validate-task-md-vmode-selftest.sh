#!/usr/bin/env bash
# Selftest for validate-task-md.sh V-mode ac_verification lifecycle schema.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"

tmpdir="$(mktemp -d -t task-md-vmode-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

write_v_task() {
  local file="$1"
  local ac_status="$2"
  local human_disposition="$3"

  cat >"$file" <<EOF
---
title: "Work Order - V1: verification schema fixture (1 pt)"
description: "V-mode validator fixture."
ac_verification:
  status: ${ac_status}
  last_run_at: 2026-05-08T00:00:00Z
  ac_total: 2
  ac_pass: 0
  ac_fail: 0
  ac_manual_required: 0
  ac_uncertain: 2
  human_disposition: ${human_disposition}
---

# V1: verification schema fixture (1 pt)

> Epic: EP-999 | JIRA: TEST-999 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-999 |
| Parent Epic | EP-999 |
| Implementation tasks | T1 |
| Base branch | feat/ep-999-fixture |
| Depends on | N/A |
| References to load | - \`skills/references/task-md-schema.md\` |

## Verification Handoff

驗收委派 verify-AC skill 執行。

## 目標

驗證 V mode lifecycle schema。

## 驗收項目

- AC-1: fixture
- AC-2: fixture

## 估點理由

1 pt - validator fixture。

## 驗收計畫（AC level）

- 驗證 frontmatter lifecycle schema。

## Test Environment

- **Level**: runtime
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: http://127.0.0.1:3100
- **Env bootstrap command**: bash scripts/start-test-env.sh

## 驗收步驟

\`\`\`bash
curl -sf http://127.0.0.1:3100/health >/dev/null
echo "verify-AC executes this fixture"
\`\`\`
EOF
}

expect_pass() {
  local label="$1"
  local file="$2"
  if ! bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected pass for $label" >&2
    cat "$tmpdir/$label.err" >&2
    exit 1
  fi
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validation failure for $label" >&2
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected '$pattern' for $label" >&2
    cat "$tmpdir/$label.err" >&2
    exit 1
  fi
}

blocked_env_ok="$tmpdir/V1-blocked-env-ok.md"
write_v_task "$blocked_env_ok" "BLOCKED_ENV" "deferred"
expect_pass "blocked-env-ok" "$blocked_env_ok"

blocked_env_missing_disposition="$tmpdir/V1-blocked-env-missing-disposition.md"
write_v_task "$blocked_env_missing_disposition" "BLOCKED_ENV" ""
expect_fail_contains "blocked-env-missing-disposition" "$blocked_env_missing_disposition" "human_disposition is required"

invalid_status="$tmpdir/V1-invalid-status.md"
write_v_task "$invalid_status" "PENDING" "deferred"
expect_fail_contains "invalid-status" "$invalid_status" "ac_verification.status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS"

echo "PASS: validate-task-md V-mode lifecycle selftest"
