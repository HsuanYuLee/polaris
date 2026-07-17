# Engineer Delivery Flow Index

這份薄索引是 `engineering` delivery 的穩定入口。DP-188 將原本單一大型流程拆成分段 reference，同時保留相同 backbone 與 gate 順序。

## Phase References

| Phase | Reference | Scope |
|-------|-----------|-------|
| Context | `engineer-delivery-flow-index-context.md` | delivery contract、role matrix、design principles |
| R0 | `engineer-delivery-flow-R0-preflight.md` | simplify、self-review、scope gate、rebase |
| R1 | `engineer-delivery-flow-R1-ci-verify.md` | local CI mirror 與 behavioral verify |
| R2 | `engineer-delivery-flow-R2-flow-vr.md` | flow gap audit 與 visual regression |
| R3 | `engineer-delivery-flow-R3-base-commit.md` | base freshness、commit、changeset |
| R4 | `engineer-delivery-flow-R4-pr-jira.md` | PR create / local extension handoff / JIRA transition |
| R5 | `engineer-delivery-flow-R5-completion-cleanup.md` | completion gate、cleanup、halting conditions、evidence model |

## Consumer Contract

- `engineering-first-cut-flow.md` 先讀此索引，再只載入目前 role / gate 需要的 phase。
- Developer 與 Local Extension role 共用相同 phase 順序；local extension policy 可以增加 tail checks，但不能移除 evidence gates。
- 修改 delivery semantics 時，必須在同一張 task 內同步更新相關 phase reference 與 deterministic scripts。

## Backbone

完整順序維持如下：

```text
scope -> rebase -> ci-local -> verify -> flow-gap -> VR if triggered -> base freshness -> commit -> PR/local extension -> completion gate -> cleanup
```

Developer completion gate 也會消費 `engineering-branch-setup.sh` 在 fresh worktree 建立時寫入的 planner-owned baseline snapshot。若 snapshot 缺失，或 `Verify Command`、`depends_on`、`Base branch`、`Allowed Files` 任一欄位與 snapshot 不一致，屬於 scope-escalation blocker；engineering 不得就地修改 task.md，或建立 post-hoc snapshot evidence 來通過 closeout。

所有 engineering work 的交付 scope authority 都是 resolved task.md 的
`Allowed Files`。`refinement.json.changed_files` 只供 refinement／breakdown planning preview，
不得作為 live engineering delivery gate。穩定 adapter 仍可用下列方式呼叫 canonical
`check-scope.sh`：

```bash
bash scripts/gates/gate-changed-files-scope.sh \
  --repo <task-worktree> \
  --task-md <resolved-task.md> \
  --base <pr-base-or-task-base>
```

若 gate fail，engineering 不得自行擴大 scope；應 route back to refinement 更新
AC／architecture，或 route back to breakdown 更新 task.md `Allowed Files`；也可縮小
implementation diff。不得修改 `refinement.json.changed_files` 來放行交付。

## Revision Mode — Explicit --pr

Revision mode（fix review comments、push CI fix、補 verify evidence）操作既有 PR 時，
**必須**對下列共用 PR state script 顯式傳 `--pr <number>`：

- `scripts/resolve-pr-work-source.sh --pr <number>`
- `scripts/pr-state-snapshot.sh --pr <number>`
- `scripts/pr-action-classifier.sh --pr <number>`

不傳 `--pr` 時這三支會走 branch-fallback：以 current git branch 推 PR。主 checkout 可能
已切到另一張 task branch，resolver 會挑到錯 PR（例：PR #1234 對應 PROJ-AAAA，但主
checkout 在 `task/PROJ-BBBB-...` 上，resolver 回 PR 1235 或 `pr_number: null`），導致
completion gate evidence、JIRA write-back 與 closeout 全部 bind 錯 PR。

`engineering-revision-worktree-setup.sh` 已要求 `--pr`；同樣 discipline 套用到上述三支
resolver/snapshot/classifier triad。

## Gate Invocation — Portable Paths

Portable gate helper 不是全部在同一個目錄，且 argument shape 不一致：

```bash
# ✅ Correct
bash scripts/gates/gate-ci-local.sh --repo /path/to/repo
bash scripts/gates/gate-evidence.sh --repo /path/to/repo --ticket PROJ-NNNN --task-md /path/to/task.md
(
  cd /path/to/repo
  bash /path/to/workspace/scripts/check-base-fresh.sh /path/to/task.md
)
```

