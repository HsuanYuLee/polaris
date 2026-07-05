---
title: "Refinement Bug Source Mode"
description: "Bug source mode 的 reproduction、RCA、source PR 與 severity/impact assessment handoff contract。"
---

# Refinement Bug Source Mode

Bug source mode 是 `refinement` 的 source mode，不是獨立 planning skill。當 resolver 或
caller 明確提供 `source_kind=bug`，或 JIRA issue type 為 `Bug` 時，`refinement` 必須產出
同一套 canonical `refinement.md` + `refinement.json` artifact，供 `breakdown` deterministic
消費。

## Trigger

Bug source mode 只能由明確 Bug signal 觸發：

- `source_kind=bug`
- `source.type=bug`
- JIRA `issuetype.name=Bug`

Negative-tone prose、一般 support request、Epic / Story / Task key 不得只靠語氣推成 Bug
source。Slack URL + fix intent + no JIRA key 的 strategist preprocessing 仍先建立 Bug ticket，
再把該 Bug ticket 交給 `refinement`。

## Required Sub-Steps

Bug source mode 必須完成四個 sub-step，並把結果寫入 `refinement.json` Bug-specific 欄位：

| Sub-step | Required output |
|----------|-----------------|
| reproduction | `reproduction_steps[]`、reproducible 判定、evidence link 或無法重現理由 |
| rca_investigation | `root_cause`，含觀察事實與造成錯誤的系統路徑 |
| source_pr_identification | `source_pr`，若找不到則寫明 searched refs / commits |
| severity_impact_assessment | `severity`、`impact_scope`、`regression` |

任何 required output 缺失時，不可 LOCK / handoff breakdown；應停在 refinement artifact
修補，或把無法取得的證據明確標成 blocked input。

## Non-Bug Sources

Non-Bug source 不應填 Bug-specific 欄位，也不應執行 Bug-only sub-step。這保留 DP / Epic /
Story / Task / topic refinement 的既有行為。

## Detector Helper

`scripts/lib/refinement-bug-source-detector.py` 是 deterministic helper，用於 selftest 與
adapter 前置判斷。它只做明確 signal 判斷，不連線 JIRA，也不從自然語氣推論 bug。
