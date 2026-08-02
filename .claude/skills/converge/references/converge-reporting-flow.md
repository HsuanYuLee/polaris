---
title: "Converge Reporting Flow"
description: "converge 的 plan presentation、before/after rescan report、Markdown artifact requirements、Slack review follow-up 與 completion summary。"
---

# Converge Reporting Contract

這份 reference 負責 converge 的呈現與收斂報告。

## Plan Presentation

Plan 必須包含：

- scan date
- scanned ticket counts by type
- gap / ready / skipped counts
- quick wins
- implementation items
- planning items
- waiting / skipped items
- ready items
- proposed route for each actionable item

每個 item 顯示 ticket key、summary、gap type、evidence、route。等待使用者確認或調整。

## Execution Updates

每完成一張 ticket，立即報告：

- ticket
- route
- result
- PR / JIRA / artifact link when produced
- remaining selected item count

不要等整批結束才回報所有結果。

## Rescan Report

執行完畢後重跑 scan，產生 before/after 矩陣：

| Column | Meaning |
|---|---|
| Ticket | ticket key |
| Before | original gap state |
| After | current gap state |
| Action Taken | downstream route and result |

Summary 顯示 resolved、skipped、failed、blocked counts。

## Artifact Rules

若產生 specs Markdown artifact：

- follow `starlight-authoring-contract.md`
- include frontmatter when docs-manager content requires it
- link raw evidence instead of embedding large logs
- scrub secrets and personal tokens

## External Follow-Up

Slack review nudges and JIRA/PR-facing text are external writes. Before sending:

- run `workspace-language-policy.md`
- confirm destination / audience
- preserve downstream skill ownership

`REVIEW_STUCK` follow-up should route through `check-pr-approvals`.
