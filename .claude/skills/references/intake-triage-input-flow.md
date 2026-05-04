---
title: "Intake Triage Input Flow"
description: "intake-triage 的 ticket key/JQL/Slack/Epic input parsing、JIRA batch fetch、standard record、Epic child convergence 與 theme/lens detection。"
---

# Intake Input Contract

這份 reference 負責 intake-triage 的輸入解析與 ticket 標準化。

## Input Modes

| Input | Handling |
|---|---|
| ticket key list | extract `[A-Z]+-\d+` keys |
| JQL | use directly for JIRA search |
| Slack URL | read thread/message, extract ticket keys |
| Epic key | expand active child tickets |

無法判斷 input type 時，直接詢問使用者。

## Theme Detection

從使用者訊息或 ticket summaries 偵測 theme：

- `seo`
- `cwv`
- `a11y`
- `generic`

同批 ticket 可混合 theme；每張 ticket 最終都要標示使用的 lens。無法判斷時用 `generic`。

## JIRA Fetch

用 key list 或 JQL 批次讀 JIRA。Fields 至少包含：

- summary
- description
- status
- priority
- issuetype
- created
- story points field
- issue links
- labels
- parent
- comments when needed

Story points field 依 `jira-story-points.md` dynamic detection。結果過大時，可派 sub-agent
擷取結構化資料，但主 session 只接收 normalized JSON。

## Standard Record

每張 ticket 標準化為：

- key
- summary
- description
- AC
- status
- priority
- issue type
- story points
- labels
- linked issues
- parent key
- created time

缺欄位保留 null，不猜。

## Epic And Child Convergence

同批同時出現 Epic 與它的 child tickets 時：

- Epic 不進五維 scoring。
- Epic 轉成摘要行，顯示 child count、in-batch count、estimated count、progress。
- Sorting and verdict 只看 child tickets。

只有 Epic、child 不在批次時，正常分析 Epic 本身。

只有 child、Epic 不在批次時，正常分析 child，輸出時標註 parent。
