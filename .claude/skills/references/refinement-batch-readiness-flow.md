---
title: "Refinement Batch Readiness Flow"
description: "refinement batch readiness scan：批次掃 Epic 完整度、產生 readiness table、JIRA label/comment 與下一步路由。"
---

# Batch Readiness Flow

## Entry

適用於 sprint planning 前掃多張 Epic，例如「這幾張準備好了嗎」、「batch refinement」、
「sprint prep」。輸入是多個 Epic keys。

## Parallel Read

可平行讀每張 Epic：

1. `getJiraIssue` 讀 Summary、Description、Comments、Labels。
2. 用 `project-mapping.md` 確認 project。
3. 用 `epic-template.md` readiness checklist 檢查背景、AC、scope、edge cases、Figma /
   API / dependency / out-of-scope。

Sub-agent 必須使用 Completion Envelope。

## Summary Table

彙整：

```markdown
## Refinement Readiness — Sprint 準備掃描

| # | Epic | Summary | 完整度 | 狀態 | 缺項 | 建議 |
|---|---|---|---|---|---|---|
```

狀態：

- Ready：必要項完整，可進 breakdown。
- Almost：少量缺口，可快速補。
- Needs work：需要 Phase 1。

## Writes After Confirmation

使用者確認後才更新：

- Ready：加 `refinement-ready`，移除 `needs-refinement`。
- Not ready：加 `needs-refinement`，移除 `refinement-ready`。
- JIRA comment 寫 checklist 與建議。

## Next Route

- Ready -> `breakdown`。
- Needs work -> Phase 1。
- Planning session -> `sprint-planning`。
