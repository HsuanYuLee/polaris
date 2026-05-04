---
title: "My Triage Resume Flow"
description: "my-triage 的 zero-input routing、branch-ticket context、Hot memory、recent checkpoints、WIP branch scan 與 resume candidate 排序。"
---

# My Triage Resume Contract

這份 reference 負責 my-triage 的 cross-session resume scan。

## When To Run

在完整 JIRA dashboard 前先跑。它處理「之前做的事」線索；Session Start Fast Check
處理「目前 working tree 改了什麼」。若 Session Start 已報告 WIP branch、stash、
uncommitted files，只引用結果，不重印 file list。

## Branch-Ticket Context

檢查 current branch 是否含 ticket key pattern `[A-Z]+-\d+`。

有 ticket key 時讀 JIRA status：

- In Development / 進行中：列為「上次未完成」第一候選。
- Code Review / In Review：建議 `check-pr-approvals`。
- Done / Closed：跳過。
- 其他：列入 dashboard，由使用者選擇。

若 PR open 且 changes requested，建議 `engineering` revision mode。若 PR open 且無 valid
approval，建議 `check-pr-approvals`。

## Hot Memory Scan

讀 workspace project memory 的 Hot index，尋找含以下 signal 的 entries：

- 下一步
- 待做
- 待續
- pending
- next step
- in-progress

只納入最近 30 天更新的 entries。Title 使用 memory one-liner，不重新詮釋。

## Checkpoint Scan

讀最近 7 天 checkpoints，擷取 topic、ticket、或 filename keyword，列為 resume candidates。
路徑依 `polaris-project-dir.md` 與 workspace config 推導，不使用 user-specific absolute path。

## WIP Branch Scan

列出 `wip/*` branches，topic 從 branch suffix 推導。只顯示 branch name 與簡短狀態。

## Sorting

Resume candidates 排序：

1. current branch-ticket context
2. Hot memory by last triggered / modified time
3. recent checkpoints by modified time
4. WIP branches by branch HEAD time

沒有 candidate 時，不印 resume section。
