---
title: "Engineering First Cut Flow"
description: "engineering first-cut mode：resolve work order、branch/worktree setup、TDD、delivery backbone 與 completion closeout。"
---

# First-Cut Flow

## Resolve Work Order

先用 `engineering-entry-resolution.md` 定位單一 task.md。找不到就停止，不做 planning。

## Optional Contract Check

若 work order 涉及 fixtures / API contract，先讀 `api-contract-guard.md` 並跑對應
contract check。這是前置驗證，不改變 mode。

## Branch And Worktree Setup

1. JIRA transition in development 用 `scripts/polaris-jira-transition.sh`，soft-fail。
2. 建 branch / worktree 只能用：

   ```bash
   bash "${POLARIS_ROOT}/scripts/engineering-branch-setup.sh" "<path/to/task.md>"
   ```

3. 若 task.md 有 Branch chain，script 會先 cascade rebase 上游鏈再切本 task branch。
4. duplicate branch / remote / stale worktree 時停止，不手動改名再開新 branch。

First-cut 不再需要獨立 pre-development rebase；branch setup 已從 resolved base tip 切出。

## TDD And Implementation

順序：

1. 讀 company handbook index + linked docs，再讀 repo handbook index + linked docs。
2. 讀 project `CLAUDE.md`（若存在）。
3. 讀 `tdd-smart-judgment.md`；依檔案性質判斷是否 TDD。
4. 安裝依賴：

   ```bash
   bash {polaris_root}/scripts/env/install-project-deps.sh --task-md {task_md_path} --cwd "$(git rev-parse --show-toplevel)"
   ```

5. 用 `scripts/parse-task-md.sh` 取得 `test_command`、`verify_command`、Test
   Environment。不可自行推導。
6. runtime level 用 `scripts/start-test-env.sh`；不要手拼 docker / dev server。
7. canonical `polaris-config/{project}/generated-scripts/ci-local.sh` 存在時必跑：

   ```bash
   bash "${POLARIS_ROOT}/scripts/ci-local-run.sh" --repo "$(git rev-parse --show-toplevel)"
   ```

Migration blocker 不可被當作 skip reason。

## Behavior Baseline

若 task.md 宣告 `verification.behavior_contract.applies: true`，先讀
`behavior-contract.md`。`mode=parity` 或 `mode=hybrid` 時，implementation 前必須先跑：

```bash
bash "${POLARIS_ROOT}/scripts/run-behavior-contract.sh" --task-md "<path/to/task.md>" --mode baseline
```

已施工或 resume 場景若沒有 before evidence，runner 會依 `baseline_ref` 建 temp worktree
補錄 baseline。缺 baseline 不可繼續完成 delivery。

## Delivery

開發完成後讀 `engineer-delivery-flow.md`，Role = Developer；若命中 local extension，
Role = Local Extension 並讀 `engineering-local-extension.md`。

Developer path：

- Simplify / self-review。
- Scope gate。
- `ci-local.sh`。
- `run-verify-command.sh`。
- `run-behavior-contract.sh --mode compare` if behavior contract applies。
- post-implementation flow gap audit。
- VR if triggered。
- base freshness。
- commit。
- PR via `scripts/polaris-pr-create.sh`，不可 draft。
- JIRA transition / comment。
- completion gate。
- worktree cleanup。

最後跑：

```bash
bash "${POLARIS_ROOT}/scripts/finalize-engineering-delivery.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --ticket "{ticket_key}" \
  --workspace "{workspace_root}"
```

這支 helper 負責 task move-first closeout、parent closeout NOOP / closure、implementation
worktree cleanup。不得手動掃 folder 改 parent lifecycle。
