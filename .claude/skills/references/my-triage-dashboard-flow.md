---
title: "My Triage Dashboard Flow"
description: "my-triage 的 assigned work JIRA scan、status verification、GitHub progress enrichment、grouping/sorting 與 dashboard output。"
---

# My Triage Dashboard Contract

這份 reference 負責 JIRA / GitHub 盤點與 dashboard 排序。

## Assigned Work Query

掃描 current user 的 active work：

- Epic
- Bug
- 無 parent / Epic Link 的獨立 Task 或 Story
- status 不在 Done、Closed、Launched、完成
- project 在 configured JIRA projects

Fields 至少包含 summary、status、priority、created、duedate、story points、fixVersions、
issuetype、parent。Story points field 依 `jira-story-points.md` dynamic detection。

過濾：

- 保留所有 Epic。
- 保留所有 Bug，包含 Epic child Bug。
- 只保留無 parent 的 Task/Story。

## Status Verification

JIRA board column 可能與 actual status 不同步。檢查：

- `status.statusCategory.key == "done"`：標記已完成並從 active list 移除。
- `status.statusCategory.key == "indeterminate"` 且 status name 包含 stage/waiting：
  標記等待部署或 stage。

狀態不同步 items 要在 dashboard 顯示 excluded section。

## GitHub Enrichment

只對 In Development items 查 GitHub progress：

- open PR
- merged PR
- CI status
- review comments
- no PR

大型查詢可委派 read-only sub-agent，dispatch 必須含 `sub-agent-roles.md` Completion Envelope。

## Grouping

Dashboard group order：

1. resume candidates
2. Bugs by priority desc, created asc
3. In Development by PR progress
4. Todo Highest by created asc
5. Todo High by created asc
6. Todo Medium / Low by created asc

In Development progress order：

1. PR merged / approved
2. PR open and CI pass
3. PR open with CI red or review comments
4. no PR

## Suggested Next Action

建議要可路由：

- P0/P1 Bug → `engineering`
- PR blocked → `engineering` revision
- PR waiting review → `check-pr-approvals`
- unestimated Highest Epic → `breakdown`
- team-level scheduling → `sprint-planning`
