---
name: end-of-day
description: >
  End-of-day routine: runs /my-triage then /standup in sequence.
  Triage first (prioritize all assigned Epics/Bugs/Tasks, write .daily-triage.json),
  then standup (collect activity, format report, push to Confluence).
  Use when: (1) user says "下班", "收工", "準備明天的工作", "end of day", "EOD",
  "明天 standup", "寫明天的 standup", (2) user wants to wrap up daily work.
metadata:
  author: Polaris
  version: 1.0.0
---

# End of Day — 下班收工流程

一鍵完成每日收工：盤點工作 → 寫 standup。

## Workflow

### Step 1：執行 `/my-triage`

讀取 `skills/my-triage/SKILL.md` 並完整執行所有步驟：
1. 撈取 assigned active 工作項目（Epic + Bug + 孤兒 Task/Story）
2. 狀態驗證
3. GitHub 進度補充
4. 排序與分群
5. 產出 Dashboard **並同時寫入** `{company}/.daily-triage.json`

呈現 Dashboard 給使用者確認。使用者可以在這裡調整排序或補充資訊。

### Step 2：執行 `/standup`

Triage 完成後，讀取 `skills/standup/SKILL.md` 並完整執行所有步驟：
1. 計算日期（預設為明天的 standup）
2. 收集 git activity
3. 收集 JIRA activity
4. 收集 Google Calendar meetings
5. 合併去重 YDY
6. Plan vs Actual comparison
7. 收集 TDT candidates（此時 `.daily-triage.json` 已存在，TDT 按 triage rank 排序）
8. 收集 BOS
9. 格式化呈現，等使用者確認
10. 推送 Confluence

## Do / Don't

- Do: 按順序執行，triage 必須先完成才能跑 standup（standup 依賴 triage state）
- Do: 兩步之間允許使用者介入調整（不是完全自動跑完）
- Don't: 跳過 triage 直接跑 standup — 那樣 TDT 沒有 triage rank
- Don't: 如果 triage state 已是今天的，不重跑 — 提示「今天已盤點過」，直接進 standup

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-31 | Initial release — chain my-triage → standup |
