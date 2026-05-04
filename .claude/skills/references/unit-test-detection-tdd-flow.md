---
title: "Unit Test Detection TDD Flow"
description: "unit-test 的 framework detection、repo-specific command selection、TDD applicability、red/green/refactor cycle 與 cycle log。"
---

# Unit Test Detection/TDD Contract

這份 reference 負責 framework detection 與 TDD flow。

## Framework Detection

| Signal | Framework | Default Command |
|---|---|---|
| `vitest.config.ts` / `vitest.config.mts` | Vitest | `npx vitest run` |
| `jest.config.js` / `jest.config.ts` | Jest | `npx jest` |

Repo handbook、workspace config、task.md 的 command 優先於 default command。

若專案有專屬 unit-test skill 或 handbook testing guide，先讀專屬規範。

## TDD Applicability

啟用 strict TDD：

- 使用者明確說 TDD、紅綠燈、先寫測試、test first。
- engineering work order 或上游 skill 明確要求 TDD。

可不啟用 strict TDD，但仍需測試：

- template/style only
- config/type definition only
- barrel export
- simple prop forwarding

細節用 `tdd-smart-judgment.md` 判斷。

## Test Plan

先列 test cases，再動手寫 code。排序：simple happy path → edge cases → errors。

每次只寫一個 case，不批次一次寫完所有 tests。

## Red / Green / Refactor

每個 case：

1. RED：寫一個會失敗的 test，執行並確認 fail reason 是預期的。
2. GREEN：寫最少 code 讓該 test pass。
3. REFACTOR：所有 tests green 後才整理結構；每次整理後重跑 tests。

Cycle 超過 30 分鐘時，拆小 behavior。

## Cycle Log

TDD completion 要回報：

- cycle number
- test name
- RED failure summary
- GREEN implementation summary
- REFACTOR summary or none
- command result
