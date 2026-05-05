---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 3.2.1
---

# Breakdown — Packer

`breakdown` 是 Packer：接收 refinement artifact、bug-triage RCA、JIRA ticket 或
DP source，把已定案的需求拆成可施工 work orders。它不擁有需求探索或技術決策；需要
改 Goal / Background / Decisions / Blind Spots / Technical Approach 時，route back
to `refinement`。

## Mandatory Contracts

- 開始前讀 `workspace-config-reader.md`、`workspace-language-policy.md` 與 root
  `language`；preview、JIRA comment、task.md / V*.md artifact 預設使用 policy
  language。
- 寫入 specs Markdown 時遵守 `starlight-authoring-contract.md`；task schema 以
  `task-md-schema.md` 為準。
- 所有 estimate 使用 `estimation-scale.md`；JIRA sub-task / story point 操作使用
  `jira-subtask-creation.md` 與 `jira-story-points.md`。
- 寫入 task.md 前必須有 explicit user confirmation；沒有確認不可寫 JIRA、branch、
  task.md、sidecar processed flag。
- task.md 必須能被 `engineering` 單獨消費：Allowed Files、Gate Closure Matrix、
  Behavior Contract、Test Environment、Verify Command 都要完整。
- 任何 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope。
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

- Bug ticket 沒有 `[ROOT_CAUSE]` comment：停止，請使用者先跑 `bug-triage {TICKET}`。
- DP `status: DISCUSSION`：停止，請使用者先跑 `refinement DP-NNN`。
- 新 DP 缺 `refinement.json`：停止並 route back to refinement；legacy DP 需明確標示
  artifact 缺失並請使用者確認。
- Escalation sidecar 缺 gate-closure sections：停止，要求 engineering 重建 sidecar。
- Quality Challenge / Constructability Gate 失敗：不得建 JIRA sub-task、不得產 task.md。
- `validate-task-md.sh` 或 `validate-task-md-deps.sh` 失敗：修 artifact，不得 handoff
  engineering。

## Shared Handoff

- JIRA planning 完成後提示 `做 {TASK_KEY}` 或 `做 {EPIC_KEY}` 的下一個 READY task。
- DP planning 完成後提示 `做 DP-NNN-T1`。
- Scope escalation 處理後，若 task 已修正或新 task 已建立，回到 `engineering`；若
  lineage cap 或 planner decision 指向 refinement，只建立 refinement inbox record 後提示
  `refinement {EPIC}`。

## 17. L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.

Run the checklist in `post-task-reflection-checkpoint.md`.
