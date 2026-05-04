---
title: "SASD Review Publish Flow"
description: "sasd-review 的 scope calibration、user confirmation、JIRA/Confluence publish、language gate 與 completion report。"
---

# SASD Publish Contract

這份 reference 負責 scope calibration、使用者確認與外部發布。

## Scope Calibration

| Scope | Output |
|---|---|
| small, single module, up to 3 points | brief implementation plan |
| medium, 5-13 points | standard SA/SD |
| large, over 13 points or cross-service | full SA/SD with alternatives and risks |

Small plan 仍要包含 requirements、dev scope、task estimate、verification。

## User Review

產出 draft 後，詢問：

- 哪些 sections 要調整。
- Approach 是否正確。
- 是否加到 JIRA comment。
- 是否建立 Confluence SA/SD page。
- 是否進 `breakdown`。

使用者確認前，不寫外部系統。

## JIRA Publish

若使用者要加到 JIRA，將 SA/SD 轉成適合 JIRA comment 的格式。送出前依
`workspace-language-policy.md` 或 external write gate blocking validation。

## Confluence Publish

若使用者要建立 Confluence page，依 `sasd-confluence.md` 決定位置：

- configured SA/SD folder
- current year child page
- title format `[TICKET] summary SA/SD`

使用 `confluence-page-update.md` 的 search/create/update flow，處理 version conflict。

Confluence body 送出前，同樣要跑 language gate。

## Decision Audit

重要技術選型或 approach trade-off 可同步產出 Decision Record；格式依
`decision-audit-trail.md`。若寫入 JIRA，仍需 language gate。

## Completion Report

回報：

- SA/SD status。
- total estimate。
- chosen approach。
- unresolved questions。
- JIRA / Confluence publish status and links。
- suggested next command, usually `breakdown {TICKET}`。
