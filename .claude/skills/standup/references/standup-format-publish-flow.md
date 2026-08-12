---
title: "Standup Format Publish Flow"
description: "standup 的 YDY/TDT/BOS/口頭同步格式、local markdown backup、language gate 與 Confluence append 流程。"
---

# Standup Publish Contract

這份 reference 負責格式、確認、本地備份與 Confluence 發布。

## Required Sections

Standup entry 必須有四個區塊：

1. `YDY – Yesterday I Did`
2. `TDT – Today's Tasks`
3. `BOS – Blockers or Struggles`
4. `口頭同步`

`口頭同步` 放在 BOS 後、分隔線前。使用 3-4 條 italic bullets，口語化摘要：

- YDY 精華 1-2 條。
- 插曲或損失 0-1 條。
- TDT 計畫 1 條。

不要逐條複述 YDY / TDT。

## Grouping Rules

YDY 與 TDT 都依 team 分組。Ticket 有 parent Epic 時，Epic 在 team 分組內成為最上層。

Sub-task 全部通過時折成一行，例如 N/N 驗證子單通過；有失敗才展開。

NO-JIRA 項目用一行摘要帶過。

格式需遵守 `standup-template.md`，並維持既有 Confluence page 的風格。

## Confirmation

呈現 draft 後等待使用者確認。使用者可新增、刪除、改寫 YDY / TDT / BOS / 口頭同步。只有使用者
說 OK、推上去、確認等明確同意後，才進入 publish。

## 落差：看得見，但不會被自己寫掉

<!-- STANDUP-CONTRACT: drift-surfaced -->

收集的時候會發現某張單或某個 PR 上寫的東西與量到的現況不符。**這是唯一一個會把兩者擺在
一起看的時刻，不列下來它就消失。** 所以草稿裡多一段〈發現 N 處與現況不符〉，逐條給四樣：

1. 哪一個（單號／PR 編號）
2. 哪一段（章節名或行號）
3. 量到的是什麼
4. 建議改成什麼

**證據與推論分開標。** 每一條說得出它的根據是量到的還是推出來的：

- `量到` —— 有留言時間、有 API 回應、有命令輸出。
- `待驗` —— 我自己剛推導出來的。**不得與量到的並列成同一種東西。**

三種情況要長得不一樣，不能有兩種長得一樣：有落差且證據充足、有落差但根據只是推論、
沒有落差。**兩邊一致的時候不要為了有東西可報而列出落差。**

<!-- STANDUP-CONTRACT: drift-needs-consent -->

**人點頭才寫。** 這一段跟 Confluence 走同一條紀律，順序不得顛倒：

1. 落差列出來，等使用者逐條裁。
2. 同意的那幾條，內容先落地成檔案。
3. 過 `scripts/validate-language-policy.sh`。
4. 才送出。

**沒有人點頭的情況下，沒有任何一條路徑會把東西寫到別人看得到的地方。** 這一條不是禮貌，
是因為列出來的東西有一部分是推論，而推論會錯：2026-08-12 那一輪的落差清單裡，「這條 AC
還沒交付」與「這件事在等 QA」兩條都是我自己從 stale 的資料推出來的，兩條都是錯的。自動寫
會把它們變成別人讀到的事實。

同意是**逐次、逐條**的：一次同意不延伸到下一條，也不延伸到下一天。同意寫某一段就只寫那
一段，不順手整理旁邊的東西。

**不新開對外寫入通道。** 用既有那一條（落地成檔案 → 過 gate → 送），不為這件事新增平行的
介面或紀錄。

## Local Markdown

確認後先寫 local markdown：

`{base_dir}/standups/{YYYY}/{MM}/{YYYYMMDD}.md`

內容包含 `## YYYYMMDD` heading 到 entry 結尾分隔線。目錄不存在就建立；同日重跑可覆寫。

## Language Gate

Confluence 是 external write。推送前對 local markdown 執行
`scripts/validate-language-policy.sh` 指定的 blocking artifact gate。Gate fail 時修正自然語言並重跑；
不可把未通過 gate 的 standup 寫到 Confluence。

## Confluence Append

依 `confluence-page-update.md`：

1. 搜尋當月 `YYYYMM Standup Meeting` page。
2. 找不到時告知使用者需先建立，不自行猜位置。
3. 取得 existing content 與 version number。
4. 更新前偵測 version conflict；若 version changed，重新讀最新內容。
5. Append new standup entry 到頁面尾端。
6. 使用 version message 說明新增日期。

更新後回報 Confluence page link 與 local file path。

## Link Rules

Ticket link 使用 markdown `[KEY title](URL)`。不要使用 Confluence smartlink custom tags；
markdown update 會把既有 smart link 轉成普通連結，這是 API behavior，應保持一致。
