#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-main-chain-compliance.sh"

bash "$SCRIPT" --repo "$ROOT_DIR" --check-callsites
if [[ -d "$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/archive/DP-140-secondary-llm-main-development-chain-mechanical-enforcement" ]]; then
  legacy_dp140="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/archive/DP-140-secondary-llm-main-development-chain-mechanical-enforcement"
  if bash "$ROOT_DIR/scripts/refinement-handoff-gate.sh" "$legacy_dp140/refinement.md" --closeout >/dev/null 2>&1; then
    bash "$SCRIPT" --repo "$ROOT_DIR" \
      --source-container "$legacy_dp140" \
      --allow-active-verification
  fi
fi

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
---
status: IN_PROGRESS
---
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
| Branch chain | main -> task/DP-999-T1-fixture |
| Task branch | task/DP-999-T1-fixture |
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

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| Fixture | `scripts/check-main-chain-compliance.sh` | CLI validator output | `bash scripts/selftests/check-main-chain-compliance-selftest.sh` |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | selftest |
| test | yes | selftest pass | selftest |
| verify | yes | smoke pass | selftest |
| ci-local | no | N/A | selftest |

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
---
status: IN_PROGRESS
---
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
if bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$terminal_dir" --allow-active-verification --require-release-metadata >/dev/null 2>&1; then
  echo "FAIL: released implementation fixture passed without deliverable metadata" >&2
  exit 1
fi

cat >>"$terminal_dir/tasks/pr-release/T1/index.md" <<'MD'

deliverable:
  pr_url: "https://github.com/example/polaris/pull/1"
  head_sha: "0123456789abcdef0123456789abcdef01234567"
  evidence: "docs-manager/src/content/docs/specs/design-plans/DP-998-terminal-fixture/tasks/pr-release/T1/verify-report.md"
MD
bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$terminal_dir" --allow-active-verification --require-release-metadata >/dev/null

per_task_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-997-per-task-self-verify"
mkdir -p "$per_task_dir/tasks/T1"
cat >"$per_task_dir/index.md" <<'MD'
---
status: LOCKED
---
# DP-997
MD
cat >"$per_task_dir/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-997", "base_branch": "feat/DP-997"},
  "verification_strategy": {"mode": "per_task_self_verify", "reason": "selftest", "authority": "selftest"},
  "tasks": [
    {"id": "T1", "title": "implementation"}
  ]
}
JSON
cp "$source_dir/tasks/T1/index.md" "$per_task_dir/tasks/T1/index.md"
bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$per_task_dir" --allow-active-verification >/dev/null

source_required_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-996-source-level-missing-v"
mkdir -p "$source_required_dir/tasks/T1"
cat >"$source_required_dir/index.md" <<'MD'
---
status: LOCKED
---
# DP-996
MD
cat >"$source_required_dir/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-996", "base_branch": "feat/DP-996"},
  "verification_strategy": {"mode": "source_level_v_required", "reason": "selftest", "authority": "selftest"},
  "tasks": [
    {"id": "T1", "title": "implementation"},
    {"id": "V1", "title": "verification"}
  ]
}
JSON
cp "$source_dir/tasks/T1/index.md" "$source_required_dir/tasks/T1/index.md"
if bash "$SCRIPT" --repo "$ROOT_DIR" --source-container "$source_required_dir" --allow-active-verification >/dev/null 2>&1; then
  echo "FAIL: source_level_v_required fixture passed without V task" >&2
  exit 1
fi

echo "PASS: check-main-chain-compliance selftest"
