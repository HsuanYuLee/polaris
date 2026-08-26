---
name: standup
description: |
  "Use when the user wants to generate a daily standup report or end-of-day summary (YDY / TDT / BOS / 口頭同步). Single entry point for all standup and end-of-day workflows. Trigger: 'standup', '站會', 'daily', '寫 standup', '下班', '收工', 'EOD', 'wrap up', '今天做了什麼'."

  要產出每日站會報告或下班摘要。例如「站會」「daily」「下班」「收工」
  「EOD」「今天做了什麼」。

  不用於：一張單走到哪（走 driving-work-to-done）、工時補登（走該公司自己的 worklog skill）。
metadata:
  author: Polaris
  version: 4.0.0
scope: universal
tools:
  - name: jq
    provision: framework
    why: 解析 API 回應的 JSON
    install: mise:aqua:jqlang/jq
---

# Standup — 每日站立會議報告產生器

把一個人手上的一切收起來，統整成他自己讀得懂的四塊：**YDY（昨天做了什麼）、TDT（今天要
做什麼）、BOS（被什麼卡住）、口頭同步**。來源是 git、JIRA、行事曆、PR 狀態、他自己講的話。

**它收一切。** 工作、日常、會議、沒有單號的東西都收，不分是哪一家公司的、也不分是不是
這套工具自己的進度。要不要給別人看某一段，是拿它去報告的那個人的事，不是收集這一步的事。

**送到哪由宣告決定。** 有宣告就送到那裡，送出前把逐字全文交給人、等一句同意；沒有宣告就
把內容講出來，結束。細節在〈送到哪裡去〉。

## Contract

`standup` 是 daily standup 與 EOD summary 的單一入口。它不自己做排序判斷，也不捏造資料
來源沒有的活動。它可以轉述 PR / JIRA / planning / blocker 現況，但不得自行把這些訊號升格成
workflow authority。這條有兩個方向，兩個都要擋：

- **不得升格成完成宣告**——「PR 狀態良好」不等於 `mergeable_ready`，release page / standup
  內容也不等於 release eligibility 或 release completed。
- **不得升格成待辦**——狀態名、單上的現況表、一個答不了問題的查詢回空，都不構成「還有什麼
  要做」。判準與三個實例在 `standup-data-collection-flow.md` 的〈狀態不是意圖〉，這裡不抄
  第二份。

這條原本只寫了第一個方向，而 2026-08-12 的四次校正有兩次是第二個方向。

**收集不過濾。** 這裡曾經有一段寫著「它不報產生它的那套工具自己的進度」，理由是
2026-08-14 那份對同事講了一整排跟他們無關的號碼與版本。**那一段修錯了地方**：問題不在
收集，在於全部倒給了同事。收集一切是給這個人自己整理用的；要給誰看哪一段，由拿它去填
某個平台、某個頁面的那一步過濾。

## 送到哪裡去

**這支不認得任何一個特定的地方，它讀一個宣告。** 那個宣告住在使用它的人自己的設定裡
（公司的 `workspace-config.yaml` 或個人設定），不寫死在這份散文裡。四種結果，行為互不
相同，而且每一種都要說出來：

| 讀到什麼 | 怎麼做 |
|---|---|
| 宣告齊全 | 送到那裡。**送出前把逐字全文交給人、等一句同意**；送出去之後要改，改動的全文再交一次 |
| 宣告在，但缺欄位 | 說出缺哪一欄，不送。內容照常產出 |
| 沒有宣告 | 把內容講出來，結束。**不猜、不沿用上一個目的地** |
| 量不到（設定檔讀不到、工具不在） | 說出量不到，不當成「沒有宣告」 |

**第二種與第三種不得收斂成同一句「找不到」**——半條宣告比沒有宣告糟，它看起來像有人
設定過。

**目的地要什麼形狀，由那一步自己去轉，不回頭改這一支的形狀。** 一個平台的表單欄位長什麼
樣是那個平台的事；把它抄進這裡，這支就只會產出那個平台的樣子。這件事發生過：2026-06 的
產出是四區塊，2026-08-13 為了對齊某個平台的表單改成一張 epic 三格，於是「每一塊收什麼」
反而沒有人寫——填的人只能照 PR 的機械狀態填。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `standup-data-collection-flow.md`, `workspace-config.yaml` |
| TDT / planning | `standup-planning-flow.md`, `standup-template.md`, `session-timeline.md` when useful |
| Formatting | `standup-format-flow.md`, `standup-template.md`, `scripts/validate-language-policy.sh` |

