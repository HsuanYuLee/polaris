---
title: "Refinement Phase 0 Discovery Flow"
description: "refinement Phase 0：RD 主動發現 tech debt / code smell / performance issue，分析價值並產 JIRA ticket 草稿。"
---

# Phase 0 Discovery Flow

## Entry

適用於 RD 主動提出 code smell、效能瓶頸、tech debt、架構不合理，例如「想重構」、
「這段 code 很亂」、「頁面很慢」。

## Problem Analysis

用 `explore-pattern.md` 自適應探索 codebase。單一模組直接讀；跨模組可 dispatch
sub-agent。輸出：

- 位置。
- 被引用範圍。
- 問題列表。
- 使用者體驗 / 穩定性 / 維護性影響。

## Impact Assessment

用非技術人員可理解的方式寫：

- severity。
- 不修的風險。
- 修了的好處。
- 建議投入與 ROI。

## Ticket Draft

產出 JIRA ticket 草稿：

- Summary。
- Description：背景、目標、AC、scope、QA 影響範圍。
- 建議 issue type / source，例如 Tech maintain 或 Tech bug。

## Create After Confirmation

使用者確認後才 create JIRA issue。建立後建議下一步：

- 簡單：Phase 2 討論方案後估點 / 開工。
- 複雜：Phase 2 / SA-SD / breakdown。
