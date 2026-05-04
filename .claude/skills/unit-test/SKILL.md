---
name: unit-test
description: >
  Project-aware unit testing guide with mock patterns, TDD discipline, and best practices.
  Auto-detects test framework (Jest/Vitest) and provides appropriate examples.
  Use when: (1) writing or fixing unit tests, (2) user says "寫測試", "write test",
  "補測試", "add test", (3) user encounters mock patterns or test failures,
  (4) user asks how to test a composable, component, or store, (5) user says
  "mock imports", "test store", "怎麼測", "測試怎麼寫",
  (6) reviewing test quality: "unit test review", "review tests", "check test quality",
  "測試審查", "review 測試", "測試品質", "檢查測試品質",
  (7) TDD workflow: "TDD", "test driven", "紅綠燈", "先寫測試", "test first",
  "red green refactor".
metadata:
  author: Polaris
  version: 1.1.0
---

# Unit Test

`unit-test` 是 project-aware unit testing guide，用於寫測試、修測試、review test quality，
或在 engineering 中執行 TDD。

## Contract

測試要驗證真實行為，不用 mock-only assertions 製造假綠燈。明確 TDD 時採 red / green /
refactor；一般補測試時仍要先確認現有 framework、local patterns、test command。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `unit-test-detection-tdd-flow.md`, `tdd-smart-judgment.md` |
| Jest / Vitest / Vue examples | `unit-test-framework-patterns.md` |
| Coverage / test quality review | `unit-test-strategy-coverage.md` |
| Delegated test work | `sub-agent-roles.md` Completion Envelope |

## Flow

1. Detect test framework and repo-specific test command.
2. Locate existing tests near the target module and copy local style.
3. Decide whether strict TDD applies using `tdd-smart-judgment.md`.
4. Plan test cases from simplest to most complex.
5. In TDD mode, run one red/green/refactor cycle per case.
6. In non-strict mode, write focused tests alongside implementation.
7. 先跑 narrow test command，再跑 owning workflow 要求的 broader command。
8. Report changed tests, command results, coverage gaps, and any intentional non-testable scope.

## Hard Rules

- 不可為了 pass 而弱化 assertions、加入 `.skip()`、刪 tests、或加 type suppressions。
- Public behavior 可測時，不測 private implementation details。
- 不 inline 大量 mock data；改用 fixtures 或 factories。
- 除非 dependency boundary 需要，不用 mock 取代 real source logic。
- 每個 test 驗證一個 behavior；需要用 "and" 命名時通常應拆開。
- Delegated test work must return the Completion Envelope.

## Completion

回傳 framework、commands run、TDD 時的 red/green evidence、files changed、remaining coverage
risk，以及 skipped test rationale。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
