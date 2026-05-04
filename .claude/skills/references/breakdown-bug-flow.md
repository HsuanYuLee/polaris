---
title: "Breakdown Bug Flow"
description: "breakdown Bug path：讀取 bug-triage RCA、估點、簡單修復規劃與複雜 bug 轉 planning flow。"
---

# Bug Flow

## Entry

只處理 JIRA Issue Type = Bug。先檢查 JIRA comments 是否存在 `[ROOT_CAUSE]`；沒有時
停止，請使用者先跑 `bug-triage {TICKET}`。

讀取 bug-triage 產出的結構化資訊：

- `[ROOT_CAUSE]`：根因、檔案位置、問題描述。
- `[IMPACT]`：影響範圍、變更風險。
- `[PROPOSED_FIX]`：修正方向、預估改動範圍。

## Estimate And Route

依 `estimation-scale.md` 評估：

| Complexity | Condition | Route |
|---|---|---|
| simple | 1-2pt and changes <= 3 files | estimate ticket directly, no sub-task |
| complex | 3+pt or cross-module | continue through Planning Flow Step 6 with RCA context |

Simple bug preview 必須包含：

- Root Cause summary。
- Proposed Fix 與涉及檔案。
- Story Points 與估點理由。
- Local verification：重現原 bug、修正後預期、邊界場景。
- Post-deploy verification if needed。

## Confirmation And Writes

使用者確認前不可寫 JIRA。確認後：

1. 用 `jira-story-points.md` 查 Story Points 欄位 ID。
2. 更新 bug ticket estimate 並回查驗證。
3. 將 simple bug planning preview 寫入 JIRA comment。

Handoff：

- simple bug：提示 `做 {TICKET}`。
- complex bug：切到 `breakdown-planning-flow.md`，從拆子任務開始，帶入 RCA；不重跑
  refinement-style 探索。
