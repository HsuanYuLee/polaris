---
name: review-inbox
description: "Use when the user wants to discover and review PRs across the team awaiting their attention. NOT for a single specific PR (use review-pr). Supports three discovery modes: Label (GitHub label scan), Slack (channel-wide scan), Thread (specific Slack thread URL). Trigger: '掃 PR', 'review 大家的 PR', '批次 review', '有哪些 PR 要我看', Slack thread URL + review intent ('review <slack_url>', '幫我看這串'). Key: '我的 PR' → check-pr-approvals; '大家的 PR' / Slack URL → here; single PR URL → review-pr."
metadata:
  author: Polaris
  version: 2.2.0
---

# Review Inbox — 批次 Review 待審 PR

找出 team 內需要自己 first review、re-approve、或 re-review 的 PR，批次執行 review，
並依來源回 Slack 通知。

## Contract

此 skill 只處理多 PR discovery + batch review orchestration。單一 PR URL 轉 `review-pr`；
「我的 PR」approval 狀態轉 `check-pr-approvals`。

支援三個來源：

| Source | Use when |
|---|---|
| Slack | 預設；掃 PR channel 最近訊息中的 PR URLs |
| Thread | 使用者提供 Slack thread URL 並要求 review |
| Label | 使用者明確提到 need review label |

不得 review 自己的 PR。不得對 `waiting_for_author` PR 重複 review。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `review-inbox-discovery-flow.md`, `shared-defaults.md`, `stale-approval-detection.md`, `workspace-config-reader.md` |
| Batch review execution | `review-inbox-batch-review-flow.md`, `review-inbox/dispatch-context-bundle.md` |
| Slack notification | `review-inbox-slack-reporting.md`, `slack-message-format.md`, `github-slack-user-mapping.md`, `workspace-language-policy.md` |

Slack channel scan 可以派 read-only sub-agent。Per-PR review 不得使用 Claude Code
general-purpose sub-agent；只有 runtime 提供 constrained code-reviewer adapter 時才可平行
dispatch。否則依 `build-review-runtime-plan.py` 產生的 `main_session_sequential` plan，一次執行
一個 review packet，完成後只把 Completion Envelope summary 留在主 context。Batch review
dispatch 由 main session 讀取 `dispatch-context-bundle.md` 一次，再把濃縮後的 review flow inline
注入每個 review packet；不得要求執行者重讀完整 review skill / reference stack。

## Flow

1. 讀 workspace config 與 defaults，取得 GitHub org、PR channel、approval threshold、
   batch size、concurrency、confirm setting。
2. 解析 mode：Thread 優先，其次 explicit Label，其餘走 Slack。
3. 取得 current GitHub username，作為 exclude author 與 review-status 判定依據。
4. 依 discovery reference 產生 candidates JSON；scan snapshot 超過 60 秒不可沿用。
   Slack channel scan 使用 MCP 時指定 concise output；fallback CLI 的 `--oldest` 可接受
   Slack timestamp 或 ISO date/datetime。
5. 將 candidates JSON 經 `annotate-review-candidates.py` enrich，補上 sister PR cluster
   metadata 與 `model_tier` semantic class。Slack mapping 若含 `root_ticket_key`，cluster
   必須優先使用 root ticket；若沒有 umbrella ticket 但同一 Slack root message 有可辨識
   topic，使用 `root_topic_key`；最後才 fallback 到每張 PR 自己的 ticket。
6. 若 candidates 為空，回報目前沒有需要 review 的 PR 並停止。
7. 顯示排序後清單；若 config 要求 confirm，等待使用者選擇。
8. 先用 `build-review-prompt.sh` 產生 review packets + manifest，再用
   `build-review-runtime-plan.py` 產生 runtime plan。Plan 必須禁止 general-purpose sub-agent；
   若無 constrained code-reviewer adapter，主 session 依 sequential plan 執行。
9. 依 batch size / runtime plan 執行 per-PR review packets；prompt 必須使用
   deterministic handbook resolver 列出已存在的 project handbook paths，空清單時明確標示
   no project handbook。Prompt 必須要求執行者先讀 changed-file names，再依 diff size
   sampling；existing inline comments 只能以 metadata-only dedup，不把完整 comment body 放進
   context。Cluster lead 先跑完整 review；cluster sibling 使用 sibling-diff mode 與
   `small_fast` model class hint，不確定時標記 `needs_standard_review`。
10. 收斂結果，依來源模式發 Slack summary 或 thread replies。
11. 在對話中回報每個 PR 的 review result 與 approve status。

## Write And Notification Rules

- Review body 與 inline comments 由 `review-pr` 流程負責。
- Slack message 送出前必須通過 `workspace-language-policy.md` language gate。
- Slack mode 不發 channel-wide summary；只回覆原始 PR threads。
- Label mode 發一則 channel summary。
- Thread mode 回覆指定 thread。
- Thread replies 不設 `reply_broadcast: true`。

## Completion

輸出 reviewed count、APPROVE / REQUEST_CHANGES / COMMENT counts、Slack notification count、
以及任何 blocked PR 的原因。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
