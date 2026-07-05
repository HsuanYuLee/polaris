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

First-cut worktree 是一次性環境：

- 每次開發都必須建立 fresh worktree。
- 不可以回傳或沿用既有 worktree path。
- 同 identity 若有 clean stale worktree，setup helper 會先清掉再建立新的 worktree。
- dirty / unsafe stale worktree 會 fail-stop；先處理內容，再重跑 setup。

1. JIRA transition in development 用 `scripts/polaris-jira-transition.sh`，soft-fail。
2. 建 branch / worktree 只能用 setup helper，並立刻 capture stdout 最後一行為
   `WORKTREE_PATH`：

   ```bash
   SETUP_OUTPUT="$(bash "${POLARIS_ROOT}/scripts/engineering-branch-setup.sh" "<path/to/task.md>")"
   printf '%s\n' "$SETUP_OUTPUT"
   WORKTREE_PATH="$(printf '%s\n' "$SETUP_OUTPUT" | tail -n 1)"
   test -d "$WORKTREE_PATH"
   test "$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel)" = "$WORKTREE_PATH"
   ```

3. 若 task.md 有 Branch chain，script 會先 cascade rebase 上游鏈再切本 task branch。
4. duplicate branch / remote 時停止，不手動改名再開新 branch；stale worktree 只能由 setup helper 清理，不可人工拿舊 path 繼續做。
5. `WORKTREE_PATH` 是 first-cut 後續唯一 implementation repo。source write、test、
   verify、commit、PR create、finalize 都必須用 `WORKTREE_PATH` 作為 repo / cwd。
6. framework-owned source path（如 `scripts/**`、`.claude/skills/**`、
   `.claude/rules/**`、`.claude/instructions/**`、`CLAUDE.md`、`AGENTS.md`、
   `.codex/**`、`.agents/**`）不得在 main checkout 施工。main checkout 若有
   framework-owned dirty source，engineering 必須 fail-stop 或要求清理 / stash；dirty
   內容只能作為參考，實作 diff 必須在 `WORKTREE_PATH` 產生。
7. product repo 或 ignored runtime artifact 的 main checkout dirty state 可存在，但不得為了
   建立 task worktree 對 main checkout 執行 `git stash`、`git reset`、`git restore`、
   `git checkout` 或等價 destructive workaround。

First-cut 不再需要獨立 pre-development rebase；branch setup 已從 resolved base tip 切出。

## TDD And Implementation

順序：

1. 讀 company handbook index + linked docs，再讀 repo handbook index + linked docs。
2. 讀 project `CLAUDE.md`（若存在）。
3. 讀 `tdd-smart-judgment.md`；依檔案性質判斷是否 TDD。
4. 安裝依賴：

   ```bash
   bash {polaris_root}/scripts/env/install-project-deps.sh \
     --task-md {task_md_path} \
     --cwd "$WORKTREE_PATH"
   ```

5. 用 `scripts/parse-task-md.sh` 取得 `test_command`、`verify_command`、Test
   Environment。不可自行推導。
6. runtime level 用 `scripts/start-test-env.sh`；不要手拼 docker / dev server。
7. canonical `polaris-config/{project}/generated-scripts/ci-local.sh` 存在時必跑：

   ```bash
   bash "${POLARIS_ROOT}/scripts/ci-local-run.sh" --repo "$WORKTREE_PATH"
   ```

Migration blocker 不可被當作 skip reason。

DP-backed framework work 若需要讀 task.md、refinement、skills reference、handbook 或
polaris-config，這些 workspace-owned artifacts 必須用主 checkout canonical absolute path
讀取；不得把 `docs-manager/src/content/docs/specs/**`、`.claude/skills/**` 或
`polaris-config/**` copy / rsync / mirror 到 task worktree。

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
- product delivery 若產生 framework-owned diff，先跑
  `scripts/framework-scope-escalation-gate.sh --mode product`；命中
  `POLARIS_FRAMEWORK_SCOPE_ESCALATION_REQUIRED` 時，移出產品 PR，建立 DP-backed framework
  workstream seed/handoff 或更新既有 DP-backed framework source。
- VR if triggered。
- base freshness。
- commit。
- PR via `scripts/polaris-pr-create.sh`，不可 draft。
- auto-pass ownership consumption 只接受 `polaris-pr-create.sh` provenance、non-draft PR、
  completion marker PASS、base freshness current；裸 `gh pr create`、generic publisher、
  plugin publisher 或 draft PR 不可在後段補認成 valid delivery。
- JIRA transition / comment。
- completion gate。
- worktree cleanup。

最後跑：

```bash
bash "${POLARIS_ROOT}/scripts/finalize-engineering-delivery.sh" \
  --repo "$WORKTREE_PATH" \
  --ticket "{ticket_key}" \
  --workspace "{workspace_root}"
```

這支 helper 負責 task move-first closeout、parent closeout NOOP / closure、implementation
worktree cleanup。不得手動掃 folder 改 parent lifecycle。
