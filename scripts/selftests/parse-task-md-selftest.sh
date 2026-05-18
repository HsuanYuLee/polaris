#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARSE_TASK_MD_SELFTEST=1 bash "$SCRIPT_DIR/parse-task-md.sh"

tmpdir="$(mktemp -d -t polaris-required-tools-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

valid_task="$tmpdir/T1.md"
cat > "$valid_task" <<'MD'
---
title: "T1: Required tools fixture (1 pt)"
status: PLANNED
verification:
  behavior_contract:
    applies: false
    reason: "schema selftest"
---

# T1: Required tools fixture (1 pt)

> Source: DP-194 | Task: DP-194-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-194 |
| Task ID | DP-194-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-194-T1-required-tools-fixture |
| Task branch | task/DP-194-T1-required-tools-fixture |
| Depends on | N/A |
| References to load | - `.claude/skills/references/task-md-schema.md` |

## 目標

Validate Required Tools schema.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/example.sh` | modify | fixture |

## Allowed Files

- `scripts/example.sh`

## Required Tools

| name | owner | install_authority | check_command | install_command | runtime_profile | goes_to_mise | handoff_hint |
|------|-------|-------------------|---------------|-----------------|-----------------|--------------|--------------|
| mockoon-cli | ticket | workspace_dependency_consent | mockoon-cli --version | N/A | ticket | false | Install/check before Verify Command. |

## 估點理由

1 pt — schema fixture.

## 測試計畫（code-level）

- validate-task-md should accept ticket-scoped tools with goes_to_mise=false.

## Test Command

```bash
echo test
```

## Test Environment

- **Level**: build
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo verify
```
MD

bash "$SCRIPT_DIR/validate-task-md.sh" "$valid_task" >/dev/null

invalid_authority="$tmpdir/T2.md"
sed 's/workspace_dependency_consent/unknown_installer/' "$valid_task" > "$invalid_authority"
if bash "$SCRIPT_DIR/validate-task-md.sh" "$invalid_authority" >/dev/null 2>&1; then
  echo "[selftest] Required Tools unknown install_authority should fail" >&2
  exit 1
fi

invalid_mise="$tmpdir/T3.md"
sed 's@| mockoon-cli | ticket | workspace_dependency_consent | mockoon-cli --version | N/A | ticket | false |@| mockoon-cli | ticket | workspace_dependency_consent | mockoon-cli --version | N/A | ticket | true |@' "$valid_task" > "$invalid_mise"
if bash "$SCRIPT_DIR/validate-task-md.sh" "$invalid_mise" >/dev/null 2>&1; then
  echo "[selftest] Required Tools ticket-scoped goes_to_mise=true should fail" >&2
  exit 1
fi

valid_refinement="$tmpdir/refinement-valid.json"
cat > "$valid_refinement" <<'JSON'
{
  "epic": "EPIC-194",
  "version": "1.0",
  "created_at": "2026-05-18T00:00:00Z",
  "modules": [
    {
      "path": "scripts/example.sh",
      "action": "modify"
    }
  ],
  "dependencies": [],
  "tool_requirements": [
    {
      "name": "mockoon-cli",
      "owner": "ticket",
      "install_authority": "workspace_dependency_consent",
      "check_command": "mockoon-cli --version",
      "install_command": null,
      "runtime_profile": "ticket",
      "goes_to_mise": false,
      "handoff_hint": "Install/check before Verify Command."
    }
  ],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "Tool requirements schema is preserved.",
      "category": "functional",
      "quantifiable": true,
      "verification": {
        "method": "unit_test",
        "detail": "validator selftest"
      },
      "negative": false
    }
  ],
  "predecessor_audit": []
}
JSON

bash "$SCRIPT_DIR/validate-refinement-json.sh" "$valid_refinement" >/dev/null

invalid_refinement_authority="$tmpdir/refinement-invalid-authority.json"
sed 's/workspace_dependency_consent/unknown_installer/' "$valid_refinement" > "$invalid_refinement_authority"
if bash "$SCRIPT_DIR/validate-refinement-json.sh" "$invalid_refinement_authority" >/dev/null 2>&1; then
  echo "[selftest] refinement tool_requirements unknown install_authority should fail" >&2
  exit 1
fi

invalid_refinement_mise="$tmpdir/refinement-invalid-mise.json"
sed 's/"goes_to_mise": false/"goes_to_mise": true/' "$valid_refinement" > "$invalid_refinement_mise"
if bash "$SCRIPT_DIR/validate-refinement-json.sh" "$invalid_refinement_mise" >/dev/null 2>&1; then
  echo "[selftest] refinement ticket-scoped goes_to_mise=true should fail" >&2
  exit 1
fi
