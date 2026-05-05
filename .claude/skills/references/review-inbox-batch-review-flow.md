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

每個 PR 使用獨立 sub-agent。Dispatch 前 candidates 必須已由
`annotate-review-candidates.py` 補上 `model_tier` 與 cluster metadata。Prompt 必須包含：

- PR URL。
- `review_status`。
- Current GitHub username。
- Workspace config base directory。
- `review-inbox/dispatch-context-bundle.md` 的 inline 內容。
- deterministic handbook resolver 輸出的 verified project handbook paths；空清單時明確寫
  no project handbook，且不可掃 repo guideline folders。
- `model_tier` semantic class hint。
- `cluster_role`, `cluster_key`, `root_ticket_key`, `cluster_lead_url`，以及 sibling PR
  可用的 lead summary。
- Completion Envelope requirement。

Review mode：

| Status | Review behavior |
|---|---|
| `needs_first_review` | normal review |
| `needs_re_approve` | review commits since last valid approve；無實質變更時可直接 re-approve |
| `needs_re_review` | check previous comments and author fixes |

Sub-agent 不呼叫 Skill tool；它直接依 inline dispatch context、verified handbook paths、
PR diff、existing comments 執行 review，然後 submit GitHub review。Batch prompt 不得要求
sub-agent 重讀完整 review skill / reference stack。

Cluster scheduling：

- `cluster_lead` 必須先於同 cluster siblings 完成，並在 Detail artifact 提供一句
  lead review summary。
- `cluster_sibling` 使用 sibling-diff mode：比較 sibling diff 與 lead PR diff，只 review
  行為差異、平台差異，以及 lead findings 是否適用。
- 若 `cluster_sibling` 發現行為不一致、風險升級、lead summary 缺失，或無法 confidence 判斷，
  result 用 `COMMENT` 並在 summary 標記 `needs_standard_review`，主流程再用
  `standard_coding` 重跑該 PR。

Token budget rules：

- 先執行 `gh pr diff <PR_URL> --name-only` 取得完整 changed-file list。
- 整體 diff 不超過 2000 行時可讀完整 diff；超過時每個檔案只讀 hunk headers、changed lines
  與前後約 20 行 context。
- 單檔 diff 小於 200 行可讀完整 per-file diff；大檔只 sample changed hunks。import/export、
  routing、API contract、schema、test expectation、security/auth、payment/booking 等 cross-file
  風險才升級讀相關檔案全文。
- Existing inline comments 只抓 metadata 用於 dedup：`user`, `path`, `line`, `side`,
  `head = body[:80]`。不得把完整 comment body 放進 sub-agent context。

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
