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

讀取 `issues/` 底下還沒收斂的單。最多列 top 3，
放入「AI 工具改善（NO-JIRA）」區塊。

若 framework skills/rules 有 uncommitted changes，提醒有框架改動未 commit。

## BOS

### 准入判準：我在等誰

<!-- STANDUP-CONTRACT: bos-admission -->

**BOS 是「我在等某個人、或某個我動不了的東西」，不是「這件事還沒做完」。**

一件我自己動手就能推進的事**不是 blocker**，不論它多久沒動、多讓人煩——它是待辦，屬 TDT。
2026-08-12 把「兩張子單的 resolution 被 Automation for Jira 誤設成完成」寫進 BOS，使用者
的回覆是：「卡關你要留需要其他人協助的事，你列的不是，只是待辦。」那件事我自己改得掉。

| 這件事 | BOS？ |
|---|---|
| 等 reviewer 看我的 PR | 是 —— 我按不了那個按鈕 |
| 等 PM 拍板兩個方案選哪個 | 是 —— 只有他知道 |
| 等一個我沒有權限的環境或憑證 | 是 |
| CI 紅了要修 / lint 沒過 / 資料被誤設要清 | 否 —— 我自己動得了 |
| 一張單已經 merge，後面由別人接（QA 排程、排 release） | **否** —— 見下 |

**最後一列是判準會判錯的地方，所以指名。** 「等 QA 排程」字面上完全符合「需要別人動」，
但它不是 blocker：那張單對我而言已經結束，我沒有任何東西卡在那裡等它回來。判準的重點是
**我在等**，不是**有人要動**。分辨法是問一句：那件事回來之後，我手上會多出什麼工作？答案
是「沒有」就不是 BOS。

**空著是一個答案。** 沒有符合判準的東西時保留 heading 且留白，不寫「無」，也不要因為那一格
空著就把待辦搬過去填。

### BOS sources

- JIRA status = `DISCUSS` 的 assigned tickets。
- 前幾天 standup BOS 中持續存在的 blocker。
- 使用者在對話中的口述 blockers。

判準收窄的是**什麼進得去**，不擴張**從哪裡找**——這三個來源不因為判準而增加。每一個來源
撈出來的東西仍然要逐一過上面那張表。
