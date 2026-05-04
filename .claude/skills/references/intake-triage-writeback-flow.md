---
title: "Intake Triage Writeback Flow"
description: "intake-triage 的判決表呈現、RD confirmation、JIRA intake labels/comments、PM-friendly Slack summary 與 workflow handoff。"
---

# Intake Writeback Contract

這份 reference 負責呈現、確認、JIRA 寫回、Slack summary。

## Decision Table

判決表包含：

- batch summary counts
- Do First / Do Soon / Do Later / Skip / Hard Blocker groups
- readiness visual
- effort
- impact visual
- lens tag
- global rank
- PM-friendly reason
- missing questions for Skip
- dependency chains
- duplicate pairs
- Epic summary rows when applicable

全域 rank 連續編號，跨 verdict 不重置。Epic summary row 不佔 rank。

## RD Confirmation

呈現後等待 RD：

- confirm
- adjust verdict
- adjust rank
- skip writes

調整後重新排序並再次呈現。未確認前不寫 JIRA、不發 Slack。

## JIRA Labels

只移除舊 `intake-` prefix labels，保留其他 labels。新增：

| Verdict | Label |
|---|---|
| Do First | `intake-do-first` |
| Do Soon | `intake-do-soon` |
| Do Later | `intake-do-later` |
| Skip | `intake-skip` |
| Hard Blocker | `intake-blocked` |

## JIRA Comment

每張 ticket 寫 intake analysis comment，包含：

- verdict
- RD-facing ranking reason
- readiness score and missing fields
- effort and evidence
- impact and lens evidence
- dependencies
- hard blocker check
- PM questions for Skip

Comment 是 direction guidance，不是 implementation spec。不要寫 code-level file paths。

送出前每張 comment 都要 language gate。

## Slack Summary

產生 PM-friendly summary，語言避免 code-level details。Sections：

- this sprint / do first
- later
- need spec
- suggested not to do
- dependency reminder

RD 確認後才送出。Destination options：

- configured Slack channel
- DM resolved by user search
- no send

每則 Slack message 送出前跑 language gate，並遵守 `slack-message-format.md`。

## Workflow Handoff

Labels and comments feed downstream：

- `intake-do-first` 可被 `my-triage` / `engineering` 優先讀取。
- `intake-do-soon` 進 sprint planning candidate。
- `intake-skip` 等 PM 補規格後重跑 intake 或進 refinement。
- `intake-blocked` 留作不做或需 PM decision 的紀錄。

`intake-` labels 與 `needs-refinement` / `refinement-ready` 正交。
