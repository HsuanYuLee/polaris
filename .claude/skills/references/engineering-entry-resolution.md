---
title: "Engineering Entry Resolution"
description: "engineering entry resolution：resolve authoritative task.md、derive mode、duplicate work guard、batch dispatch contract。"
---

# Entry Resolution

Engineering 的入口目標只有一個：找到 authoritative work order。不要先讀 JIRA 狀態或
PR comments 來猜流程。

## Supported Inputs

用 `scripts/resolve-task-md.sh --write-lock` 解析：

| Input | Resolver |
|---|---|
| task.md path | `resolve-task-md.sh --write-lock <path>` |
| JIRA ticket key | `resolve-task-md.sh --write-lock <KEY>` |
| DP pseudo-task ID | `resolve-task-md.sh --write-lock <DP-NNN-Tn>` |
| PR URL / number | `resolve-task-md.sh --write-lock <PR_REF>` |
| current branch / raw user message | `--current` or `--from-input "{raw_user_msg}"` |

Resolver 成功後結果就是 authoritative；不得再用 `find` / `rg` / ad hoc fallback 覆寫。
若要重新解析，先 `scripts/resolve-task-md.sh --clear-lock`。

## Work Order Gate

唯一合法施工來源是 canonical task.md：

- Product task：`docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/tasks/T{n}.md`
- DP task：`docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T{n}.md`

可 fallback 到 `tasks/pr-release/T{n}.md` 讀已 closeout artifact，但不得讀 legacy
`specs/{TICKET}/plan.md` 當施工圖。

JIRA 在 engineering 是 write-only side effect；不可讀 JIRA description / comment /
status 當施工指令來源。Epic key 無法 resolve 到單一 task.md 時 fail loud。

## Mode Derivation

讀 work order 後依 `deliverable.pr_url`：

| State | Mode |
|---|---|
| empty / null | first-cut |
| open PR | revision |
| merged / closed PR | fail loud，先修 lifecycle / deliverable state |

DP-backed task 若 local policy 明確宣告 delivery extension，first-cut 的尾段可接
local extension；resolver、handbook、TDD、ci-local、verify、scope、base freshness 不變。

## Duplicate Work Guard

First-cut 建 branch / worktree 前，必須由 `scripts/engineering-branch-setup.sh` 執行
duplicate guard。若同一 `identity.work_item_id` 已存在 local branch、remote branch 或
engineering worktree，且不是同一條 registered worktree 的續做，停止施工。

`jira_key` 只用於 JIRA side effect；branch / worktree / handoff identity 使用
`work_item_id`。

## Batch Mode

多輸入時：

1. 每項先 resolve 成單一 task.md。
2. 無法 resolve 的項目標示 blocked，不施工。
3. 可 resolve 的項目各自派生 first-cut / revision。
4. 同 repo 使用 worktree 隔離；跨 repo 可平行。

Sub-agent prompt 保持最小：唯一施工來源是 task.md；先讀 company/repo handbook；
first-cut 用 `engineering-branch-setup.sh`；revision 先跑 `revision-rebase.sh`；驗證與交付
依 `engineer-delivery-flow.md`。

## Workspace Overlay

Framework worktree 若需讀 main checkout 的 ignored specs、`.codex/` runtime context 或
maintainer-local skills，依 `workspace-overlay.md` 與 `scripts/resolve-workspace-overlay.sh`
解析 read-only overlay。Tracked implementation、commit、PR 仍留在 task worktree；
`docs-manager/dist` 永遠不是 authoring source。
