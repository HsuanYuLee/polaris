---
title: "Review Inbox Batch Review Flow"
description: "review-inbox 的 candidates list、batch size、concurrency、per-PR review sub-agent dispatch 與 result fan-in。"
---

# Batch Review Contract

這份 reference 負責 candidates list 呈現、分批 review、結果收斂。

## Candidate List

Candidates 依 PR created time 升序排序，最早發出的 PR 優先。顯示欄位：

| Field | Purpose |
|---|---|
| number | user selection |
| repo | review scope |
| PR number and title | identification |
| author | notification routing |
| review status | first review / re-approve / re-review |

表格下方附統計：first review、re-approve、re-review counts。

若 `skill_defaults.review-inbox.confirm` 為 false，列完清單後自動選取 candidates，受 batch
size 限制。若為 true，等待使用者輸入編號、`all`、或 `none`。

## Batch Size And Concurrency

`batch_size` 控制本次最多 review 幾個 PR；`0` 代表不限。`concurrency` 控制同時平行的
review sub-agents 數量。

當 selected PRs 超過 concurrency，分波執行：每波完成 fan-in 後再啟動下一波。

## Per-PR Review Dispatch

每個 PR 使用獨立 sub-agent。Prompt 必須包含：

- PR URL。
- `review_status`。
- Current GitHub username。
- Workspace config base directory。
- 指示讀取 `review-pr/SKILL.md` 並 inline 執行其流程。
- Completion Envelope requirement。

Review mode：

| Status | Review behavior |
|---|---|
| `needs_first_review` | normal review |
| `needs_re_approve` | review commits since last valid approve；無實質變更時可直接 re-approve |
| `needs_re_review` | check previous comments and author fixes |

Sub-agent 不呼叫 Skill tool；它直接讀 `review-pr/SKILL.md`、rules、handbook、PR diff、
existing comments，然後 submit GitHub review。

## Result Envelope

每個 sub-agent 回傳：

| Field | Meaning |
|---|---|
| `pr_url`, `number`, `title`, `repo`, `author` | PR identity |
| `result` | `APPROVE`, `REQUEST_CHANGES`, or `COMMENT` |
| `must_fix`, `should_fix`, `nit` | finding counts |
| `approve_status` | threshold summary |
| `summary` | one-line result |
| `Detail` | temp artifact path with full comments |

Fan-in 後統計 result counts，並保留每個 PR 的 most important must-fix summary for Slack。

## Re-approve Boundaries

Re-approve 不等於略過 review。必須確認 last approve 後的新 diff。只有 CI/bot-only 或
non-substantive changes 時，才可 concise approve。

若作者尚未回覆上一輪 REQUEST_CHANGES comments，即使有新 push，也應維持
`waiting_for_author` 並 skip。
