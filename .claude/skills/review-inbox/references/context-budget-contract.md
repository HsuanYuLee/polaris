---
title: "Context Budget Contract"
description: "High-volume skill 的 main-session context budget、raw evidence routing 與 telemetry contract。"
---

# Contract
<!-- PROSE-EXTERNAL-PATHS: verify-report.md — 舊層的證據留在 specs 那個 repo，不搬進來 -->

Context Budget Contract 適用於會批次讀取大量 diff、logs、Slack messages、JIRA comments、
CI rollup、test output 或其他 raw evidence 的 high-volume skill。

核心原則：main session 是 orchestration surface，只負責決策、路由、fan-in 與可讀摘要；
raw evidence workspace 必須是 artifact、bounded script output、deterministic summary、
sample，或受限 reviewer envelope。

## Required Fields

每個 concrete contract instance 必須包含六個欄位：

| 欄位 | 要求 |
|---|---|
| `main_session_budget` | 定義 per item / per batch budget、計算單位、超限行為，以及何時 reset。 |
| `raw_evidence_policy` | 定義哪些 raw evidence 禁止直接進 main context，以及 artifact / summary / sample path。 |
| `reference_compilation` | 定義 bounded dispatch bundle、bundle size、forbidden reread checks。 |
| `dispatch_facts` | 定義派工前要交給執行者的事實有哪些，以及哪些判斷刻意不做。 |
| `telemetry` | 定義 completion 後要寫入的 estimator、count、artifact volume。 |
| `verify_report` | 定義 pilot / rollout 完成後如何證明 contract 有效。 |

## Ownership Boundary

DP-085 owns placement decisions：內容與 mechanism 住在哪裡。

DP-113 owns consumption budgets：runtime 實際消耗多少、超限如何降載、哪些 raw evidence
不得進 main context。

同一個 mechanism，例如 bundle、artifact、sub-agent envelope，可以同時服務 DP-085 和
DP-113；但 acceptance 必須由各自 owner 驗證，不得互相覆寫。

## Self-Consistency Check

Concrete instance PASS 條件：

1. 六個 required fields 都存在。
2. 每個欄位都有 skill-specific binding，不可只寫 TBD。
3. Pilot 才能知道的 threshold、artifact path、quality number 必須明確標示
   `pending_pilot_evidence`。
4. `main_session_budget` 必須說明計算單位，例如 per PR、per batch、per tool output。
5. `raw_evidence_policy` 必須列出 forbidden raw evidence 與替代 route。
6. `dispatch_facts` 只列事實，不得規定用哪一種 sub-agent——要求與禁止都算。一支
   `scope: universal` 的 skill 指名一個它不 ship 的東西，換一個環境就不成立。
7. `telemetry` 必須能被 deterministic query 找回。
8. `verify_report` 必須連到 telemetry、artifact、quality evidence。

## Review-Inbox Contract Instance

`review-inbox` 是第一個 concrete contract instance。

| 欄位 | Binding |
|---|---|
| `main_session_budget` | Per PR 主 session delta 目標 ≤ 15K tokens；batch overhead 目標 ≤ `N * 15K + 50K`。主 session raw diff output 以單 PR 累積 100 行為 hard cap；觸發後該 PR 維持 hunk-only / sample-only 到 review 完成。Pilot 實測值：`pending_pilot_evidence`。 |
| `raw_evidence_policy` | Full diff、raw comments、PASS CI rollup、raw Slack channel messages 不得直接進 main context。Full diff 存 `/tmp/review-inbox-runs/{run_id}/pr-{number}.diff`；raw Slack messages 由 discovery sub-agent / script 轉 filtered artifacts；comments 只允許 metadata-only dedup。 |
| `reference_compilation` | Review packet 自帶 `review-inbox/dispatch-context-bundle.md` inline bundle 與 verified handbook paths，執行者不讀任何 skill 就做得完。另附延伸參考的**路徑**，讀不讀由執行者判斷——review-inbox 底下不再放 review-pr 那幾份的副本（DP-575 刪掉 6 個檔、453 行）。Bundle size target 沿用 DP-094；本 DP 不重算 bundle size。 |
| `dispatch_facts` | 每張 PR 一個 sub-agent。Packet 交出去的是事實——`cluster_role`、`cluster_size`、`model_tier`、送出授權狀態、延伸參考的路徑——不是結論：用哪一種 agent、幾個並行、先跑哪一張，由執行的人當下判斷。以前這一格是 `runtime_plan`，規定了預設 adapter、禁用 general-purpose sub-agent、以及一份 `build-review-runtime-plan.py` 產生的 plan；DP-575 把三層一起拿掉，理由與量到的數字寫在 `review-inbox-batch-review-flow.md`。**那條禁令代理的「主 session 不讀完整 diff」由本表的 `main_session_budget` 與 `raw_evidence_policy` 直接規定，不隨禁令消失。** |
| `telemetry` | Completion 後以 line-count proxy 產生 run metrics，並透過 `polaris-learnings.sh add --type telemetry --tag review-inbox --metadata '{"review_inbox_run": ...}'` 寫入。Required keys：`run_id`, `candidate_count`, `reviewed_count`, `main_session_input_tokens`, `main_session_output_tokens`, `sub_agent_tokens`, `duration_seconds`, `estimator_kind`。 |
| `verify_report` | Pilot 完成後產生 `docs-manager/src/content/docs/specs/design-plans/DP-113-review-inbox-main-session-token-budget/verify-report.md`（<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 舊層的證據留在 specs 那個 repo，不搬進來 -->），（見上方 external-paths 宣告）至少包含 token、raw evidence routing、artifact sufficiency、quality、telemetry、rollout candidate list。 |

`type=telemetry` 不是 technical learning，不應進入一般 preamble learning。`polaris-learnings.sh`
預設 query 會排除 telemetry；只有明確傳入 `--type telemetry` 或 `--tag review-inbox` 時才查詢
runtime metrics。

## Rollout Candidate Draft

首輪只落地 review-inbox。以下 skill 只列 rollout candidate，需等 review-inbox
`verify-report.md` PASS 後再開 follow-up work：

| Priority | Skill | 第一個 context bloat source |
|---|---|---|
| 1 | `review-pr` | Large PR diff、existing comments、handbook stack。 |
| 2 | `learning` | External article / repo raw content、merged PR history。 |
| 3 | `verify-ac` | Browser evidence、logs、screenshots metadata、AC run output。 |
| 4 | `intake-triage` | Batch ticket descriptions、JIRA comments、priority evidence。 |
| 5 | `converge` | Multi-ticket status scan、PR review comments、CI summaries。 |
| 6 | `refinement Bug source mode` | Logs、stack traces、multi-file debugging evidence。 |
| 7 | `kibana-logs` | Raw production log windows。 |