```bash
# ❌ Wrong — root-level guesses / passing repo-style args to base-fresh
bash scripts/gate-ci-local.sh --repo ... --task-id ... --head ...
bash scripts/gate-evidence.sh --repo ... --task-id ... --head ...
bash scripts/check-base-fresh.sh --repo ... --task-md ... --pr ...
```

Why：`gate-ci-local.sh` 與 `gate-evidence.sh` 是 `scripts/gates/` 底下的 portable wrapper，
自行 resolve HEAD；`check-base-fresh.sh` 只接 `<task_md>`，依當前 git repo cwd 比對 HEAD/base。

## Verify Evidence Worktree Resolution

`scripts/run-verify-command.sh` 解析 `REPO_PATH` 走以下優先順序（DP-219）：

1. `--repo <path>` override：caller 明示，最高優先。
2. `--worktree <path>` override：caller 明示 worktree，比 PWD-based 偵測穩定。
3. PWD-based 偵測：`git rev-parse --show-toplevel` 從當前 cwd 取得 working tree
   root；只有當 basename 對得上 task.md 解析出的 `REPO_NAME`，或當前 worktree 對應的
   主 checkout basename 對得上 `REPO_NAME` 時才接受。
4. Legacy fallback：從 task.md 所在目錄往上 walk，找 `{ancestor}/{REPO_NAME}/.git`。

效果：在 worktree 內呼叫 `bash scripts/run-verify-command.sh --task-md <path> --ticket <key>`
**不需**手動傳 `--repo`；evidence file 的 `head_sha` 自動 bind 到 worktree HEAD，後續
`pr-create` / completion gate 的 head_sha 比對不再 drift。

註：若需要在另一個 cwd 觸發 worktree-bound verify（例如 sub-agent 用絕對路徑 dispatch），
明示 `--worktree <path>` 比依賴 PWD 偵測更可預期；非 git fixture 或 stale worktree path 會
exit 1 + clear error，不會 silent 蓋掉。

## Declared Verification Orchestration

需要一次執行 task 宣告的 verification layers 時，使用單一 callable：

```bash
bash scripts/run-verify-all.sh \
  --task-md <resolved-task.md> \
  --repo <task-worktree> \
  --ticket <delivery-ticket-key>
```

它只做 orchestration：primary layer 委派 `run-verify-command.sh`；有
`verification.visual_regression` 才委派 `run-visual-snapshot.sh --mode compare`；只有
`behavior_contract.applies=true` 才委派 `run-behavior-contract.sh --mode compare`。最後由
既有 `gate-evidence.sh` 驗證跨層 marker 語意。未宣告的 VR 與 `applies=false` behavior
直接 skip，不產生 marker，也不形成 blocker。task 的 `Verify Command` 不得反向呼叫
`run-verify-all.sh`，避免 orchestrator 遞迴成第二層 runner。

verify／VR durable path 必須透過 `resolve-artifact-location.sh` 取得；該 adapter 只 delegate
`scripts/lib/verification-evidence.sh`，不自行維護 path template。marker location、ticket、
current HEAD 與 PASS outcome 則由 `validate-artifact-location.sh` 驗證。DP-backed 與
JIRA-backed ticket 使用同一組參數與 path authority，沒有 source-type fast path。

## DP-201 Proof Markers

engineering 擁有 auto-pass 需要讀取的 delivery state durable proof markers：

- `pr_freshness`：`deliverable.head_sha` 必須對齊 `gh pr view --json headRefOid`。
- `blocked_conflict`：shared PR state 或 rebase classification 為 `blocked_conflict` 時的 durable marker。
- `unsupported_mutation`：requested PR mutation 超出 supported lane 時的 durable marker。
- `ci_local`：auto-pass 需要 filesystem proof 時，落在 `.polaris/evidence/ci-local/` 的 durable ci-local mirror。
- `completion_gate`：落在 `.polaris/evidence/completion-gate/` 的 completion-gate roll-up。

Marker JSON schema 與 producer mapping 以 `auto-pass-proof-of-work.md` 與
`scripts/lib/evidence-producers.json` 為準。`/tmp` evidence 只能當 cache。
