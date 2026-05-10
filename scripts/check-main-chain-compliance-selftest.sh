#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-main-chain-compliance.sh"

bash "$SCRIPT" --repo "$ROOT_DIR" --check-callsites
bash "$SCRIPT" --repo "$ROOT_DIR" \
  --source-container "$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/DP-140-secondary-llm-main-development-chain-mechanical-enforcement" \
  --allow-active-verification

tmpdir="$(mktemp -d -t main-chain-compliance.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
source_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture"
mkdir -p "$source_dir/tasks/T1" "$source_dir/tasks/V1"
cat >"$source_dir/index.md" <<'MD'
---
status: LOCKED
---
# DP-999
MD
cat >"$source_dir/tasks/T1/index.md" <<'MD'
# T1: Fixture implementation (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | DP-999-V1 |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1 |
| Task branch | task/DP-999-T1 |
| Depends on | N/A |
| References to load | - scripts/check-main-chain-compliance.sh |

## 目標

Fixture.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/check-main-chain-compliance.sh` | modify | Fixture |

## Allowed Files

- `scripts/check-main-chain-compliance.sh`

## 估點理由

1 pt.

## Test Command

```bash
true
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo PASS
```
MD
cat >"$source_dir/tasks/V1/index.md" <<'MD'
# V1: Fixture verification (1 pt)

> Source: DP-999 | Task: DP-999-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-999-V1 |
| Parent Epic | DP-999 |
| Implementation tasks | T1 |
| Base branch | main |
| Depends on | DP-999-T1 |
| References to load | - scripts/check-main-chain-compliance.sh |

## 驗收項目

| AC | 摘要 | 對應實作 task | 驗證類型 |
|----|------|--------------|---------|
| AC1 | Fixture | T1 | static |

## 估點理由

1 pt.

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## 驗收步驟

```bash
echo PASS
```
MD
if bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$source_dir" >/dev/null 2>&1; then
  echo "FAIL: active V fixture passed without allow flag" >&2
  exit 1
fi

terminal_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-terminal-fixture"
mkdir -p "$terminal_dir/tasks/pr-release/T1" "$terminal_dir/tasks/V1"
cat >"$terminal_dir/index.md" <<'MD'
---
status: LOCKED
---
# DP-998
MD
cp "$source_dir/tasks/T1/index.md" "$terminal_dir/tasks/pr-release/T1/index.md"
cp "$source_dir/tasks/V1/index.md" "$terminal_dir/tasks/V1/index.md"
bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$terminal_dir" --allow-active-verification >/dev/null

echo "PASS: check-main-chain-compliance selftest"
