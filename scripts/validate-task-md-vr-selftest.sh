#!/usr/bin/env bash
# Selftest for task.md verification.visual_regression schema enforcement.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
PARSER="$ROOT_DIR/scripts/parse-task-md.sh"

tmpdir="$(mktemp -d -t task-md-vr-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

write_task() {
  local file="$1"
  local frontmatter="$2"
  local level="$3"
  local target="$4"
  local bootstrap="$5"

  cat >"$file" <<EOF
---
title: "Work Order - T1: VR fixture (${level})"
description: "VR metadata validator fixture."
${frontmatter}
---

# T1: VR fixture (1 pt)

> Source: DP-104 | Task: DP-104-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-104 |
| Task ID | DP-104-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-104-T1-vr-fixture |
| Task branch | task/DP-104-T1-vr-fixture |
| Depends on | N/A |
| References to load | - task-md-schema |

## 目標

驗證 VR metadata schema。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/validate-task-md.sh | test | fixture only |

## Allowed Files

- scripts/validate-task-md.sh

## 估點理由

1 pt - validator fixture。

## 測試計畫（code-level）

- validator fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: ${target}
- **Env bootstrap command**: ${bootstrap}

## Verify Command

\`\`\`bash
curl -sf ${target} >/dev/null
echo PASS
\`\`\`
EOF
}

expect_pass() {
  local label="$1"
  local file="$2"
  if ! bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected pass for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validation failure for $label"
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected '$pattern' for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

valid_vr="$tmpdir/T1-valid-vr.md"
write_task "$valid_vr" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/zh-tw"]' "runtime" "http://127.0.0.1:3100" "bash scripts/start-test-env.sh"
expect_pass "valid-vr" "$valid_vr"

expected="$(bash "$PARSER" "$valid_vr" --no-resolve --field verification_visual_regression_expected)"
if [[ "$expected" != "none_allowed" ]]; then
  echo "FAIL: parser expected field mismatch: $expected"
  exit 1
fi
pages="$(bash "$PARSER" "$valid_vr" --no-resolve --field verification_visual_regression_pages)"
if [[ "$pages" != "/zh-tw" ]]; then
  echo "FAIL: parser pages field mismatch: $pages"
  exit 1
fi

empty_pages="$tmpdir/T1-empty-pages.md"
write_task "$empty_pages" 'verification:
  visual_regression:
    expected: baseline_required
    pages: []' "runtime" "http://127.0.0.1:3100" "bash scripts/start-test-env.sh"
expect_pass "empty-pages" "$empty_pages"

invalid_expected="$tmpdir/T1-invalid-expected.md"
write_task "$invalid_expected" 'verification:
  visual_regression:
    expected: maybe
    pages: ["/zh-tw"]' "runtime" "http://127.0.0.1:3100" "bash scripts/start-test-env.sh"
expect_fail_contains "invalid-expected" "$invalid_expected" "verification.visual_regression.expected"

scalar_pages="$tmpdir/T1-scalar-pages.md"
write_task "$scalar_pages" 'verification:
  visual_regression:
    expected: none_allowed
    pages: "/zh-tw"' "runtime" "http://127.0.0.1:3100" "bash scripts/start-test-env.sh"
expect_fail_contains "scalar-pages" "$scalar_pages" "verification.visual_regression.pages must be a YAML list"

static_vr="$tmpdir/T1-static-vr.md"
write_task "$static_vr" 'verification:
  visual_regression:
    expected: none_allowed
    pages: []' "static" "N/A" "N/A"
expect_fail_contains "static-vr" "$static_vr" "requires Test Environment Level=runtime"

no_vr_static="$tmpdir/T1-no-vr-static.md"
write_task "$no_vr_static" "" "static" "N/A" "N/A"
expect_pass "no-vr-static" "$no_vr_static"

echo "PASS: task.md VR metadata validator selftest"
