---
name: converge
description: "Use when the user wants to push all in-flight work forward toward review in one pass — closing gaps across Epics, Bugs, and orphan Tasks. NOT for single-ticket work (use engineering) or read-only triage (use my-triage). Trigger: '收斂', 'converge', '推進', '全部推到 review', '把我的單收一收', 'epic 進度', '離 merge 還多遠', '補全'."
metadata:
  author: Polaris
  version: 1.1.0
---

# Converge

`converge` 是 batch convergence orchestrator：掃描使用者名下 active work，找出離
review / merge 的 gap，提出排序後的推進計畫，經使用者確認後才逐項委派下游 skill。

## Contract

`converge` 不是單張 ticket 施工（用 `engineering`），也不是 read-only dashboard（用
`my-triage`）。它可以路由到 `breakdown`、`engineering`、`check-pr-approvals`、
`feature-branch-pr-gate.md`，但不取代下游 skill 的 gate 或 ownership。

若使用者指定 Epic key，只掃該 Epic 與子單；未指定 ticket 時掃 assigned active work。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `converge-scan-gap-flow.md`, `workspace-config-reader.md`, `shared-defaults.md`, `jira-story-points.md` |
| PR / feature branch state | `stale-approval-detection.md`, `feature-branch-pr-gate.md`, `pr-input-resolver.md` |
| Execution after confirmation | `converge-execution-flow.md`, `sub-agent-roles.md`, `workspace-language-policy.md` |
| Report / artifacts | `converge-reporting-flow.md`, `starlight-authoring-contract.md` |

Any sub-agent dispatch must include `sub-agent-roles.md` Completion Envelope.

## Flow

1. Load workspace config and resolve global mode or Epic-only mode.
2. Fetch active assigned tickets and Epic children.
3. Scan GitHub PR / feature branch state using the bundled reference scripts where available.
4. 分類所有 gap，依「自己可推進、離 review 最近」排序。
5. 呈現 Converge Plan，等待使用者明確確認或調整。
6. After confirmation, execute selected items through downstream skills.
7. Rescan and produce before/after report, skipped items, blockers, and next actions.

## Hard Rules

- Do not execute Phase 3 before user confirmation; batch changes need review.
- Do not modify JIRA status directly; downstream skills own status movement.
- Do not parallelize heavy `NOT_STARTED` implementation tickets.
- Do not treat `WAITING_QA` / `WAITING_RELEASE` as gaps.
- 不處理其他 assignee 的 tickets，除非使用者明確縮小或改寫範圍。
- External Slack / JIRA / PR-facing text must pass `workspace-language-policy.md`.
- Markdown artifacts under specs must pass `starlight-authoring-contract.md`.

## Completion

Return scanned counts, gap counts, selected execution list, per-ticket result, before/after gap
matrix, skipped waiting items, failed/blocker items, and follow-up routes.

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
