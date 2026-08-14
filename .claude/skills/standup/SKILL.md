---
name: standup
description: |
  "Use when the user wants to generate a daily standup report or end-of-day summary (per-epic 昨日/今日/卡關). Single entry point for all standup and end-of-day workflows. Trigger: 'standup', '站會', 'daily', '寫 standup', '下班', '收工', 'EOD', 'wrap up', '今天做了什麼'."

  要產出每日站會報告或下班摘要。例如「站會」「daily」「下班」「收工」
  「EOD」「今天做了什麼」。

  不用於：一張單走到哪（走 driving-work-to-done）、工時補登（走該公司自己的 worklog skill）。
metadata:
  author: Polaris
  version: 3.0.0
scope: standalone
tools:
  - name: jq
    provision: framework
    why: 解析 API 回應的 JSON
    install: mise:aqua:jqlang/jq
---

# Standup — 每日站立會議報告產生器

從 git、JIRA、Calendar、PR status 與使用者補充資料，產出**以 epic 為主體、每張 epic 三格
（昨日／今日／卡關）**的報告。使用者確認後寫 local markdown，再依公司宣告的目的地送出。

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

**送出去之前必須等待使用者確認。** 沒有卡關的項目時保留那一格，不寫「無」。

**目的地不寫在這支 skill 裡。** 送到哪、什麼形狀、誰按下送出，問
`scripts/resolve-standup-destination.sh`；宣告缺席時說出來、報告照常產出並寫在本地，
不猜也不沿用。判準與四種離場碼在 `standup-format-publish-flow.md` 的〈送到哪〉。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `standup-data-collection-flow.md`, `workspace-config.yaml` |
| 今日格 / planning | `standup-planning-flow.md`, `session-timeline.md` when useful |
| Formatting / publish | `standup-format-publish-flow.md`, `standup-template.md`, `scripts/resolve-standup-destination.sh`, `scripts/validate-language-policy.sh` |

## Flow

1. 讀 workspace config，取得 JIRA、GitHub、projects、teams。
2. 計算 `YDY_DATE`、`PRESENT_DATE`、`TDT_PLAN_DATE`；使用者指定日期時以使用者為準。
3. 收集昨日 sources：git commits、JIRA updates（含窗內留言）、分支上的事（被 merge 的 PR、
   收到的 review comment、CI 狀態）、Calendar meetings。視窗綁在查詢那一層，不是事後過濾。
4. Merge and deduplicate 昨日，並做 plan vs actual comparison——比對來源是
   `{base_dir}/standups/` 底下今天以前最新的那一份，而且**每次都說出拿哪一份比的**。
   同一張單描述與留言衝突時留言勝出，且把落差說出來。
5. 收集今日 candidates：JIRA open sprint、open PR status、review-requested PR。
6. 收集卡關：JIRA discuss status、前幾天持續 blocker、使用者口述。每一項過
   `standup-planning-flow.md` 的准入判準——「我在等誰」加上那張措辭表；自己動得了的是待辦
   不是卡關。
7. 依 `standup-template.md` 依 epic 組裝三格並呈現給使用者確認，附上〈發現 N 處與現況不符〉。
8. 使用者確認後，寫 local markdown。**那一份不是備份，是本體**，也是明天的比對來源。
9. 對 local markdown 跑 language gate，通過後依宣告的目的地送出。
10. 落差清單裡使用者逐條同意的那幾條，才寫回單／PR——同一條紀律：落地成檔案 → 過 gate →
    才送。沒點頭的不寫。

## Data Rules

- Git commits 排除 merge commits。
- Calendar 不猜 Google Meet link；MCP 沒回傳就不列。
- Ticket 連結使用 `[KEY title](URL)` markdown，不使用平台專屬的 smartlink custom tags。
- Friday standup title 使用 Friday `PRESENT_DATE`；今日格的 work target 才是 next Monday。
- Meeting items 不參與 plan vs actual planned/additional/loss 判斷。

## Write Rules

- Local markdown 確認後無條件寫入，即使那天沒送出去——明天的 plan vs actual 讀它。
- 送出是 external write；送出前必須通過 `scripts/validate-language-policy.sh`。
- 目的地與送出方式依 `resolve-standup-destination.sh` 的宣告；`publish: manual` 表示
  最後一步由人自己貼上，那不是流程停住。
- 送出後回報目的地連結與 local file path；沒送出時說出為什麼。
- standup 內對 PR / release / planning 的描述只能轉述來源系統或 shared state；不得在 standup prose
  中自行宣告「已完成 / 可 release / 可 merge」。

## Completion

輸出 standup date、每張 epic 的三格 counts、local file、送出狀態（含目的地或缺宣告的理由）、
任何 skipped sources 與原因。
