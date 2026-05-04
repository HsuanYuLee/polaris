---
name: standup
description: "Use when the user wants to generate a daily standup report or end-of-day summary (YDY/TDT/BOS/口頭同步). Single entry point for all standup and end-of-day workflows. Trigger: 'standup', '站會', 'daily', '寫 standup', '下班', '收工', 'EOD', 'wrap up', '今天做了什麼'."
metadata:
  author: Polaris
  version: 2.1.0
---

# Standup — 每日站立會議報告產生器

從 git、JIRA、Calendar、PR status、triage state 與使用者補充資料產出 YDY / TDT / BOS /
口頭同步報告。使用者確認後，先存 local markdown，再 append 到 Confluence standup page。

## Contract

`standup` 是 daily standup 與 EOD summary 的單一入口。它可以自動觸發當日 triage guard，
但不取代 `my-triage` 的排序判斷，也不捏造資料來源沒有的活動。

Confluence 寫入前必須等待使用者確認。沒有 blockers 時保留 BOS heading，不寫「無」。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `standup-data-collection-flow.md`, `workspace-config-reader.md`, `shared-defaults.md` |
| TDT / planning | `standup-planning-flow.md`, `session-timeline.md` when useful |
| Formatting / publish | `standup-format-publish-flow.md`, `standup-template.md`, `confluence-page-update.md`, `workspace-language-policy.md` |
| Monthly framework hygiene | `framework-iteration-procedures.md`, `repo-handbook.md` if first monthly standup needs framework follow-up |

## Flow

1. 讀 workspace config，取得 JIRA、Confluence、GitHub、projects、teams。
2. Auto-triage guard：若今日 triage state 缺漏或過期，先執行 `my-triage`，讓使用者確認。
3. 計算 `YDY_DATE`、`PRESENT_DATE`、`TDT_PLAN_DATE`；使用者指定日期時以使用者為準。
4. 收集 YDY sources：git commits、JIRA updates、Calendar meetings。
5. Merge and deduplicate YDY，並做 plan vs actual comparison。
6. 收集 TDT candidates：JIRA open sprint、open PR status、review-requested PR、Polaris backlog。
7. 收集 BOS：JIRA discuss status、前幾天持續 blocker、使用者口述。
8. 依 `standup-template.md` 組裝四區塊並呈現給使用者確認。
9. 使用者確認後，寫 local markdown。
10. 對 local markdown 跑 language gate，通過後 append 到 Confluence page。

## Data Rules

- Git commits 排除 merge commits。
- Calendar 不猜 Google Meet link；MCP 沒回傳就不列。
- Ticket 連結使用 `[KEY title](URL)` markdown，不使用 Confluence smartlink custom tags。
- Friday standup title 使用 Friday `PRESENT_DATE`；TDT work target 才是 next Monday。
- Meeting items 不參與 plan vs actual planned/additional/loss 判斷。

## Write Rules

- Local markdown 是 Confluence push 前的備份，確認後無條件寫入。
- Confluence page update 依 `confluence-page-update.md` 做 search、version check、append。
- Confluence body 是 external write；送出前必須通過 `workspace-language-policy.md`。
- 更新完成後回報 Confluence page link 與 local file path。

## Completion

輸出 standup date、YDY/TDT/BOS counts、local file、Confluence status、任何 skipped sources
與原因。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
