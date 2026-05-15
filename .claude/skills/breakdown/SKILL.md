---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 3.3.0
---

# Breakdown — Packer

`breakdown` 是 Packer：接收 refinement artifact、bug-triage RCA、JIRA ticket 或
DP source，把已定案的需求拆成可施工 work orders。它不擁有需求探索或技術決策；需要
改 Goal / Background / Decisions / Blind Spots / Technical Approach 時，route back
to `refinement`。

## Mandatory Contracts

- 開始前讀 `workspace-config-reader.md`、`workspace-language-policy.md`、
  `authoring-preflight.md` 與 root `language`；preview、JIRA comment、task.md / V*.md
  artifact 必須直接用 policy language 起稿，不可把 language gate 當送出前翻譯器。
- 寫入 specs Markdown 時遵守 `starlight-authoring-contract.md`；新 task work order
  預設寫入 folder-native `tasks/Tn/index.md` 或 `tasks/Vn/index.md`，legacy
  `tasks/Tn.md` / `tasks/Vn.md` 只作為既有 artifact fallback；task schema 以
  `task-md-schema.md` 為準。
- 所有 estimate 使用 `estimation-scale.md`；JIRA sub-task / story point 操作使用
  `jira-subtask-creation.md` 與 `jira-story-points.md`。
- 寫入 task.md 前必須有 explicit user confirmation；沒有確認不可寫 JIRA、branch、
  task.md、sidecar processed flag。
- task.md 必須能被 `engineering` 單獨消費：Allowed Files、Gate Closure Matrix、
  Behavior Contract、Test Environment、Verify Command 都要完整。
- 若 task 修改 Polaris deterministic script behavior、release gate、bootstrap/doctor、
  dependency governance 或 selected suite，task.md 必須寫出 script test contract；
  高風險行為變更優先包進 failing selftest → implementation → passing selftest。
  text-only / trivial 文件或 help 文案變更可註明不需新增 failing selftest。
- Story / Task / Epic 拆單前讀 `infra-first-decision.md`；infra prerequisite 只能由
  refinement artifact 的 AC verification methods 推導，不得只因 visual regression config
  存在就加入 fixture task。
- Story / Task / Epic 拆單與 DP-backed task preview 前讀
  `stacked-delivery-sibling-epic-policy.md`；建立 task.md / JIRA child 前必須用
  `scripts/detect-stacked-delivery-lane.mjs` 檢查 draft task set。若結果是 `required`，
  使用者確認 sibling Epic strategy 或 explicit override 前不得寫 task.md、不得寫 JIRA、
  不得建 branch。
- DP-backed work 沒有特殊 execution shortcut。只要 task.md 要 handoff `engineering`，
  就必須沿用與 Epic 相同的正規鏈；`framework-release` 只能作為 engineering PR 之後的
  local extension tail，不得提前取代 `engineering`。
- DP task 若只觸及 local sample / ignored specs artifacts（例如 Allowed Files 全在
  `docs-manager/src/content/docs/specs/**`），不得包成 implementation task handoff
  engineering；必須留在 refinement / breakdown artifact，或另拆真正的 tracked
  releaseable task。
- 任何 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope；同時依
  `model-tier-policy.md` 選 semantic model class。Codex runtime 必須使用 matching
  `polaris-*` child-agent adapter；若 adapter / model 不可用，fallback 只能是 `inherit`，
  並在 Completion Envelope 回報 `Model Fallback: inherit - <reason>`。
- 完成任何 write 後最後跑 Post-Task Reflection。

## Source Routing

先讀 `spec-source-resolver.md` 判斷 source type，再只讀對應 reference：

| Source / signal | Path | Reference |
|---|---|---|
| Bug ticket | Bug RCA estimate / simple fix or planning handoff | `breakdown-bug-flow.md` |
| Story / Task / Epic ticket | JIRA planning, sub-task creation, task.md packaging | `breakdown-planning-flow.md` |
| `DP-NNN` or locked DP artifact | DP-backed `tasks/T{n}.md` without JIRA writes | `breakdown-dp-intake-flow.md` |
| engineering escalation sidecar | scope-escalation intake and planner decision | `breakdown-escalation-intake-flow.md` |
| `scope challenge` / `挑戰需求` | advisory challenge only, no writes unless user later confirms planning | `breakdown-scope-challenge-flow.md` |
| branch/task packaging details needed | branch DAG, task.md / V*.md validation | `breakdown-task-packaging.md` |

## Shared Fail-Stops

- 每種 source 在 work-order packaging 前都必須有對應的 planning handoff：
  refinement-owned DP / Epic / Story / Task 需要 current `refinement.json`；Bug 需要
  `bug-triage` confirmed `[ROOT_CAUSE]` handoff。
- Bug ticket 沒有 `[ROOT_CAUSE]` comment：停止，請使用者先跑 `bug-triage {TICKET}`。
- DP `status: DISCUSSION`：停止，請使用者先跑 `refinement DP-NNN`。
- 新 DP 缺 `refinement.json`：停止並 route back to refinement；legacy DP 需明確標示
  artifact 缺失並請使用者確認。
- Escalation sidecar 缺 gate-closure sections：停止，要求 engineering 重建 sidecar。
- Quality Challenge / Constructability Gate 失敗：不得建 JIRA sub-task、不得產 task.md。
- `validate-task-md.sh` 或 `validate-task-md-deps.sh` 失敗：修 artifact，不得 handoff
  engineering。
- DP-backed task 若混合「tracked releaseable framework work」與「local sample/spec recut」，
  或 Allowed Files 全落在 ignored local artifact surface：停止，回 planning 重拆，不得
  handoff engineering / framework-release。

## Shared Handoff

- 只有在 `validate-task-md.sh`、`validate-task-md-deps.sh`、`validate-breakdown-ready.sh`
  全部通過後，才可提示 `做 {TASK_KEY}`、`做 {EPIC_KEY}` 或 `做 DP-NNN-T1`。
- Scope escalation 處理後，若 task 已修正或新 task 已建立，回到 `engineering`；若
  lineage cap 或 planner decision 指向 refinement，只建立 refinement inbox record 後提示
  `refinement {EPIC}`。

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.

Run the checklist in `post-task-reflection-checkpoint.md`.
