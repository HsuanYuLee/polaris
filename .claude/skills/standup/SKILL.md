---
name: standup
description: |
  "Use when the user wants to generate a daily standup report or end-of-day summary (per-epic 昨日/今日/卡關). Single entry point for all standup and end-of-day workflows. Trigger: 'standup', '站會', 'daily', '寫 standup', '下班', '收工', 'EOD', 'wrap up', '今天做了什麼'."

  要產出每日站會報告或下班摘要。例如「站會」「daily」「下班」「收工」
  「EOD」「今天做了什麼」。

  不用於：一張單走到哪（走 driving-work-to-done）、工時補登（走該公司自己的 worklog skill）。
metadata:
  author: Polaris
  version: 4.0.0
scope: standalone
tools:
  - name: jq
    provision: framework
    why: 解析 API 回應的 JSON
    install: mise:aqua:jqlang/jq
---

# Standup — 每日站立會議報告產生器

從 git、JIRA、Calendar、PR status 與使用者補充資料，產出**以 epic 為主體、每張 epic 三格
（昨日／今日／卡關）**的報告。使用者確認後寫 local markdown，然後把內容列出來。

**它只收集與列出，不送出。** 這支寫得到的只有那一份本地檔案，其餘什麼都不碰——不貼看板、
不打 API、不改任何一張單。要把列出來的東西送到哪裡去，是使用它的人自己的事。

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

**它不報產生它的那套工具自己的進度。** 來源就是它被設定去看的那幾樣——公司的單、PR、
行事曆、使用者口述。以前這裡有一步會去翻開發這套流程用的那些紀錄，把它們併進今日格並提醒
有東西還沒提交；2026-08-14 那份因此在對同事講一整排跟他們無關的號碼與版本，是人工事後
刪掉的。**讀者是誰決定了報告寫什麼**——而那一步指名的目錄與腳本，在這支 skill 被單獨帶走
的環境裡一個都不存在。

**這支不知道目的地，也不該知道。** 沒有宣告、沒有解析、沒有預設值——它組出三格、寫成
本地檔、把內容列給人看，到這裡就結束。沒有卡關的項目時保留那一格，不寫「無」。

這件事以前是反過來的：這支自己去問一個宣告、自己按下送出，於是「要送到哪裡」變成一支通用
skill 的問題，而那個答案只有某一家公司才有。**送出是一個人在一家公司的行為，收集與列出
不是**——把兩者放在同一支裡面，通用的那一半就被綁在特定環境上。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `standup-data-collection-flow.md`, `workspace-config.yaml` |
| 今日格 / planning | `standup-planning-flow.md`, `standup-template.md`, `session-timeline.md` when useful |
| Formatting | `standup-format-flow.md`, `standup-template.md`, `scripts/validate-language-policy.sh` |

**`standup-template.md` 在兩列都出現，是因為它管兩件事**：形狀是排版時要的，而〈怎麼寫：
產出物精簡，證據不精簡〉那五條管的是**內容**——三格的長度與語氣在第 3–6 步就決定了，等到
排版才載它，那五條從來沒有在該生效的時候在手上。

## Flow

1. 讀 workspace config，取得 JIRA、GitHub、projects、teams。
2. 計算 `YDY_DATE`、`PRESENT_DATE`、`TDT_PLAN_DATE`；使用者指定日期時以使用者為準。
3. 收集昨日 sources：git commits、JIRA updates（含窗內留言）、分支上的事（被 merge 的 PR、
   收到的 review comment、CI 狀態）、Calendar meetings。視窗綁在查詢那一層，不是事後過濾。
4. Merge and deduplicate 昨日，並做 plan vs actual comparison——比對來源是
   `{base_dir}/standups/` 底下今天以前最新的那一份，而且**每次都說出拿哪一份比的**。
   **比的是內容不是號碼**，而且空的今日格不算一個計畫——規則在 `standup-planning-flow.md`。
   同一張單描述與留言衝突時留言勝出，且把落差說出來。
5. 收集今日 candidates：JIRA open sprint、open PR status、review-requested PR。
6. 收集卡關：JIRA discuss status、前幾天持續 blocker、使用者口述。每一項過
   `standup-planning-flow.md` 的准入判準——「我現在還有沒有下一步動作可做」加上那張措辭表；
   自己動得了的是待辦不是卡關。**「等 review」預設不是卡關**，判準與三種被退回的形狀寫在
   同一份的〈「等 review」預設不是卡關〉那一節。**延續過來的那一類還要先問一次它今天的來源**，
   寫在〈第二個來源要帶今天的根據〉那一節。
   兩次 standup 之間才發現的卡關寫回本地那份檔案，見〈兩次 standup 之間發現的卡關，落在哪〉。
7. 依 `standup-template.md` 依 epic 組裝三格並呈現給使用者確認，附上〈發現 N 處與現況不符〉。
   **epic 的 assignee 不是自己時，三格寫的是自己名下那幾張子單**，不寫成整張 epic 由自己
   推進——判定與標本在 `standup-data-collection-flow.md` 的〈這張 epic 是我的，還是我只有
   底下的單〉。
8. 使用者確認後，寫 local markdown。**那一份不是備份，是本體**，也是明天的比對來源。
9. 對 local markdown 跑 language gate，通過後把那份**逐字全文**列出來。流程到此結束——
   要不要送、送到哪、由誰按下送出，不在這支裡面。

## Data Rules

- Git commits 排除 merge commits。
- Calendar 不猜 Google Meet link；MCP 沒回傳就不列。
- Ticket 連結使用 `[KEY title](URL)` markdown，不使用平台專屬的 smartlink custom tags。
- Friday standup title 使用 Friday `PRESENT_DATE`；今日格的 work target 才是 next Monday。
- Meeting items 不參與 plan vs actual planned/additional/loss 判斷。

## Write Rules

- Local markdown 確認後無條件寫入——明天的 plan vs actual 讀它。
- **本地那一份是這支唯一會寫的東西。** 沒有第二個寫入目標，也不代人改任何一張單或 PR。
- 本地檔要通過 `scripts/validate-language-policy.sh` 才算產出完成。
- standup 內對 PR / release / planning 的描述只能轉述來源系統或 shared state；不得在 standup prose
  中自行宣告「已完成 / 可 release / 可 merge」。

## Completion

輸出 standup date、每張 epic 的三格 counts、local file path、那份檔案的逐字全文、
任何 skipped sources 與原因。
