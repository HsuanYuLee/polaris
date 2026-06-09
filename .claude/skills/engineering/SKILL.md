---
name: engineering
description: >
  Engineer-minded execution orchestrator: takes a planned JIRA ticket and implements it with strict quality discipline — TDD, lint, typecheck, test, behavioral verify, PR.
  Two modes: first-cut (new implementation) and revision (fix PR review comments by returning to the work order).
  Local-only workflows may register delivery extensions, but those extensions are not part of the portable skill contract.
  Supports batch mode via parallel sub-agents.
  Trigger: "做 PROJ-123", "work on", "engineering", "開始做", "接這張", "做這張",
  "修 PROJ-123", "fix review on PROJ-123", PR URL (from pr-pickup or direct),
  or user provides JIRA ticket key(s).
  NOT for planning: Bug → bug-triage first; Story/Task/Epic → breakdown first.
  Key distinction: "下一步" / "繼續" without ticket key → my-triage (zero-input router + resume scan).
tier: product
metadata:
  author: Polaris
  version: 5.3.1
---

# Engineering

`engineering` 是純施工 skill。唯一施工來源是 authoritative task.md；JIRA、PR、
review comments、CI 都只是 side effect 或 revision signal，不是施工圖。規劃、估點、
RCA、scope ownership 由 `bug-triage` / `breakdown` / `refinement` 持有。

## Mandatory Authority

- Mandatory gate 只有 pass 或 fail-stop；沒有 LLM 自行 skip 的第三條路。
- Hook / wrapper / completion gate 是 enforcement，不是前置步驟豁免。
- 產品 repo CI declarations（Woodpecker、GitHub Actions、Codecov、husky、pre-commit、
  package scripts）不是 engineering 修補面；CI parity / config 問題要停下記錄 owner
  decision；`BLOCKED_ENV` 語意與 retry/escalation contract 以 `ci-local-env-blocker.md`
  為準。
- planner-owned task.md 欄位（Allowed Files、estimate、Test Command、Verify Command、
  Test Environment、depends_on）不可由 engineering 手動改；需要改時走 scope escalation。
- First-cut branch setup 必須先執行 readiness pack（`validate-task-md.sh`、
  `validate-task-md-deps.sh`、`validate-breakdown-ready.sh`、`resolve-task-base.sh`、
  `resolve-task-branch.sh`），並在 fresh worktree 建立後寫入 planner-owned 欄位 baseline
  snapshot。finalize / completion / revision gate 若偵測 snapshot 缺失或 mismatch，必須
  停止並走 scope escalation；不得就地修改 task.md 讓 gate 通過。
- engineering 只能用 helper-only contract 寫 execution-owned lifecycle metadata，例如
  deliverable / extension_deliverable / status move-first closeout。
- 開始前讀 workspace config、company handbook index + linked docs、repo handbook index +
  linked docs；缺 company handbook 要明記，不可跳過 repo handbook。
- fresh worktree / checkout 跑 Test Command 或 Verify Command 前，先用
  `scripts/env/install-project-deps.sh --task-md <task.md> --cwd <repo>` 消費
  `## Required Tools` 與 project dependency contract。缺 ticket-scoped 工具且 task.md 沒有可執行
  install command 時，視為 `BLOCKED_ENV`，依 handoff_hint 提醒使用者安裝或授權。
- 任何 sub-agent dispatch 前，先讀 `sub-agent-roles.md` 並注入 Completion Envelope；
  Codex runtime / model fallback contract 見該 reference § Runtime Adapter Contract /
  Fallback Behavior。Implementation、CI/debug、PR review 與 correctness review 不得降到
  `small_fast` / `realtime_fast`。
- downstream-facing PR body、commit message、handoff、sidecar、JIRA / Slack text 必須遵守
  `workspace-language-policy.md`；specs Markdown 另遵守 `starlight-authoring-contract.md`。
- 寫 artifact 前必讀 `pipeline-handoff.md` § Artifact Schemas，再讀
  `refinement-artifact.md` / `task-md-schema.md` 等對應 artifact-specific schema。atom
  ownership 邊界以 `pipeline-handoff-atom-matrix.md` 為準；SKILL 主文不複製完整 schema 表。
- **Consumer boundary（DP-238 AC2）**：engineering 的唯一施工輸入是 authoritative
  task.md（Allowed Files / Scope Trace Matrix / Verify Command）。engineering
  **不直接讀 refinement.json** 的 `acceptance_criteria` / `modules` 補 scope authority；
  work-order derivation 是 `breakdown` 的 owning scope。需要改 scope 時走 scope
  escalation 回 breakdown，不從 refinement.json 自行 re-derive（atom matrix
  `t_task_work_order` row）。
- 開始撰寫 PR title/body 前必須先讀 `pr-body-builder.md`，並依該 reference 的 L1→L2→L3
  template detection 讀 repo PR template；PR body draft 必須從 template skeleton 起稿，不可先
  用 generic summary 再等 `gate-pr-body-template.sh` 擋下重寫。

## Canonical / Standalone Handoff Contract（DP-296 AC6）

