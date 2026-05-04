---
title: "Bug Triage Confirm Handoff Flow"
description: "bug-triage 的 RD confirmation hard stop、JIRA ROOT_CAUSE comment、handbook observation processing、handoff message 與 error handling。"
---

# Confirmation And Handoff Contract

這份 reference 負責 RD confirmation、JIRA write、handoff。

## RD Confirmation

向使用者呈現：

- Root Cause
- Impact
- Proposed Fix
- evidence artifact path when available

這是 hard stop。使用者明確確認前，不得寫 JIRA、不得進 breakdown、不得開始 engineering。

若使用者修正分析，帶新資訊重跑 root cause analysis。最多 re-analyze 兩輪；仍不清楚時，
建議人工 code confirmation 或 exploratory branch。

## JIRA RCA Comment

確認後寫 JIRA comment，包含：

- `[ROOT_CAUSE]`
- `[IMPACT]`
- `[PROPOSED_FIX]`

這個 comment 是 `breakdown` Bug path 的輸入。送出前，把 final comment 寫成 artifact，
依 `workspace-language-policy.md` 或 external write gate blocking validation。

不可送出未通過 language gate 的 diagnostic comment。

## Handbook Observations

Explorer 若回報 handbook gaps 或 stale entries，依 `explore-pattern.md` 處理：

- gaps：寫入 workspace-owned handbook appropriate sub-file。
- stale：mark or fix。

不要寫 repo-local compatibility overlay 作為 source of truth。

## Handoff Message

完成後回報：

| Item | Meaning |
|---|---|
| Root Cause | confirmed |
| JIRA Comment | written or failed |
| Proposed Fix | concise scope summary |
| Evidence artifact | path or fast path none |

Next step：

- `breakdown {TICKET}`：估點、測試計畫、Design Doc、task packaging。
- `做 {TICKET}`：若已有 plan/work order，engineering 會檢查來源合法性。

AC-FAIL Bug 要額外標明 source AC ticket、feature branch、以及 re-run verify-AC 的路由。

## Error Handling

JIRA API failure：回報 failed operation 與 manual fallback content。

Explorer inconclusive：呈現已找到的 facts，請使用者提供 file/module/feature hints。

Root cause changed after confirmation：帶新資訊從 root cause analysis 重跑。
