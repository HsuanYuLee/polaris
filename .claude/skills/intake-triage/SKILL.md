---
name: intake-triage
description: >
  批次收單排工：分析 PM 開出的一批 ticket，評估優先序，告訴 PM 哪些先做、哪些後做、哪些規格不足需補。
  產出 JIRA label + comment + Slack 摘要。
  觸發：「收單」、「排工」、「intake」、「這批單幫我看」、「PM 開了一堆單」、「幫我排優先」、
  「intake-triage」、「triage these tickets」、「prioritize this batch」。
  當使用者提供一批 ticket key 並要求排優先序時使用此 skill，不要與 /my-triage（個人每日盤點）混淆。
metadata:
  author: Polaris
  version: 2.1.0
---

# Intake Triage — PM 收單排工

批次分析 PM 開出的 tickets，產出「先做 / 後做 / 補規格 / 不建議做」的排序建議，
並可寫回 JIRA labels/comments 與 Slack 摘要。

## Contract

`intake-triage` 是 batch intake prioritization，不是個人每日工作盤點（`my-triage`），
也不是深入 refinement、sprint planning、或 engineering codebase probe。

它只依 ticket 內容與同批關係做快速排序；不做 codebase exploration、不自動改 status、
不把 intake comment 當 implementation spec。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `intake-triage-input-flow.md`, `workspace-config-reader.md`, `shared-defaults.md`, `jira-story-points.md` |
| Scoring | `intake-triage-scoring-flow.md`, `epic-template.md` |
| Writeback / Slack summary | `intake-triage-writeback-flow.md`, `workspace-language-policy.md`, `slack-message-format.md` |

Per-ticket analysis 或 JIRA writeback 派 sub-agent 時，必須注入 `sub-agent-roles.md` 的
Completion Envelope。

## Flow

1. Parse input：ticket keys、JQL、Slack URL，或 Epic key 展開子單。
2. Fetch tickets from JIRA，標準化 fields，並收斂同批 Epic + child tickets。
3. 偵測 batch theme 與 per-ticket lens。
4. 對每張 ticket 評估 readiness、effort signal、impact、dependencies、duplicate risk、hard blockers。
5. 依判決矩陣產生 verdict 與全域 rank。
6. 呈現判決表，等待 RD 確認或調整。
7. 使用者確認後，寫 JIRA `intake-*` labels 與 intake comment。
8. 產生 PM-friendly Slack summary；RD 確認後才送出。

## Write Rules

- JIRA comment 與 Slack summary 都是 external write，送出前必須通過 `workspace-language-policy.md`。
- JIRA labels 只更新 `intake-` prefix，不碰其他 labels。
- Skip ticket 的補規格問題寫在 comment 中，不額外 tag PM；Slack summary 統一通知。
- Slack 發送目的地由 RD 確認：channel、DM，或不發。

## Completion

輸出 batch count、verdict counts、top ranks、writeback status、Slack status、blocked/skipped
questions，以及後續路由：`my-triage`、`sprint-planning`、`refinement`、或 `engineering`。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
