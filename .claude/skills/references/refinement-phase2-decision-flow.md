---
title: "Refinement Phase 2 Decision Flow"
description: "refinement Phase 2：需求已明確時的技術方案討論、trade-off 比較與 Decision Record。"
---

# Phase 2 Decision Flow

## Entry

適用於需求與 AC 已明確，但做法需要討論：架構、第三方、migration、重構策略、CI /
delivery 流程、framework contract。

## Flow

1. 讀 source container / ticket / current refinement artifact。
2. 補必要 codebase exploration 或 external research。
3. 列出 2-3 個 option。
4. 每個 option 寫：
   - approach。
   - pros。
   - cons。
   - risk。
   - effort。
   - rollback / migration consideration。
5. 明確標示 recommendation 與 confidence，但讓使用者確認 final decision。

## Decision Record

使用者確認後寫入 source container：

```markdown
## Decision Record — {date}

### Context

### Options Considered

### Decision

### Trade-offs

### Follow-up / Validation
```

Framework contract change 必須 target-state-first：

- final source of truth。
- runtime ownership。
- handoff boundary。
- steady-state path。
- 若有 temporary compatibility，列 owner、移除條件、驗證方式、follow-up task。

未確認前不可改 skill / rule / reference / validator。
