---
title: "Standup Format Flow"
description: "standup 的四區塊格式、local markdown、language gate、送到宣告的目的地。"
---

# Standup Format Contract

這份 reference 負責格式、確認、本地檔案，以及送到宣告的目的地。

## Required Sections

Standup entry 一天一筆，每筆四塊：**YDY**、**TDT**、**BOS**、**口頭同步**，順序固定。
分組（Epic、主題、沒有單號的工作、會議）掛在區塊底下。

形狀與每一塊收什麼寫在 `standup-template.md`，這裡不抄第二份。格式一律遵守那份模板。

## Grouping Rules

同一個區塊底下依分組排，Epic → Task → Sub-task 依序縮排。

Sub-task 全部通過時折成一行，例如 N/N 驗證子單通過；有失敗才展開。

沒有單號的項目用一行摘要帶過，掛在自己的分組底下。

## Confirmation

呈現 draft 後等待使用者確認。使用者可新增、刪除、改寫任何一格。只有使用者說 OK、確認等
明確同意後，才寫本地檔案。

確認之後才寫本地檔，寫完才談送出——送到哪由宣告決定，見〈送到哪裡去〉。

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

**列出來就結束，不代人寫回去。** 落差清單交給使用者逐條裁，改不改那張單、什麼時候改，
是他的事。

這一條不是禮貌，是因為列出來的東西有一部分是推論，而推論會錯：2026-08-12 那一輪的落差
清單裡，「這條 AC 還沒交付」與「這件事在等 QA」兩條都是我自己從過期的資料推出來的，兩條
都是錯的。自動寫回去會把它們變成別人讀到的事實。

## Local Markdown

確認後先寫 local markdown：

`{base_dir}/standups/{YYYY}/{MM}/{YYYYMMDD}.md`

內容包含 `## YYYYMMDD` heading 到 entry 結尾分隔線。目錄不存在就建立；同日重跑可覆寫。

**這一份不是備份，是本體。** 它同時是下一份 standup 的 plan vs actual 比對來源
（見 `standup-planning-flow.md`），所以它每天都要寫。

## Language Gate

對 local markdown 執行 `scripts/validate-language-policy.sh` 指定的 blocking artifact gate。
Gate fail 時修正自然語言並重跑；沒過 gate 的那一份不算產出完成，也不要列給人看。

## 送到哪裡去

本地檔寫完、language gate 過了之後，讀目的地宣告。四種結果的行為寫在 `SKILL.md` 的
〈送到哪裡去〉那張表，這裡不抄第二份。

**送出前把那份逐字全文列出來，等一句同意。** 授權工具不等於授權內容——人說「你可以開
瀏覽器」授的是瀏覽器，那份要貼出去的東西他還沒看過。送出去之後才發現要改，改動的全文
再列一次、再等一次同意，不要直接重送。

## Link Rules

Ticket link 使用 markdown `[KEY title](URL)`。不要使用平台專屬的 smartlink custom tags；
markdown update 會把既有 smart link 轉成普通連結，這是 API behavior，應保持一致。
