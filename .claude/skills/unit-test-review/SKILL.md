---
name: unit-test-review
description: >
  Review existing unit test quality in Vue/Nuxt + Vitest projects. Produces a structured report
  with severity-rated findings, scoring, and missing scenario analysis.
  Use when asked to: "unit test review", "review tests", "check test quality",
  "測試審查", "review 測試", "測試品質", "review unit test", "檢查測試品質".
  Does NOT write new tests — use unit-test skill for writing tests.
---

# Unit Test Review

## Input

Provide one of:
- Test file path (also reads corresponding SUT automatically)
- PR diff (auto-detects test files)
- Directory path (batch review all tests in that directory)

## Workflow

### Step 1: Collect context
- Read the test file
- Read the corresponding SUT (source under test)
- Check `vitest.config.ts` and `vitest.setup.ts` for global setup

### Step 2: Structural scan
- File naming follows `*.test.ts` convention?
- Imports correct (vitest, test-utils)?
- describe/it structure reasonable?

### Step 3: Per-test analysis

**Three questions for each test:**
1. What logic does this unit do **itself**?
2. What belongs to **others**? → Should be stubbed/mocked
3. What am I asserting? → Does the assertion match "own logic"?

Apply the full checklist from `references/checklist.md` to each test case.
Check each test is at the correct layer (component logic → component test, composable logic → composable test).

### Step 4: Cross-test analysis
- Any important SUT scenarios not covered at all?
- Duplicate logic that can be extracted?
- Mock strategy consistent across tests?

### Step 5: Produce report using the output format below

## Severity Levels

| Level | Definition | Action |
|---|---|---|
| **CRITICAL** | Test cannot correctly verify behavior; may produce false positives | Must fix immediately |
| **HIGH** | Seriously insufficient test quality, high maintenance cost | Fix in this PR |
| **MEDIUM** | Improvable practice, affects readability/maintainability | Suggest, can defer |
| **LOW** | Style or convention issue | Optional |
| **INFO** | Positive observation or suggestion | Reference only |

## Output Format

```markdown
## Unit Test Review Report

### Summary
- **測試檔案**：`path/to/test.test.ts`
- **被測模組（SUT）**：`path/to/module.ts`
- **測試數量**：X 個
- **總體評價**：一句話總結
- **品質分數**：XX / 50

### Findings

#### CRITICAL
- [ ] **[Issue title]** (line XX)
  Description, impact, suggested fix

#### HIGH
- [ ] **[Issue title]** (line XX)

#### MEDIUM
- [ ] **[Issue title]** (line XX)

#### LOW
- [ ] **[Issue title]** (line XX)

### 缺失的測試場景
- SUT 中 `functionName` 的 error path 未測試
- 當 input 為 null 時的行為未驗證

### 正面觀察
- 良好的 AAA pattern 使用
- Mock 策略清晰一致

### 分數明細

| 維度 | 分數 | 說明 |
|---|---|---|
| 結構與組織 | /10 | |
| 測試品質與隔離 | /10 | |
| 斷言品質 | /10 | |
| Mocking 實踐 | /10 | |
| 覆蓋完整性 | /10 | |
| **總分** | **/50** | |
```

## Reference

See `references/checklist.md` for the full review checklist covering:
1. Test structure & organization
2. Test quality & isolation
3. Assertion quality
4. Mocking best practices (mock boundary principle, strategy comparison, Vue/Nuxt patterns)
5. Anti-patterns quick reference
6. Vue/Nuxt specific checks
7. Coverage considerations
