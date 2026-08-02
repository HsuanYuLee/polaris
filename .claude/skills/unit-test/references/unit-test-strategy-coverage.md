---
title: "Unit Test Strategy Coverage"
description: "unit-test 的 test target selection、coverage expectations、quality review checklist、anti-patterns 與 skipped-test rationale。"
---

# Unit Test Strategy/Coverage Contract

這份 reference 負責測試範圍與品質檢查。

## Should Test

| Target | Location | Focus |
|---|---|---|
| Utility function | near source `.test.ts` | pure behavior |
| Composable | near source `.test.ts` | returned API and side effects |
| Store | near module `.test.ts` | state transitions |
| Component | near component `.test.ts` | props, emits, render, interaction |

## Usually Skip

- pure type definitions
- constants only
- barrel exports
- pure CSS/style changes
- config files with no behavior

使用者要求 test coverage 時，completion 必須說明 skipped scope。

## Coverage Expectations

Minimum:

- each public export has happy path coverage
- main conditional branches covered
- null/undefined/empty values covered when supported

Recommended:

- error handling
- API failure behavior
- returned object shape
- regression case for the bug being fixed

## Quality Review Checklist

- Test name describes behavior.
- Assertion would fail if implementation regresses.
- Test imports and executes real source logic.
- Mocking is limited to dependency boundaries.
- Test is independent from execution order.
- Fixtures are small and named.

## Anti-Patterns

- assertion only checks a mock return value
- `.skip()` / `.only()` left behind
- `as any` or `@ts-ignore` used to silence test typing
- overly broad snapshot that hides behavior
- one test covers multiple unrelated behaviors
