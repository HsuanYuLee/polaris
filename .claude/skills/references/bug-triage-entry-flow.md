---
title: "Bug Triage Entry Flow"
description: "bug-triage 的 ticket parsing、Issue Type guard、project mapping、existing ROOT_CAUSE detection 與 fast-path routing。"
---

# Bug Entry Contract

這份 reference 負責 bug-triage 的入口判斷。

## Ticket Read

從使用者輸入或 current branch 解析 ticket key。讀 JIRA ticket，至少取得 summary、
description、AC/repro steps、labels、status、assignee、issue type、comments。

Issue Type 不是 Bug 時停止，並建議正確 skill：

- Story / Task：`breakdown` 或已有 work order 時 `engineering`。
- Epic：`refinement` 後 `breakdown`。
- PR review fix：`engineering` revision mode。

## Project Mapping

依 `project-mapping.md` 與 workspace config 判斷 project。常見 signal：

- Summary tag。
- JIRA project key。
- Component / label。
- Config `projects[].tags` / `keywords`。

找到 project 後讀 repo handbook；handbook 不存在時，依 `explore-pattern.md` 小範圍探索。

## Existing Diagnosis

搜尋 JIRA comments 是否已有 `[ROOT_CAUSE]`。若已存在，詢問使用者：

- 重新分析。
- 直接進 `breakdown {TICKET}`。
- 若已有 task.md，直接 `做 {TICKET}`。

不要重複寫 RCA。

## AC-FAIL Detection

若 ticket description 以 `## [VERIFICATION_FAIL]` 開頭，表示 verify-AC 已判定 implementation
drift 並建立 Bug。此時不要做 generic exploration，改走 `bug-triage-acfail-flow.md`。

## Fast Path

只有同時符合以下條件才 fast path：

| Criteria | Required |
|---|---|
| root cause clarity | 從 ticket description 可明顯看出 |
| scope | single file and small change |

不確定時走 full path。Fast path 仍必須產出 Root Cause / Impact / Proposed Fix，且仍要 RD
confirmation hard stop。
