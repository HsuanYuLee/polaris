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
  version: 5.3.0
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
  decision。
- planner-owned task.md 欄位（Allowed Files、estimate、Test Command、Verify Command、
  Test Environment、depends_on）不可由 engineering 手動改；需要改時走 scope escalation。
- engineering 只能用 helper-only contract 寫 execution-owned lifecycle metadata，例如
  deliverable / extension_deliverable / status move-first closeout。
- 開始前讀 workspace config、company handbook index + linked docs、repo handbook index +
  linked docs；缺 company handbook 要明記，不可跳過 repo handbook。
- 任何 sub-agent dispatch 前，先讀 `sub-agent-roles.md` 並注入 Completion Envelope。
- downstream-facing PR body、commit message、handoff、sidecar、JIRA / Slack text 必須遵守
  `workspace-language-policy.md`；specs Markdown 另遵守 `starlight-authoring-contract.md`。

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
  triggered → evidence upload bundle if local media evidence exists → base freshness → commit
  → PR → JIRA → completion gate → worktree cleanup。
- Local Extension：同樣先完成 engineering evidence gates，再依 local policy 交給 extension；
  extension 不得降低 gate。

## Fail-Stops

- 無 task.md、命中多個 task.md、Epic key 無法 resolve 單一 task：停止，回上游補 work
  order。
- Work order 有 merged / closed PR deliverable 但 task lifecycle 未對齊：停止，修 task
  metadata / closeout，不施工。
- Duplicate branch / remote branch / stale worktree：停止，resume / revision / cleanup，
  不開第二條 implementation branch。
- Review signal 分類出 plan gap / spec issue：停止，寫 handoff / learning，需要
  breakdown 或 refinement。
- Scope escalation sidecar validator 未 pass：不得結束 session，也不得 push / PR。

## Step 9 — L2 Deterministic Check: version-bump-reminder

Delivery tail 依 `engineer-delivery-flow.md` 執行；framework 相關變更需呼叫
`scripts/check-version-bump-reminder.sh`。

## Step 10 — L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`，再執行 Post-Task Reflection。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.

Run the checklist in `post-task-reflection-checkpoint.md`.
