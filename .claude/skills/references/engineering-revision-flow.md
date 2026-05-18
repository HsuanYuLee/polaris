---
title: "Engineering Revision Flow"
description: "engineering revision mode：pre-revision rebase、review/CI signal collection、classification、fix, verify, reply, lesson extraction。"
---

# Revision Flow

## R0. Fresh Worktree, Rebase, And PR Base Sync

revision mode 進入後必須先建立 fresh revision worktree。不得在舊 PR worktree、
main checkout、或先前 review pass 的 worktree 繼續修：

```bash
scripts/engineering-revision-worktree-setup.sh --repo <repo> --task-md <task.md> --pr <pr_number>
```

此 helper 從 PR branch/head 建立一次性 detached worktree；同 identity clean stale
worktree 會先清掉，dirty / unsafe stale worktree 會 fail-stop。後續 R0-R6 的 `--repo`
都指向這個 fresh worktree。

fresh worktree 建好後跑：

```bash
scripts/revision-rebase.sh
```

可用 `--task-md`、`--pr`、`--repo`。Script 負責 task.md 定位、Branch chain cascade
rebase、resolve base、fetch、rebase、PR base sync。

成功後 script 會寫 head-bound R0 evidence：

- `/tmp/polaris-revision-rebase-{TICKET_OR_TASK}-{HEAD_SHA}.json`
- `{main_checkout}/.polaris/evidence/revision-rebase/polaris-revision-rebase-{TICKET_OR_TASK}-{HEAD_SHA}.json`

Existing PR push 由 `gate-revision-rebase.sh` 檢查此 evidence；缺 evidence 代表 R0 沒有對
current HEAD 執行，不能 push revision。

Exit：

- `0`：進 R1。
- `1`：conflict / fetch / PR base edit failure，停止回報。
- `2`：usage error。

不要信任 PR `baseRefName` 作為 source of truth；task.md + shared resolver 才是 base authority。
R0 成功後先確認 shared PR state 允許 mutable lane：

```bash
bash scripts/resolve-pr-work-source.sh --repo <repo> --task-md <task.md> --intent mutable
```

若結果是 `unsupported_mutation`、`external_base`、或 `stale_downstream`，停止；先處理 authority /
lineage，再進 R1-R6。

## R1. Read Work Order And Handbook

用 `parse-task-md.sh` 讀完整 task JSON 與欄位：Allowed Files、test_command、
verify_command、Test Environment、AC / verification context。不要回 JIRA 補語意。

同一步完成 handbook gate：company handbook index + linked docs，repo handbook index +
linked docs。

在進入 code drift 修正前，revision lane 必須確認 branch setup 時寫入的 planner-owned
baseline snapshot 仍可通過：

```bash
bash scripts/validate-task-md.sh --snapshot "<baseline-snapshot.json>" "<task.md>"
```

若 snapshot 缺失，或 `Verify Command`、`depends_on`、`Base branch`、`Allowed Files`
任一欄位與 snapshot 不一致，停止並寫 scope escalation sidecar，route 回 `breakdown`。
revision 不得就地修 task.md 後繼續施工。

## R2. Collect Signals

收集：

```bash
gh api repos/{org}/{repo}/pulls/{pr_number}/reviews --paginate
gh api repos/{org}/{repo}/pulls/{pr_number}/comments --paginate
gh api graphql ... reviewThreads ...
bash scripts/pr-state-snapshot.sh --repo <repo> --task-md <task.md> --intent mutable
bash scripts/pr-action-classifier.sh --repo <repo> --task-md <task.md> --intent mutable
```

Thread-level status mandatory；flat comments 不能判斷 resolved/outdated。
PR readiness / CI / review vocabulary 必須以 `pr-state-contract.md` 與 shared PR state
scripts 為 authority；不要另外用 ad-hoc `gh pr checks --json` 或 legacy status helper 推論
`awaiting_re_review` / `mergeable_ready`。

GitHub plugin helper boundary：`github:gh-address-comments` 或其他 GitHub plugin workflow 可作為
R2 的讀取輔助，用來取得 thread-aware review data；但它不是 revision flow authority。其 generic
Write Safety、互動式確認、或完成語彙不得覆蓋本檔 R3-R6、shared PR state scripts、或
`engineering` completion gate。

Active signals：

- unresolved, non-outdated root inline comments。
- reviewer newer follow-up after implementer reply。
- completed and explicit failed CI checks。
- Codecov fail 也是 blocker；帳號 activation / visibility 文案不能豁免 failed state。

Queued / pending / running 不是 revision signal。

Empty signal -> rebase-only path：跳過 R3/R4，直接 R5 完整驗收。

## R3. Classify

每個 signal 對照 task.md，並映射到 shared classifier：

| Class | Meaning |
|---|---|
| code drift | implementation deviates from plan; fix in revision |
| plan gap | plan omitted case; stop and route breakdown |
| spec issue | requirement / AC issue; stop and route refinement / planner |

對外 readiness 語彙只允許：`needs_code_changes`、`planning_gap`、`blocked_conflict`、
`wait_ci`、`review_required`、`awaiting_re_review`、`mergeable_ready`。

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
- behavior contract compare；若 `parity` / `hybrid` 缺 baseline，先用
  `scripts/run-behavior-contract.sh --mode baseline` 依 `baseline_ref` 補錄 before evidence。
- VR if triggered。
- base freshness / completion gates。

修完 code 後舊測試結果作廢，必須重跑。

## R6. Reply And Learn

對每個 unresolved root inline comment 的 exact `databaseId` 回覆修正說明；包含
non-outdated active thread 與 GitHub 已標 `isOutdated=true` 但仍 unresolved 的 thread。
Outdated thread 的回覆要明說 disposition，例如「這段 diff 已移除 / 被後續 commit 取代 /
已用另一個檔案修正」，然後 resolve conversation。只有已 resolved 的 thread 不回覆，但
保留 evidence summary。

這是 `engineering` revision mode 的 external-write obligation；不需要因為 GitHub plugin helper 的
generic Write Safety 另行詢問使用者是否允許回覆。若 review feedback 已分類為 code drift 並完成
R5 re-verify，就依本節回覆 / resolve；若 feedback 是 plan gap 或 spec issue，依 R3a fail-stop，
不要用 plugin workflow 繞過。

Closeout 報告不得只列 `active_unresolved_threads`；必須同時列出 total unresolved 與
outdated unresolved 的 disposition，避免 GitHub UI 仍顯示 unresolved conversation 時被誤判成
「沒修」。

從 reviewer feedback 萃取可重用 lesson 時，依 `review-lesson-extraction.md` dedup and
write。需要 PR body / comment / JIRA / Slack text 時，先跑 language gate。

最後推 branch，更新 PR / task lifecycle，並跑 Post-Task Reflection。只有 shared classifier
輸出 `awaiting_re_review` 才能說「請 reviewer re-review」；只有 `mergeable_ready` 才能升格成
merge lane readiness。沒有 snapshot-backed evidence 時不得口頭宣稱「已修好」。