**`standup-template.md` 在兩列都出現，是因為它管兩件事**：形狀是排版時要的，而〈怎麼寫：
產出物精簡，證據不精簡〉那五條管的是**內容**——每一塊的長度與語氣在第 3–6 步就決定了，
等到排版才載它，那五條從來沒有在該生效的時候在手上。

## Flow

1. 讀 workspace config，取得 JIRA、GitHub、projects、teams。
2. 計算 `YDY_DATE`、`PRESENT_DATE`、`TDT_PLAN_DATE`；使用者指定日期時以使用者為準。
3. 收集昨日 sources：git commits、JIRA updates（含窗內留言）、分支上的事（被 merge 的 PR、
   收到的 review comment、CI 狀態）、Calendar meetings。視窗綁在查詢那一層，不是事後過濾。
4. Merge and deduplicate 昨日，並做 plan vs actual comparison——比對來源是
   `{base_dir}/standups/` 底下今天以前最新的那一份，而且**每次都說出拿哪一份比的**。
   **比的是內容不是號碼**，而且空的TDT不算一個計畫——規則在 `standup-planning-flow.md`。
   同一張單描述與留言衝突時留言勝出，且把落差說出來。
5. 收集今日 candidates：JIRA open sprint、open PR status、review-requested PR。
6. 收集卡關：JIRA discuss status、前幾天持續 blocker、使用者口述。每一項過
   `standup-planning-flow.md` 的准入判準——「我現在還有沒有下一步動作可做」加上那張措辭表；
   自己動得了的是待辦不是卡關。**「等 review」預設不是卡關**，判準與三種被退回的形狀寫在
   同一份的〈「等 review」預設不是卡關〉那一節。**延續過來的那一類還要先問一次它今天的來源**，
   寫在〈第二個來源要帶今天的根據〉那一節。
   兩次 standup 之間才發現的卡關寫回本地那份檔案，見〈兩次 standup 之間發現的卡關，落在哪〉。
7. 依 `standup-template.md` 組裝成四塊（YDY／TDT／BOS／口頭同步），分組掛在區塊底下，
   呈現給使用者確認，附上〈發現 N 處與現況不符〉。
   **epic 的 assignee 不是自己時，寫的是自己名下那幾張子單**，不寫成整張 epic 由自己
   推進——判定與標本在 `standup-data-collection-flow.md` 的〈這張 epic 是我的，還是我只有
   底下的單〉。
8. 使用者確認後，寫 local markdown。**那一份不是備份，是本體**，也是明天的比對來源。
9. 對 local markdown 跑 language gate。
10. 讀目的地宣告，照〈送到哪裡去〉那張表走。送出前把那份**逐字全文**列出來等一句同意；
    沒有宣告就列出來，結束。

## Data Rules

- Git commits 排除 merge commits。
- Calendar 不猜 Google Meet link；MCP 沒回傳就不列。
- Ticket 連結使用 `[KEY title](URL)` markdown，不使用平台專屬的 smartlink custom tags。
- Friday standup title 使用 Friday `PRESENT_DATE`；TDT的 work target 才是 next Monday。
- Meeting items 不參與 plan vs actual planned/additional/loss 判斷。

## Write Rules

- Local markdown 確認後無條件寫入——明天的 plan vs actual 讀它。
- **本地那一份以外，只寫目的地宣告指名的那一個地方。** 不代人改任何一張單或 PR。
- 本地檔要通過 `scripts/validate-language-policy.sh` 才算產出完成。
- standup 內對 PR / release / planning 的描述只能轉述來源系統或 shared state；不得在 standup prose
  中自行宣告「已完成 / 可 release / 可 merge」。

## Completion

輸出 standup date、四塊各有幾項、local file path、那份檔案的逐字全文、目的地讀到的是四種
結果的哪一種、任何 skipped sources 與原因。
