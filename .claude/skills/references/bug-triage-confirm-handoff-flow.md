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
依 `workspace-language-policy.md` 或 external write gate blocking validation；validation
未通過時停在 diagnosis，不得先寫 JIRA 再補 gate。

不可送出未通過 language gate 的 diagnostic comment。

Bug 不要求 `refinement.md` / `refinement.json`，但仍不可跳過 handoff。Bug 的
source-specific handoff 是：

- confirmed JIRA comment containing `[ROOT_CAUSE]`, `[IMPACT]`, `[PROPOSED_FIX]`
- local final-comment artifact path when available
- evidence artifact path when investigation produced one

缺 confirmed RCA comment 時，`breakdown` 必須 fail-stop 並 route back to `bug-triage`。
即使 confirmed RCA 已存在，若尚未有 authoritative task work order，下一步仍只能是
`breakdown`，不能暗示可直接進 `engineering`。

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

- `breakdown {TICKET}`：預設下一步；產 estimate、測試計畫、Design Doc、task packaging。
- `做 {TICKET}`：只有已存在 authoritative task work order 時才合法；engineering 仍會再檢查來源。

AC-FAIL Bug 要額外標明 source AC ticket、feature branch、以及 re-run verify-AC 的路由。

## Error Handling

JIRA API failure：回報 failed operation 與 manual fallback content。

Explorer inconclusive：呈現已找到的 facts，請使用者提供 file/module/feature hints。

Root cause changed after confirmation：帶新資訊從 root cause analysis 重跑。
