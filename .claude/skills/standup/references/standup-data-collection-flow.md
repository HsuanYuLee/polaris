---
title: "Standup Data Collection Flow"
description: "standup 的 config/defaults、auto-triage guard、日期計算、git/JIRA/Calendar YDY data collection。"
---

# Standup Data Contract

這份 reference 負責 standup 原始資料收集。

## Config And Defaults

讀取 workspace config，取得：

- `jira.instance`
- `confluence.space`
- `github.org`
- `jira.projects`
- `projects[].path`
- `teams`

Config 不存在時使用 `workspace-config.yaml` 的 `defaults` 區塊 fallback。GitHub username 動態取得。Timezone 預設
Asia/Taipei。

## Triage State：有就用，沒有就說

收集 standup 資料前，檢查 `{company}/.daily-triage.json`。存在且 `date` 是今天就拿它當排序
依據；missing 或 stale 就照常收集，並在報告裡寫明「今日沒有 triage state」。

以前這裡寫的是「missing 就去執行 my-triage 產生一份」。那支 skill 已經不在了，而一句指向
不存在的東西的指示，讀的人只會照做然後自己撞上。**沒有 triage state 是一個要被說出來的
狀態，不是一個要被自動補上的洞**——排序的判斷本來就不屬於 standup。

## Date Semantics

Standup 有三個日期：

| Date | Meaning |
|---|---|
| `PRESENT_DATE` | 報告標題日期與當天會議來源 |
| `YDY_DATE` | 收集 git / JIRA / Calendar activity 的日期 |
| `TDT_PLAN_DATE` | TDT 工作項目的規劃目標日 |

週一：YDY 是上週五；PRESENT 與 TDT 是週一。

週二到週四：YDY 是昨天；PRESENT 與 TDT 是今天。

週五：YDY 是週四；PRESENT 是週五；TDT work target 是下週一。

使用者指定日期時，以使用者指定為準，並明確回報三個日期。

## Git Activity

掃描 config projects 指定的 local git repos；若 config 未列，fallback 掃 company base
directory 下有 `.git` 的 repos。

收集 YDY_DATE 使用者 authored commits，排除 merge commits。從 commit messages 擷取符合
configured JIRA project keys 的 ticket keys，並記錄 repo 與 commit summary。

## JIRA Activity

用 Atlassian MCP 查詢 YDY_DATE 由 current user 更新的 tickets，限制在 configured JIRA
projects。需要欄位包含 summary、status、issue type、priority、parent。

JIRA response 過大被落檔時，用 deterministic parser 提取 key、summary、status、parent；
不要把整個大型 response 讀進 context。

用途：

- 補 git 沒抓到的 status-only work。
- 補 ticket title。
- 提供 TDT fallback candidates。

## Calendar Activity

用 Calendar MCP 分別讀 YDY_DATE 與 PRESENT_DATE。YDY meetings 放到 YDY；PRESENT_DATE
meetings 放到 TDT。週五 TDT meetings 仍是週五當天會議，不是下週一。

過濾 all-day events。列出 meeting title、日期、weekday、time range、timezone、location
when available。Calendar MCP 沒有 `conferenceData` 時，不猜 Meet URL。
