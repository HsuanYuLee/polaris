---
name: tdd
description: >
  Enforces strict Test-Driven Development (Red-Green-Refactor) workflow during implementation.
  Each feature is built through small, iterative cycles: write a failing test → minimal code to pass → refactor.
  Use this skill whenever: (1) user says "TDD", "test driven", "紅綠燈", "先寫測試", "test first",
  "red green refactor", (2) another skill (work-on, fix-bug) delegates implementation
  with TDD discipline, (3) user wants to develop a feature or fix with tests leading the way.
  This skill is about the *development process* — for test writing patterns and mock techniques,
  it references unit-test.
metadata:
  author: ""
  version: 1.0.0
---

# TDD Workflow — Red-Green-Refactor

This skill enforces a disciplined TDD cycle. The goal is not just "having tests" — it's using tests to **drive design decisions** and keep implementation scope tight.

## 0. Setup

Before starting any cycle:

1. **Detect test framework** — check for `vitest.config.ts` (Vitest) or `jest.config.js` (Jest)
2. **Identify the test command** — `pnpm -C <project> vitest run` or `pnpm -C <project> jest`
3. **Locate existing tests** — find the test file for the target module, or determine where to create one (same directory, `*.test.ts` / `*.spec.ts`)
4. **Read unit-test skill** for project-specific mock patterns and conventions

## 1. Plan Test Cases

Before writing any code, list the behaviors to implement as test case names:

```
□ returns empty array when no results match
□ maps API response to display format
□ handles null price gracefully
□ sorts results by relevance score descending
```

Order them from simplest → most complex. Each one becomes a Red-Green-Refactor cycle.

**Do not write all tests upfront.** Only write the test for the current cycle. The list is a roadmap, not a batch job.

## 2. Red-Green-Refactor Cycle

Repeat for each planned test case:

### RED — Write a Failing Test

Write exactly ONE test that describes the next behavior. Run it. It must fail.

```
🔴 RED: "returns empty array when no results match"
   → Expected: [] / Got: function not found
   → ✓ Test fails as expected
```

If the test passes immediately, either:
- The behavior already exists (skip this cycle, move to next)
- The test is not asserting the right thing (fix the test)

**Rules:**
- One test per cycle — if you catch yourself writing two `it()` blocks, stop
- The test name describes the behavior, not the implementation
- Import and call the real function/component — don't just assert on mocks

### GREEN — Make It Pass (Minimum Code)

Write the **least amount of code** to make the failing test pass. This is the hardest discipline — resist the urge to write the "complete" solution.

```
🟢 GREEN: "returns empty array when no results match"
   → Added: early return [] when input.length === 0
   → ✓ Test passes
```

Run the full test suite (not just the new test) to make sure nothing broke.

**Rules:**
- Hardcoding a return value is a valid GREEN step if only one test exists
- Don't add error handling, edge cases, or optimizations — those are future cycles
- If you need to touch more than ~20 lines, the test scope is too big — split it

### REFACTOR — Clean Up

With all tests green, improve the code:
- Extract repeated logic
- Rename for clarity
- Remove duplication between production code and test fixtures

```
🔄 REFACTOR: extracted shared mapping logic into mapApiResponse()
   → ✓ All tests still pass
```

Run tests after **every** refactor change, not just at the end.

**Rules:**
- No new behavior in this phase — all tests should pass throughout
- If you spot a missing behavior, add it to the test case plan for a future cycle
- Refactor test code too — DRY up fixtures, improve naming

## 3. Cycle Log

After each cycle, output a structured log entry:

```
── Cycle 1 ──────────────────────────────
🔴 RED:      it('returns empty array when no results match')
             Expected [] but got TypeError: filterResults is not defined
🟢 GREEN:    Created filterResults() with early return for empty input
             +8 lines in src/utils/filterResults.ts
🔄 REFACTOR: (none needed — first cycle)
✅ ALL TESTS: 1 passed, 0 failed
─────────────────────────────────────────

── Cycle 2 ──────────────────────────────
🔴 RED:      it('maps API response to display format')
             Expected {name, price} but got raw API shape
🟢 GREEN:    Added .map() to transform API fields
             +12 lines in src/utils/filterResults.ts
🔄 REFACTOR: Extracted mapToDisplay() helper
✅ ALL TESTS: 2 passed, 0 failed
─────────────────────────────────────────
```

## 4. Completion

After all planned test cases pass:

1. **Final full test run** — run the entire test suite, not just the file you worked on
2. **Coverage check** — verify new code has adequate coverage (invoke dev-quality-check if available)
3. **Review the cycle log** — summarize what was built, how many cycles, total tests added

## When to Break the Cycle

TDD works best for logic-heavy code. For some work, strict TDD adds friction without value:

| Use TDD | Skip TDD |
|---------|----------|
| Utility functions | Pure template/style changes |
| Composables with logic | Config files |
| Store actions/mutations | Type definitions |
| API response transformers | Barrel exports (index.ts) |
| Complex conditionals | Simple prop-forwarding components |

When TDD is skipped, still write tests — just write them alongside or after the code.

## Anti-Patterns

These break the TDD feedback loop and should be avoided:

- **Batch mode** — writing all tests first, then all production code. This loses the design-driving benefit of TDD. One test at a time.
- **Skipping RED** — writing production code before the test. If the test never failed, you don't know if it's actually testing the right thing.
- **Gold plating in GREEN** — adding "while I'm here" code. GREEN means minimum to pass, nothing more. Extras go in future cycles.
- **Skipping test runs** — not running tests between RED and GREEN, or during REFACTOR. The fast feedback loop is the whole point.
- **Mega cycles** — a single cycle that takes 30+ minutes. If the test requires too much setup or the implementation is complex, break the behavior into smaller pieces.

## Do / Don't

- Do: Plan test cases as a list before starting, but write them one at a time
- Do: Run the full test suite after every GREEN and every REFACTOR step
- Do: Use the cycle log to track progress visibly
- Do: Reference unit-test for mock patterns and project conventions
- Do: Break down a large behavior into multiple small cycles
- Don't: Write production code before a failing test exists
- Don't: Write multiple tests before making any pass
- Don't: Add features during REFACTOR — save them for the next cycle
- Don't: Skip the cycle log — it helps catch process violations

## Prerequisites

- Test framework detected (Vitest or Jest)
- `pnpm install` completed in the target project
- unit-test skill available for mock patterns reference
