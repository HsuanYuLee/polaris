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

## No-Bypass Contract

engineering PR delivery 不接受任何 create-time 或 readiness-time shortcut。合法 PR path
必須從 resolved authoritative task.md 開始，並保留下列機械事實：

- `resolve-task-md.sh --write-lock` 產生的 resolver lock。
- `engineering-branch-setup.sh` 寫入的 planner-owned readiness / baseline snapshot。
- `skill-workflow-boundary-gate.sh --start/--check` 的 engineering boundary marker。
- `run-verify-command.sh` / completion gate 寫入的 engineering completion marker。
- `polaris-pr-create.sh` provenance、non-draft PR、base freshness current。

`codex-guarded-gh-pr-create.sh` 不得接受 `--skip-gates`；`pr-create-guard.sh` 不得用
`POLARIS_PR_WORKFLOW=1` 或其他 env 讓裸 `gh pr create` 通過。外部已建立的 PR 無法在
provider create-time 被撤回，但後續 readiness / completion / auto-pass ownership payload
必須以 `scripts/auto-pass-pr-ownership-gate.sh` 拒收缺 lineage、resolver lock、baseline
snapshot、boundary marker 或 completion marker 的 PR。framework-release tail 使用自己的
release-specific readiness check，不把 generic engineering bypass 當 carve-out。

Framework/control-plane source 寫入不得繞過 `scripts/validate-framework-source-write.sh`。
進入 first-cut / revision 後，resolved task.md 必須可由 hook / wrapper 取得（建議設定
`POLARIS_TASK_MD`，或在 deterministic script call 傳 `--task-md`）；validator 只接受
task.md `## Allowed Files` 內的 framework-owned path。缺 task.md、未知 writer、或越界 path
都以 `POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:*` fail-closed。

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

Framework-owned DP task 進 first-cut 前，若 task 屬於多 task DP 且後續交由
`framework-release`，先以 `scripts/resolve-handbook.sh --project polaris-framework` 取得
canonical handbook payload。在 codebase exploration 前讀 `index_path`、從 `narrative_paths`
取得 `changeset-convention.md` 與 `release-topology.md`，並呼叫
`scripts/validate-handbook-load-gate.sh` 建立 session/repo marker；first-touch gate 只作 backstop。
以 `release-topology.md` 理解 task PR 的 stack / release base。施工權威仍是 resolved
`task.md`；handbook 不覆寫 Allowed Files、Verify Command 或
deliverable state。

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
