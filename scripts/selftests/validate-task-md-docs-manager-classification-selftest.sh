#!/usr/bin/env bash
# Purpose: Selftest for validate-task-md.sh docs-manager page-deliverable
#          classification. Asserts the /docs-manager/ URL requirement is applied
#          only when the task is a genuine docs-manager content-page deliverable
#          (Runtime verify target host = local docs viewer, OR Allowed Files
#          contains a docs-manager/src/content/docs/** content page that is NOT a
#          specs-container artifact), and NOT merely because a docs-manager specs
#          container path appears in "References to load".
# Inputs:  none (writes fixtures to a tmpdir; runs scripts/validate-task-md.sh)
# Outputs: exit 0 + "PASS" line on success; exit 1 + FAIL detail on failure
# Side effects: creates and removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"

tmpdir="$(mktemp -d -t task-md-docs-manager-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# write_task <file> <references_block> <allowed_files_block> <target> <verify_url>
write_task() {
  local file="$1"
  local references_block="$2"
  local allowed_files_block="$3"
  local target="$4"
  local verify_url="$5"

  cat >"$file" <<EOF
---
title: "Work Order - T1: docs-manager classification fixture (1 pt)"
description: "docs-manager page-deliverable classification validator fixture."
status: IN_PROGRESS
---

# T1: docs-manager classification fixture (1 pt)

> Source: DP-304 | Task: DP-304-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-304 |
| Task ID | DP-304-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-304-T1-fixture |
| Task branch | task/DP-304-T1-fixture |
| Depends on | N/A |
| References to load | ${references_block} |

## 目標

docs-manager page-deliverable classification fixture。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/validate-task-md.sh | test | fixture only |

## Allowed Files

${allowed_files_block}

## 估點理由

1 pt - validator fixture。

## 測試計畫（code-level）

- validator fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: runtime
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: ${target}
- **Env bootstrap command**: bash scripts/start-test-env.sh

## Verify Command

\`\`\`bash
curl -sf ${verify_url} >/dev/null
echo PASS
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
  echo "ok: $label (exit 0)"
}

expect_fail_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if bash "$VALIDATOR" "$file" >/dev/null 2>"$tmpdir/$label.err"; then
    echo "FAIL: expected validation failure for $label" >&2
    cat "$tmpdir/$label.err" >&2
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected stderr to contain '$pattern' for $label" >&2
    cat "$tmpdir/$label.err" >&2
    exit 1
  fi
  echo "ok: $label (exit 1, message matched)"
}

# ---------------------------------------------------------------------------
# AC1: product runtime task whose References to load contain a docs-manager
# specs-container path (refinement.md). The task verifies a PRODUCT domain
# (dev.exampleco.com), so the /docs-manager/ URL requirement must NOT apply.
# Expected: exit 0.
# ---------------------------------------------------------------------------
ac1="$tmpdir/AC1-product-runtime-with-specs-reference.md"
write_task "$ac1" \
  '- `docs-manager/src/content/docs/specs/companies/exampleco/EP-100/refinement.md`<br>- `scripts/foo.sh`' \
  '- src/product/page.ts' \
  'https://dev.exampleco.com/product/123' \
  'https://dev.exampleco.com/product/123'
expect_pass "AC1-product-runtime-with-specs-reference" "$ac1"

# ---------------------------------------------------------------------------
# AC2: genuine docs-manager content-page task. Allowed Files contains a
# docs-manager/src/content/docs/** content page (NOT a specs container), and the
# verify target host is the local docs viewer (127.0.0.1:8080) with a
# /docs-manager/ URL path. Expected: exit 0.
# ---------------------------------------------------------------------------
ac2="$tmpdir/AC2-real-docs-manager-page.md"
write_task "$ac2" \
  '- `scripts/foo.sh`' \
  '- docs-manager/src/content/docs/guides/getting-started.md' \
  'http://127.0.0.1:8080/docs-manager/guides/getting-started/' \
  'http://127.0.0.1:8080/docs-manager/guides/getting-started/'
expect_pass "AC2-real-docs-manager-page" "$ac2"

# ---------------------------------------------------------------------------
# AC3 (NEG): genuine docs-manager content-page task (Allowed Files contains a
# docs-manager content page) but the verify target is NOT a /docs-manager/ URL
# (example.com). The /docs-manager/ URL requirement MUST fire.
# Expected: exit 1, stderr contains the docs-manager URL requirement message.
# ---------------------------------------------------------------------------
ac3="$tmpdir/AC3-docs-manager-page-wrong-url.md"
write_task "$ac3" \
  '- `scripts/foo.sh`' \
  '- docs-manager/src/content/docs/guides/getting-started.md' \
  'https://example.com/guides/getting-started' \
  'https://example.com/guides/getting-started'
expect_fail_contains "AC3-docs-manager-page-wrong-url" "$ac3" "docs-manager"

# ---------------------------------------------------------------------------
# AC-NEG1: DP-backed runtime task whose References to load contain a DP-backed
# specs-container path (design-plans/DP-NNN/refinement.md) and a product-domain
# verify target. Source-neutral proof: same as AC1 but DP-backed container.
# Expected: exit 0.
# ---------------------------------------------------------------------------
acneg1="$tmpdir/AC-NEG1-dp-backed-runtime-with-specs-reference.md"
write_task "$acneg1" \
  '- `docs-manager/src/content/docs/specs/design-plans/DP-100-example/refinement.md`<br>- `scripts/foo.sh`' \
  '- src/product/page.ts' \
  'https://dev.exampleco.com/product/456' \
  'https://dev.exampleco.com/product/456'
expect_pass "AC-NEG1-dp-backed-runtime-with-specs-reference" "$acneg1"

echo "PASS: validate-task-md docs-manager page-deliverable classification selftest (AC1/AC2/AC3/AC-NEG1)"
