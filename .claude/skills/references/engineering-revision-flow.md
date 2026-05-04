---
title: "Engineering Revision Flow"
description: "engineering revision mode：pre-revision rebase、review/CI signal collection、classification、fix, verify, reply, lesson extraction。"
---

# Revision Flow

## R0. Rebase And PR Base Sync

revision mode 進入後先跑：

```bash
scripts/revision-rebase.sh
```

可用 `--task-md`、`--pr`、`--repo`。Script 負責 task.md 定位、Branch chain cascade
rebase、resolve base、fetch、rebase、PR base sync。

Exit：

- `0`：進 R1。
- `1`：conflict / fetch / PR base edit failure，停止回報。
- `2`：usage error。

不要信任 PR `baseRefName` 作為 source of truth；task.md + resolver 才是 base authority。

## R1. Read Work Order And Handbook

用 `parse-task-md.sh` 讀完整 task JSON 與欄位：Allowed Files、test_command、
verify_command、Test Environment、AC / verification context。不要回 JIRA 補語意。

同一步完成 handbook gate：company handbook index + linked docs，repo handbook index +
linked docs。

## R2. Collect Signals

收集：

```bash
gh api repos/{org}/{repo}/pulls/{pr_number}/reviews --paginate
gh api repos/{org}/{repo}/pulls/{pr_number}/comments --paginate
gh api graphql ... reviewThreads ...
gh pr checks {pr_number} --repo {org}/{repo}
```

Thread-level status mandatory；flat comments 不能判斷 resolved/outdated。

Active signals：

- unresolved, non-outdated root inline comments。
- reviewer newer follow-up after implementer reply。
- completed and explicit failed CI checks。
- Codecov fail 也是 blocker；帳號 activation / visibility 文案不能豁免 failed state。

Queued / pending / running 不是 revision signal。

Empty signal -> rebase-only path：跳過 R3/R4，直接 R5 完整驗收。

## R3. Classify

每個 signal 對照 task.md：

| Class | Meaning |
|---|---|
| code drift | implementation deviates from plan; fix in revision |
| plan gap | plan omitted case; stop and route breakdown |
| spec issue | requirement / AC issue; stop and route refinement / planner |

Interactive variant 只在使用者要求逐一確認時啟用；確認的是整體修正策略，不是一個
comment 一次中斷。

## R3a. Plan Gap / Spec Issue

若任一 signal 是 plan gap / spec issue，停止。輸出 signal、分類、理由與 route：

- plan gap -> breakdown。
- spec issue -> refinement / PM decision。

不要在 revision mode 就地補 task.md 或擴 scope。

## R4. Fix Code Drift

只修 code drift。遵守 task Allowed Files；超出範圍或需要 planner-owned 欄位變更時，
走 `engineering-scope-escalation.md`。

## R5. Re-Verify

所有 revision path 都必經完整驗收，包括 rebase-only：

- task test command。
- ci-local。
- run-verify-command。
- VR if triggered。
- base freshness / completion gates。

修完 code 後舊測試結果作廢，必須重跑。

## R6. Reply And Learn

對每個 active root inline comment 的 exact `databaseId` 回覆修正說明。Outdated /
resolved threads 不回覆，但保留 evidence summary。

從 reviewer feedback 萃取可重用 lesson 時，依 `review-lesson-extraction.md` dedup and
write。需要 PR body / comment / JIRA / Slack text 時，先跑 language gate。

最後推 branch，更新 PR / task lifecycle，並跑 Post-Task Reflection。