engineering 作為 consumer，預設 traverse breakdown 產出的 **canonical** `task.md`
schema（`Allowed Files` / Scope Trace Matrix / Verify Command）作為唯一施工輸入，**不**
改去解析 refinement / breakdown 的 LLM freeform prose 補 scope 缺口（對齊上方 Consumer
boundary 條文）。engineering 作為 producer，寫入 canonical proof-of-work marker 與
deliverable lifecycle metadata 給下游 verify-AC / closeout 機械消費。LLM freeform 只在
**standalone** 情境合法——亦即該產出沒有下游 pipeline consumer 會機械消費它（例如對使用者
的 status 說明）。會被下一段 skill 機械消費的 handoff artifact 一律走 canonical schema。
本契約只約束 handoff artifact 介面，**不**約束 engineering 內部如何 TDD、debug 或組織實作
reasoning。完整契約見 `.claude/skills/references/pipeline-handoff.md` § Canonical Schema
Traversal Contract。

## Mode Routing

先讀 `engineering-entry-resolution.md`，用 resolver 找到單一 task.md，再由 work order
派生 mode：

| Condition | Mode | Reference |
|---|---|---|
| `deliverable.pr_url` empty | first-cut | `engineering-first-cut-flow.md` |
| `deliverable.pr_url` open PR | revision | `engineering-revision-flow.md` |
| local policy declares extension for this DP task | first-cut + local extension tail | `engineering-local-extension.md` |
| multiple inputs | batch dispatch | `engineering-entry-resolution.md` |
| gate failure needs planner-owned field change | scope escalation | `engineering-scope-escalation.md` |

## Shared Delivery Backbone

所有 implementation / revision 都必須讀 `engineer-delivery-flow.md`，並依 role 執行：

- Developer：Scope Gate → ci-local → run-verify-command → flow gap audit → VR if
  triggered → behavior contract compare if declared → evidence upload bundle if local media
  evidence exists → base freshness → commit → PR → JIRA → completion gate → worktree cleanup。
- Local Extension：同樣先完成 engineering evidence gates，再依 local policy 交給 extension；
  extension 不得降低 gate。
- Mutable PR lane 先讀 `pr-state-contract.md`，再 consume shared PR state：
  `resolve-pr-work-source.sh` →
  `pr-state-snapshot.sh` → `pr-action-classifier.sh`。對外 readiness 語彙只能使用
  `review_required`、`awaiting_re_review`、`mergeable_ready`、`needs_code_changes`、
  `blocked_conflict`、`unsupported_mutation`、`wait_ci`、`planning_gap`。

## Fail-Stops

- 無 task.md、命中多個 task.md、Epic key 無法 resolve 單一 task：停止，回上游補 work
  order。
- Work order 有 merged / closed PR deliverable 但 task lifecycle 未對齊：停止，修 task
  metadata / closeout，不施工。
- Duplicate branch / remote branch / stale worktree：停止，resume / revision / cleanup，
  不開第二條 implementation branch。
- Framework source mutation 只能在 engineering task worktree 內發生。main checkout 上的
  framework-owned dirty source（`scripts/**`、`.claude/skills/**`、`.claude/rules/**`、
  `.claude/instructions/**`、`CLAUDE.md`、`AGENTS.md`、`.codex/**`、`.agents/**` 等）
  是 fail-stop；不得把 main dirty 當成可直接續做的施工面。
- shared PR state 若是 `unsupported_mutation`、`blocked_conflict`、或
  `stale_downstream`，停止把 revision lane 說成「已收斂」或「可 review」。
- Review signal 分類出 plan gap / spec issue：停止，寫 handoff / learning，需要
  breakdown 或 refinement。
- Scope escalation sidecar validator 未 pass：不得結束 session，也不得 push / PR。
- DP-201 proof-of-work marker contract 生效後，engineering 是 `pr_freshness`、
  `completion_gate`、`blocked_conflict`、`unsupported_mutation`、`ci_local` marker 的 owning
  writer；Layer B `verify` marker 的 writer 維持 `run-verify-command.sh`。Marker schema、
  producer mapping 與 freshness rule 以 `auto-pass-proof-of-work.md` /
  `scripts/lib/evidence-producers.json` 為準；不得以 final answer、JIRA-only state 或 `/tmp`
  only artifact 代替 durable marker。

## Skill Workflow Boundary Gate (DP-230 D40)

`engineering` session 開始 implementation 之前（branch / worktree 建好後）必須
呼叫 skill-workflow-boundary baseline writer，並把 task.md 路徑傳進來，scope
會由 task.md `## Allowed Files` 推導：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill engineering --start \
  --source-container "$SOURCE_CONTAINER" --task-md "$TASK_MD"
```

commit / PR / completion gate 之前（也就是 `engineer-delivery-flow.md` 的 Scope
Gate 步驟內）必須再跑 `--check`：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill engineering --check \
  --source-container "$SOURCE_CONTAINER" --task-md "$TASK_MD"
```

任何 Allowed Files 之外的新增/修改都會 exit 1 + 輸出
`POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:engineering`；engineering 不得就地改
Allowed Files 來通過 gate，必須走 `engineering-scope-escalation.md`。

`POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 等 env 不能
silence 這個 gate（AC-NEG16）。

## L2 Deterministic Check: version-bump-reminder

Delivery tail 依 `engineer-delivery-flow.md` 執行；framework 相關變更需呼叫
`scripts/check-version-bump-reminder.sh`。

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`。

## Post-Task Reflection (required)

見 `post-task-reflection-checkpoint.md`；write 後必跑、不可跳過。
