---
title: "Standup Planning Flow"
description: "standup 的 YDY merge/dedup、plan vs actual、TDT candidates、PR status、Polaris backlog 與 BOS collection。"
---

# Standup Planning Contract

這份 reference 負責把原始資料整理成 YDY / TDT / BOS。

## YDY Merge And Dedup

同一 ticket 同時出現在 git 與 JIRA 時，合併成一行：JIRA status/title 為主，git commit
summary 為輔。

依 config teams 分組。每個 team 對應一組 JIRA project keys；沒有 ticket 的相關活動與會議
放入 meeting 或 custom group。

Ticket 格式使用 `[KEY title](https://{jira.instance}/browse/KEY) — 動作摘要`。

## Plan Vs Actual

從當月 Confluence standup page 讀取今天以前最近一筆 entry，解析上一筆 TDT section。

Skip 條件：

- 沒有上一筆 standup。
- 上一筆沒有 TDT section。

比較規則：

- 今日 YDY ticket 命中上一筆 TDT ticket：標記 planned。
- 今日 YDY ticket 不在上一筆 TDT：標記 additional。
- 上一筆 TDT ticket 未出現在今日 YDY：列為 loss，原因不明時詢問使用者。
- Meeting items 不參與 planned / additional / loss。

呈現時讓使用者確認標記是否合理。

## TDT Candidates

優先從 JIRA open sprint 搜尋 current user 的 in-progress / code review / todo / planned
tickets。Status set 必須包含新 sprint 常見的待辦狀態，避免 TDT 空白。

JIRA query 為空時 fallback：

1. 從 YDY JIRA results 中選仍在進行中的 tickets。
2. 仍為空時詢問使用者今天預計做什麼。

Sorting：

1. 有今日或昨日 triage state 時，依 triage rank 排序，並附 progress indicator。
2. 無 triage state 時，priority 高的在前。
3. In development 優先於 not started。
4. 有 dependency 時標註 unblocks。

## PR Status Supplements

自己的 open PR：

- changes requested：TDT 修 review comments。
- CI fail：TDT 修 CI。
- no approvals：TDT 追 review。
- enough approvals：TDT 待 merge。
- draft：跳過，通常由 JIRA 開發項目覆蓋。

Review-requested PRs 有結果時，加入 TDT 的 PR Review 區塊。

## Polaris Backlog

讀取 `{base_dir}/.claude/polaris-backlog.md` 的 High priority unfinished items。最多列 top 3，
放入「AI 工具改善（NO-JIRA）」區塊。

若 framework skills/rules 有 uncommitted changes，提醒有框架改動未 commit。

## BOS

BOS sources：

- JIRA status = `DISCUSS` 的 assigned tickets。
- 前幾天 standup BOS 中持續存在的 blocker。
- 使用者在對話中的口述 blockers。

沒有 blockers 時，保留 BOS heading，不寫「無」。
