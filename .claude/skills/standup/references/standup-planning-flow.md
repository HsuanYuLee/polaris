---
title: "Standup Planning Flow"
description: "standup 的昨日 merge/dedup、plan vs actual、今日 candidates、PR status 與卡關 collection。"
---

# Standup Planning Contract

這份 reference 負責把原始資料整理成每張 epic 的昨日／今日／卡關三格。

## 昨日 Merge And Dedup

同一 ticket 同時出現在 git 與 JIRA 時，合併成一行：JIRA status/title 為主，git commit
summary 為輔。

依 ticket 的 parent epic 分組。沒有 parent epic 的活動與會議放進 `其他（無 Epic）`。

Ticket 格式使用 `[KEY title](https://{jira.instance}/browse/KEY) — 動作摘要`。

## Plan Vs Actual

<!-- STANDUP-CONTRACT: plan-vs-actual-source -->

**比對來源是這支 skill 自己每天落下的那份本地檔案**，不是任何一個它已經不再寫入的地方。
取 `{base_dir}/standups/` 底下日期早於今天的最新一份，解析它的**今日**格。

以前這裡讀的是外部頁面上「今天以前最近一筆 entry」。目的地一搬，那個頁面就再也沒有新的
entry，於是這一步每天都走進 skip 條件——而 skip 條件在散文裡長得像偶發狀況。**生產者與
消費者現在是同一個檔案**，這一步才不會再靜靜地失效。

**拿哪一份比的要說出來**，每一次都說：

- 有可比的前一份 → 說出是哪一天的哪一個檔案，以及它距離今天幾天。隔了假日或請假是正常的，
  隔了兩個月則是一個要被看到的訊號。
- 沒有可比的前一份 → 說出為什麼（`standups/` 底下沒有更早的檔案／那一份沒有今日格），
  然後照常往下走。**不沉默跳過**：一個安靜跳過的比對，跟一個「比過了、沒有落差」的比對
  在報告上長得一模一樣。

比較規則：

- 今日 YDY ticket 命中前一份的今日格：標記 planned。
- 今日 YDY ticket 不在前一份的今日格：標記 additional。
- 前一份今日格的 ticket 未出現在今日 YDY：列為 loss，原因不明時詢問使用者。
- Meeting items 不參與 planned / additional / loss。

呈現時讓使用者確認標記是否合理。

## 今日 Candidates

優先從 JIRA open sprint 搜尋 current user 的 in-progress / code review / todo / planned
tickets。Status set 必須包含新 sprint 常見的待辦狀態，避免今日格空白。

JIRA query 為空時 fallback：

1. 從昨日的 JIRA results 中選仍在進行中的 tickets。
2. 仍為空時詢問使用者今天預計做什麼。

Sorting：

1. Priority 高的在前。
2. In development 優先於 not started。
3. 有 dependency 時標註 unblocks。

## PR Status Supplements

自己的 open PR：

- changes requested：今日格修 review comments。
- CI fail：今日格修 CI。
- no approvals：今日格追 review。
- enough approvals：今日格待 merge。
- draft：跳過，通常由 JIRA 開發項目覆蓋。

Review-requested PRs 有結果時，加入今日格的 PR Review 項目。

## 卡關

### 准入判準：我在等誰

<!-- STANDUP-CONTRACT: bos-admission -->

**卡關是「我在等某個人、或某個我動不了的東西」，不是「這件事還沒做完」。**

一件我自己動手就能推進的事**不是卡關**，不論它多久沒動、多讓人煩——它是待辦，屬今日格。
2026-08-12 把「兩張子單的 resolution 被 Automation for Jira 誤設成完成」寫進卡關，使用者
的回覆是：「卡關你要留需要其他人協助的事，你列的不是，只是待辦。」那件事我自己改得掉。

**這幾種措辭一律是卡關**，因為它們都要靠別人才動得了——需要開會，或需要通知當事人：

| 措辭 | 卡關？ |
|---|---|
| 等 X 確認 / 請 X 覆核 | **是** |
| 等 X 回（留言、訊息、郵件） | **是** |
| 等 X review / 等 reviewer 看我的 PR | **是** |
| 等 X 拍板兩個方案選哪個 | **是** —— 只有他知道 |
| 等一個我沒有權限的環境或憑證 | **是** |
| 要跟別的團隊聯絡才推得動 | **是** |
| CI 紅了要修 / lint 沒過 / 資料被誤設要清 | 否 —— 我自己動得了 |
| 一張單已經 merge，後面由別人接（QA 排程、排 release） | **否** —— 見下 |

這張清單是量出來的：2026-08-13 那份把「請 Bily 覆核兩格」與「等 Bily 回 comment」寫進了
今日格。判準當時只寫「我在等誰」，方向對，但沒有把常見措辭寫成照著判得出來的樣子。

**最後一列是判準會判錯的地方，所以指名。** 「等 QA 排程」字面上完全符合「需要別人動」，
但它不是卡關：那張單對我而言已經結束，我沒有任何東西卡在那裡等它回來，也不需要通知誰或
開會。判準的重點是**我在等**，不是**有人要動**。分辨法是問一句：那件事回來之後，我手上會
多出什麼工作？答案是「沒有」就不是卡關。

**空著是一個答案。** 沒有符合判準的東西時保留那一格且留白，不寫「無」，也不要因為那一格
空著就把待辦搬過去填。

### 卡關 sources

- JIRA status = `DISCUSS` 的 assigned tickets。
- 前幾天 standup 卡關格中持續存在的 blocker。
- 使用者在對話中的口述 blockers。

判準收窄或放寬的都是**什麼進得去**，不擴張**從哪裡找**——這三個來源不因為判準而增加。
每一個來源撈出來的東西仍然要逐一過上面那張表。

### 第二個來源要帶今天的根據

<!-- STANDUP-CONTRACT: carried-over-blocker-needs-today-evidence -->

**「昨天那一格裡有它」不是它今天還在的根據。** 前兩個來源不一樣：`DISCUSS` 與口述都是
今天問到的，而延續是昨天問到的——它唯一的依據就是它自己。所以一條要延續的卡關，今天要
先問一次它的來源，然後照答案分三種走：

| 今天問到什麼 | 怎麼寫 |
|---|---|
| 來源系統有新痕跡（新留言、狀態變了、對方回了） | 照常留在卡關格，**並說出那個痕跡是什麼** |
| 來源系統問得到，但跟昨天一樣沒有動靜 | 留在卡關格，**說出它從哪一天開始沒有動靜** |
| 來源系統今天問不到（工具不在、查詢逾時、逐字稿是雜訊） | 留著並**標成待驗**：「昨天寫的，今天沒有查證到」。不當成還在，也不當成收掉了 |
| 使用者說它已經收掉了 | 拿掉。口頭收掉的結論不會出現在任何一個系統裡 |

這是〈狀態不是意圖〉與〈問不到就說出來〉那兩節套在這一個來源上的樣子，判準本身寫在
`standup-data-collection-flow.md`，這裡不重講一次。

這一條是量出來的：2026-08-13 那份把「等某位同事回一則 comment 的三個選項」寫進卡關，當天
會議上已經有結論但沒有人寫回單上；三個來源當天一個都答不了（單上最新留言是我自己前一天
留的、那條 PR 兩天沒有新 comment、會議逐字稿是辨識失敗的雜訊）。於是隔天那份原樣照抄，
被使用者當場退回。**沒有這張表的時候，那幾種答案在報告上長得一模一樣。**
