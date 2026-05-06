#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$SCRIPT_DIR/gate-work-source.sh"
WRAPPER="$ROOT_DIR/scripts/polaris-pr-create.sh"
CODEX_WRAPPER="$ROOT_DIR/scripts/codex-guarded-gh-pr-create.sh"
TMPDIR="$(mktemp -d -t gate-work-source.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
  echo "[gate-work-source-selftest] FAIL: $*" >&2
  exit 1
}

assert_blocked() {
  local label="$1"
  shift
  local out=""
  local rc=0
  out="$("$@" 2>&1)" || rc=$?
  [[ "$rc" -eq 2 ]] || {
    echo "$out" >&2
    fail "$label expected exit 2, got $rc"
  }
  grep -q "BLOCKED" <<<"$out" || {
    echo "$out" >&2
    fail "$label expected BLOCKED output"
  }
}

assert_pass() {
  local label="$1"
  shift
  local out=""
  out="$("$@" 2>&1)" || {
    echo "$out" >&2
    fail "$label expected pass"
  }
  grep -q "source valid" <<<"$out" || {
    echo "$out" >&2
    fail "$label expected source valid output"
  }
}

write_minimal_task() {
  local repo="$1"
  local branch="$2"
  local task="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-no-source-no-pr/tasks/T1/index.md"
  mkdir -p "$(dirname "$task")" "$repo/scripts/gates" "$repo/.claude/skills/references"
  cat > "$repo/scripts/gates/gate-work-source-selftest.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$repo/scripts/gates/gate-work-source-selftest.sh"
  cat > "$repo/.claude/skills/references/engineer-delivery-flow.md" <<'MD'
# engineer delivery fixture
MD
  cat > "$repo/.claude/skills/references/pr-body-builder.md" <<'MD'
# pr body fixture
MD
  cat > "$task" <<MD
---
title: "Work Order - T1: fixture no source no PR gate (1 pt)"
description: "Fixture task for source gate selftest."
depends_on: []
verification:
  behavior_contract:
    applies: false
    reason: "selftest fixture"
status: READY
---

# T1: fixture no source no PR gate (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: fixture

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
| References to load | \`scripts/gates/gate-work-source-selftest.sh\` |

## 目標

提供 source gate selftest 的合法 task source。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`scripts/gates/gate-work-source-selftest.sh\` | modify | fixture target |

## Allowed Files

- \`scripts/gates/gate-work-source-selftest.sh\`

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| source gate fixture | \`scripts/gates/gate-work-source-selftest.sh\` | fixture | \`bash scripts/gates/gate-work-source-selftest.sh\` |

## 估點理由

1 pt。Selftest fixture only。

## 測試計畫（code-level）

- Run fixture command.

## Test Environment

- **Level**: static
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

| 項目 | 值 |
|------|-----|
| Runtime | local shell |
| External services | N/A |
| Required env | N/A |
| Data fixtures | temporary repo |

## Test Command

\`\`\`bash
bash scripts/gates/gate-work-source-selftest.sh
\`\`\`

## Verify Command

\`\`\`bash
bash scripts/gates/gate-work-source-selftest.sh
\`\`\`
MD
}

repo="$TMPDIR/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email selftest@example.test
git -C "$repo" config user.name "Self Test"
cat > "$repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
mkdir -p "$repo/scripts"
cat > "$repo/scripts/polaris-pr-create.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$repo/scripts/polaris-pr-create.sh"
git -C "$repo" add .
git -C "$repo" commit -q -m init
git -C "$repo" checkout -q -b task/DP-999-T1-source-gate

assert_blocked "source-less branch" bash "$GATE" --repo "$repo"

cat > "$TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
echo "gh should not be called in blocked selftest" >&2
exit 99
SH
chmod +x "$TMPDIR/gh"

assert_blocked "skip-gates source gate" env PATH="$TMPDIR:$PATH" POLARIS_SKIP_PR_GATES=1 \
  bash "$WRAPPER" --repo "$repo" --skip-gates --title "測試 PR" --body "測試 body"

assert_blocked "codex fallback source gate" env PATH="$TMPDIR:$PATH" \
  GATE_PROJECT_DIR="$repo" bash "$CODEX_WRAPPER" --dry-run --title "測試 PR" --body "測試 body"

write_minimal_task "$repo" "task/DP-999-T1-source-gate"

assert_pass "legal task branch" bash "$GATE" --repo "$repo"

assert_blocked "draft blocked" env PATH="$TMPDIR:$PATH" \
  bash "$WRAPPER" --repo "$repo" --skip-gates --draft --title "測試 PR" --body "測試 body"

echo "[gate-work-source-selftest] PASS"
