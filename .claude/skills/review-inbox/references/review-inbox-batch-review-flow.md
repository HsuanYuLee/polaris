---
title: "Review Inbox Batch Review Flow"
description: "review-inbox 的 candidates list、batch size、runtime plan、per-PR review packet execution 與 result fan-in。"
---

# Batch Review Contract

這份 reference 負責 candidates list 呈現、runtime plan、分批 review、結果收斂。

本 flow 受 `context-budget-contract.md` 的 review-inbox concrete instance 約束。Main session
只保留決策、路由、fan-in 與 Completion Envelope summary；raw diff、raw comments、PASS CI
rollup 與 raw Slack channel messages 預設不得進 main context。

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

`batch_size` 控制本次最多 review 幾個 PR；`0` 代表不限。`concurrency` 只在 runtime
提供 constrained code-reviewer adapter 時控制平行數量。

Claude Code general-purpose Agent 不可作為 review-inbox per-PR reviewer，因為 DP-094 AC1
runtime measurement 顯示固定 Agent envelope 會壓過 prompt-side token saving。若 runtime
沒有 constrained code-reviewer adapter，主流程必須使用 `main_session_sequential` plan：一次只
執行一個 review packet，把 detail 寫到 artifact，fan-in 後再讀摘要。

## Per-PR Review Dispatch

每個 PR 使用獨立 review packet。Dispatch 前 candidates 必須已由
`annotate-review-candidates.py` 補上 `model_tier` 與 cluster metadata，並由
`build-review-runtime-plan.py` 產出 runtime plan。Prompt 必須包含：

- PR URL。
- `review_status`。
- Current GitHub username。
- Workspace config base directory。
- `review-inbox/dispatch-context-bundle.md` 的 inline 內容。
- deterministic handbook resolver 輸出的 verified project handbook paths；空清單時明確寫
  no project handbook，且不可掃 repo guideline folders。
- `model_tier` semantic class hint。
- `cluster_role`, `cluster_key`, `root_ticket_key`, `root_topic_key`, `cluster_lead_url`，
  以及 sibling PR 可用的 lead summary。
- Runtime adapter policy：不得使用 general-purpose sub-agent；只能使用 constrained
  code-reviewer adapter，或由 main session 依 runtime plan sequential 執行。
- Completion Envelope requirement。

Review mode：

| Status | Review behavior |
|---|---|
| `needs_first_review` | normal review |
| `needs_re_approve` | review commits since last valid approve；無實質變更時可直接 re-approve |
| `needs_re_review` | check previous comments and author fixes |

Review packet 不呼叫 Skill tool；執行者直接依 inline dispatch context、verified handbook
paths、PR diff、existing comments 執行 review，然後 submit GitHub review。Batch prompt 不得
要求執行者重讀完整 review skill / reference stack。

Runtime plan contract：

- `build-review-prompt.sh` 產出 prompts 與 manifest。
- `build-review-runtime-plan.py` 讀 annotated candidates + manifest，輸出
  `review-inbox-runtime-plan.v1`。
- Plan 的 `adapter_policy.general_purpose_subagent_allowed` 必須是 `false`。
- Plan step 的 `execution_mode` 預設為 `main_session_sequential`；只有 runtime 提供精簡
  code-reviewer adapter 時才可改為 `constrained_code_reviewer`。
- `--auto-adapter` 只能在 T7 dual-run quality evidence PASS 後選擇
  `constrained_code_reviewer`。Evidence 未通過、缺失，或 candidate count / cluster size /
  raw diff lines 未達 threshold 時，必須 fallback `main_session_sequential` 並寫入
  `adapter_policy.fallback_reason`。
- Main session sequential fallback 執行時，完成一個 PR 後只保留 Completion Envelope summary
  在主 context，完整 findings 留在 Detail artifact。

`constrained_code_reviewer` prompt envelope 必須包含：

- `review-inbox/dispatch-context-bundle.md` inline bundle。
- Verified project handbook paths。
- Main-session 100 raw diff line hard cap 的提醒。
- Completion Envelope schema。
- 禁止重讀完整 review-inbox / review-pr skill stack。
- 禁止 general-purpose sub-agent fallback；若 runtime adapter 不存在，回傳 fallback reason，
  不自行改走一般 Agent。

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
- 主 session raw diff output 以單 PR 累積 100 行為 hard cap。超過後該 PR 立即進入
  hunk-only / sample-only，直到該 PR review 完成前不得 reset；這不是單次工具呼叫額度，
  也不是整批共享額度。
- 完整 diff 必須先存到 `/tmp/review-inbox-runs/{run_id}/pr-{number}.diff`。後續 line range
  inspection 用 `inspect-pr-section.sh` 輸出 bounded section，不用 Read 工具回讀完整 diff。
- Debug 也受同一條 raw evidence policy 約束。不得在 main session 執行
  `gh pr diff ... 2>&1` 或任何會把 full diff 直接印回 stdout/stderr 的命令；錯誤診斷必須把
  full output redirect 到 artifact，再只輸出 bounded summary。
- Sub-agent 或 constrained reviewer envelope 內仍可使用 DP-094 sampling：整體 diff 不超過
  2000 行時可讀完整 diff；超過時每個檔案只讀 hunk headers、changed lines 與前後約
  20 行 context。
- 單檔 diff 小於 200 行只適用於 sub-agent / constrained reviewer envelope。主 session 仍受
  100 行 per-PR raw output cap 約束。import/export、routing、API contract、schema、
  test expectation、security/auth、payment/booking 等 cross-file 風險才升級讀相關檔案全文。
- Existing inline comments 只抓 metadata 用於 dedup：`user`, `path`, `line`, `side`,
  `head = body[:80]`。不得把完整 comment body 放進 sub-agent context。

CI rollup rules：

- 預設只輸出 `FAILURE` / `ERROR` checks。
- PASS checks 不進 main context。
- 只有使用者明確需要診斷完整 CI 狀態時，才使用 `--show-all-checks` override。

Telemetry rules：

- Completion 後執行 `measure-review-inbox-session.sh`。
- Required metadata path：`metadata.review_inbox_run`。
- Required query：`polaris-learnings.sh query --type telemetry --tag review-inbox`。
- Required keys：`run_id`, `candidate_count`, `reviewed_count`,
  `main_session_input_tokens`, `main_session_output_tokens`, `sub_agent_tokens`,
  `runtime_plan_kind`, `duration_seconds`, `estimator_kind`。

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
