---
name: validate
description: >
  Framework health check：validate / 檢查 isolation 與 mechanisms；支援
  "validate isolation", "validate mechanisms", "檢查隔離", "檢查機制", health check。
metadata:
  author: Polaris
  version: 1.1.0
user-invocable: true
---

# Validate

`validate` 是 framework health check，整合 multi-company isolation 與 mechanism
compliance 的 static smoke tests。

## Contract

`validate` 只檢查並報告 health findings；不自動修復 rules、skills、hooks、settings、或
memory。任何 fail 的修正都要先回報具體 fix，再由使用者確認。

## Mode Routing

| Input | Mode | Reference |
|---|---|---|
| `validate`, `檢查` | isolation + mechanisms | all validate references |
| `validate isolation`, `檢查隔離` | isolation only | `validate-isolation-flow.md` |
| `validate mechanisms`, `檢查機制` | mechanisms only | `validate-mechanisms-flow.md` |

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `validate-reporting-flow.md`, `deterministic-hooks-registry.md` |
| Isolation | `validate-isolation-flow.md`, `workspace-config-reader.md` |
| Mechanisms | `validate-mechanisms-flow.md`, `mechanism-rationalizations.md` |
| Bootstrap budget health | `scripts/validate-bootstrap-budget.sh --advisory` |

## Hard Rules

- Do not patch failures automatically.
- 若 check 在兩個 modes 重疊，只跑一次並重用結果。
- Treat validator exit 1 / strict failure as FAIL, not advisory.
- Conversation-level mechanisms require post-task audit; static validate cannot prove them.
- WARN 與 FAIL 分開回報；除非 validator 定義 WARN blocking，否則 WARN 不阻擋。
- Bootstrap budget check is advisory by default; use `--blocking` only in explicit release/health gates.

## Completion

Return mode, checks run, pass/warn/fail counts, failed check evidence, proposed fixes, and skipped
checks with reason.

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
