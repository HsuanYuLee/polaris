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

## Local Markdown

確認後先寫 local markdown：

`{base_dir}/standups/{YYYY}/{MM}/{YYYYMMDD}.md`

內容包含 `## YYYYMMDD` heading 到 entry 結尾分隔線。目錄不存在就建立；同日重跑可覆寫。

## Language Gate

Confluence 是 external write。推送前對 local markdown 執行
`workspace-language-policy.md` 指定的 blocking artifact gate。Gate fail 時修正自然語言並重跑；
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
