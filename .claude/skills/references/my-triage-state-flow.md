---
title: "My Triage State Flow"
description: "my-triage 的 .daily-triage.json schema、寫入時機、standup TDT handoff、progress enum 與 stale state handling。"
---

# My Triage State Contract

這份 reference 負責 `.daily-triage.json` state 與 standup handoff。

## Write Timing

Dashboard render 與 triage state write 必須同一輪完成，避免對話中斷造成 dashboard 有產出
但 state 缺失。

若今天已有 triage state，先提示「今天已盤點過，要重新掃嗎？」；使用者確認後才覆寫。

## Path

State path 從 workspace config 的 company/project 目錄推導。檔案只保留最新一次結果。

## Schema

```json
{
  "date": "2026-03-31",
  "items": [
    {
      "key": "TEAM-201",
      "summary": "商品頁問題",
      "type": "Bug",
      "priority": "Highest",
      "status": "In Development",
      "sp": null,
      "progress": "pr_open",
      "rank": 1
    }
  ]
}
```

`type` values：

- Epic
- Bug
- Task
- Story

`progress` values：

- `pr_merged`
- `pr_approved`
- `pr_open`
- `pr_blocked`
- `in_dev`
- `not_started`

## Standup Handoff

`standup` TDT 讀 `.daily-triage.json`：

- 依 triage rank 排序今天要做的 items。
- 比對 triage progress 與今日實際 progress。
- 無 triage state 時，standup 使用原本 git branch + JIRA status 邏輯。

## Progress Comparison

| Triage Progress | Actual Progress | Signal |
|---|---|---|
| `not_started` | `in_dev` or higher | ahead |
| `in_dev` | `pr_open` or higher | ahead |
| `pr_open` | `pr_approved` or `pr_merged` | ahead |
| `pr_blocked` | `pr_open` after blocker cleared | ahead |
| same level | same level | normal |
| `pr_open` over two days | still `pr_open` | stuck |
| `in_dev` over three days | still `in_dev` | behind |
