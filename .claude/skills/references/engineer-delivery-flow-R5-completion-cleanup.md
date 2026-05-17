## Step 8.5 — Completion Gate（pre-report hard gate）

> 目的不是取代 Step 7a，而是封住另一個出口：agent 在還沒碰到 git / PR gate 前，就先口頭宣稱「完成」。

Developer mode 通常由 Step 8a 的 `finalize-engineering-delivery.sh` 代跑本 gate。若只需要診斷 gate 本身，可直接執行：

```bash
bash "${POLARIS_ROOT}/scripts/check-delivery-completion.sh" --repo "$(git rev-parse --show-toplevel)" --ticket "<TICKET_OR_DP_TASK_ID>"
```

Developer completion gate 會讀 task.md `deliverable.pr_url`，用 `gh pr view` 取得 remote PR `state`、`isDraft`、`body`、head metadata，並重用 `gate-pr-body-template.sh` 與 `gate-pr-language.sh` 檢查 remote PR body。Gate 也會要求 task folder 內存在 matching `verify-report.md`，且報告含同一個 ticket 與 `deliverable.head_sha`。接著呼叫 `publish-delivery-evidence.sh --mode check`，若本地有 VR artifact 或 Playwright behavior evidence，必須在 PR comments 找到 matching `polaris-evidence-publication:v1` marker、`polaris-verify-report:v1` marker，或 Jira evidence marker；Playwright behavior evidence 必須含 video reference。Completion gate 也會讀 GitHub reviewThreads，若有 unresolved 且 non-outdated 的 active root thread，必須存在 head-bound review-thread disposition manifest（`fixed` / `reply_only` / `not_actionable` / `deferred_with_reason`），否則 fail loud。GitHub API / `gh` 讀取失敗、PR 為 draft、PR 非 open、remote head 與 deliverable head 不一致、task verify report 缺失或 stale、body 不符合 repo template、body 違反 workspace language policy、active review threads 未 disposition、或 evidence 仍只停在 local ignored path，都必須 fail loud；不得跳過並口頭回報完成。若 CLI/API 無法上傳二進位附檔，使用 `collect-evidence-upload-bundle.sh --target pr` 產生的 bundle 作為人工拖檔來源；bundle 本身不是 remote publication marker。

Local Extension mode：

```bash
bash "${POLARIS_ROOT}/scripts/gates/gate-ci-local.sh" --repo "$(git rev-parse --show-toplevel)"
bash "${POLARIS_ROOT}/scripts/gates/gate-evidence.sh" --repo "$(git rev-parse --show-toplevel)" --ticket "<DP_TASK_ID>"
bash "${POLARIS_ROOT}/scripts/framework-release-closeout.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --template-repo "<template repo path>" \
  --task-md "<path/to/task.md>" \
  --verify-evidence "<Layer B durable evidence path>" \
  --ci-local-evidence "<Layer A evidence path or N/A when no ci-local is declared>" \
  --vr-evidence "<Layer C evidence path or N/A>" \
  --workspace-commit "<workspace release commit>" \
  --template-commit "<template release commit>" \
  --version-tag "<version tag or N/A>" \
  --release-url "<release URL or N/A>"
```

`framework-release-closeout.sh` 內部必須在寫入 `extension_deliverable` 後通過
`check-release-eligible.sh`，並在 task move-first closeout、cleanup、parent closeout後通過
`check-release-completed.sh`。helper 本身不再是唯一 release authority。

Generic local-extension fallback（僅限 local policy 未宣告 closeout helper）：

```bash
bash "${POLARIS_ROOT}/scripts/write-extension-deliverable.sh" "<path/to/task.md>" \
  --extension-id "<local extension id>" \
  --task-head-sha "<validated task head sha>" \
  --workspace-commit "<workspace release commit>" \
  --template-commit "<template release commit>" \
  --version-tag "<version tag or N/A>" \
  --release-url "<release URL or N/A>" \
  --ci-local-evidence "<Layer A evidence path or N/A when no ci-local is declared>" \
  --verify-evidence "<Layer B evidence path>" \
  --vr-evidence "<Layer C evidence path or N/A>"
bash "${POLARIS_ROOT}/scripts/check-local-extension-completion.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --task-md "<path/to/task.md>" \
  --task-id "<DP_TASK_ID>" \
  --extension-id "<local extension id>"
```

不得呼叫不符合 local policy 的 completion gate 後忽略其 deliverable failure。Post-PR release endpoint 必須保留真實 workspace PR deliverable；PR-bypass endpoint 不得偽造 PR deliverable。Local Extension completion gate 的 authority 是 `extension_deliverable` metadata、Layer B evidence 對應 `task_head_sha`、Layer A evidence（若 repo 宣告 ci-local）、以及 local policy release commit freshness。Layer B evidence path 應使用 `run-verify-command.sh` 寫入的 `.polaris/evidence/verify/` durable mirror；`/tmp/polaris-verified-...json` 只作為 hook cache。對 `framework-release`，這些 signal 必須由 `framework-release-closeout.sh` 產生，並由 `check-release-eligible.sh` / `check-release-completed.sh` 驗證。

### Script contract（Developer / Admin / Local Extension）

- Layer A：呼叫 `scripts/gates/gate-ci-local.sh --repo <path>`
  - workspace-owned canonical `polaris-config/{project}/generated-scripts/ci-local.sh` 不存在 → `NO_CI_LOCAL_CONFIGURED`
  - canonical script 存在 → required，cache miss 會同步實跑 `ci-local.sh`
  - repo-local `.claude/scripts/ci-local.sh` 存在但 canonical missing → migration blocker
- Layer B（Developer only）：呼叫 `scripts/gates/gate-evidence.sh --repo <path> --ticket <TICKET_OR_DP_TASK_ID>`
  - Layer B / Layer C pass semantics 由 `check-verification-passed.sh` 決定；missing / malformed / stale / non-pass outcome → block
- exit 0 = 可以回報完成
- exit 2 = **HALT**，不得回報「完成 / 可交付 / 已驗完」

Completion gate 不查詢或等待遠端 repo CI。只要本地 LLM gates 與 mechanical evidence gates 已通過，queued / pending / running 的遠端 CI 不阻擋完成回報。Developer lane 的 user-facing complete 還必須通過 Step 8a finalize helper，確保 task lifecycle 也已 move-first closeout。Local Extension lane 另需 `check-local-extension-completion.sh` PASS，不能只靠本地 evidence gates 回報完成。

### Why this exists

Step 7a 保證「不能開 PR」；Step 8.5 保證「不能嘴上結案」。兩者一起才算完整的 no-bypass delivery contract。

---

## Step 8.6 — Worktree Cleanup

PR 建立 / 既有 PR branch push 完成，或 local extension final verification 完成後，task deliverable / extension metadata 已回寫、Developer finalize helper PASS（或 Local Extension closeout helper PASS），才清掉本次 implementation worktree。Developer lane 的 cleanup 已內建在 `finalize-engineering-delivery.sh`：task move 到 `tasks/pr-release/` 且 status 變成 `IMPLEMENTED` 後，finalize helper 會用 `engineering-clean-worktree.sh` guard 後清理。不要手動猜路徑或直接 `rm -rf`。若 local policy 使用 `framework-release-closeout.sh`，該 helper 已負責呼叫 `engineering-clean-worktree.sh`，並在 parent DP terminal 後 archive canonical DP container；不要再手動重跑 cleanup/archive 除非前次 helper 明確失敗並要求人工恢復。

`finalize-engineering-delivery.sh` 清除 worktree 前必須切回 workspace root；後續 parent closeout 不得依賴即將被刪除的 implementation worktree cwd。terminal release gate 也不得再用已刪除的 implementation worktree 當 `--repo`，必須先解析 stable repo root。

```bash
bash "${POLARIS_ROOT}/scripts/engineering-clean-worktree.sh" \
  --task-md "<path/to/task.md>" \
  --repo "$(git rev-parse --show-toplevel)"
```

- PR 後不保留常駐 worktree；若後續 review / CI 需要 revision，從當下 PR branch/head 重新建立 fresh worktree
- worktree 不可因「剛剛用過」、「還很乾淨」、「下一輪可能還要修」等理由復用；任務結束後相關 worktree 必須清空
- helper 只會移除 `.worktrees/` 底下、Git 已登記、狀態乾淨、且 `deliverable.head_sha` 等於 worktree `HEAD` 的 implementation worktree
- 若目前是在 main checkout 直接修 revision，helper 會找不到 implementation worktree 並輸出 `nothing to clean`；這是合法 no-op
- 可刪除已不需要的 local temp branch；不要刪 remote PR branch
- 若 worktree 有 uncommitted changes，先停下來分類（應提交 / 應搬到 artifact / stale experiment），不得 silent discard
- helper 會確保 main checkout 的 `.git/info/exclude` 含 `.worktrees/`，避免 worktree 目錄長期污染 `git status`

驗證型 worktree（只用於 verify / reproduce / compare / inspect）不等 PR flow；驗證結果、log、evidence 捕捉完就立即 `git worktree remove`。

---

## Halting Conditions

流程在任何步驟失敗皆停止，不靜默繼續：

| 步驟 | 失敗處置 |
|------|---------|
| Step 1 Simplify 3 輪未穩定 | 詢問使用者手動介入 |
| Step 1.3 Self-Review 3 輪仍有 blocking | 詢問使用者手動處理 |
| Step 1.5 Scope exceeded | **HALT** — 回 `/breakdown {EPIC}` 更新 Allowed Files 或拆新子 task |
| Step 2 前置 Rebase conflict | **halt** — conflict resolution 回 Phase 3 domain（LLM semantic work），解完後 resume Step 2 前置 |
| Step 2 CI Mirror FAIL | 修 → re-run；修不了停止回報 |
| Step 3 `run-verify-command.sh` FAIL | **halt delivery flow** — 回報 output，debug root cause |
| Step 3.5 VR FAIL（unexpected diff） | 停止。列 failing pages，使用者決定 |
| Step 5 Base stale | 🔄 Loop back to Step 2 前置 Rebase（non-blocking loop，自動 re-execute） |
| Step 7a Evidence AND gate missing/stale | **halt** — 不開 PR，回頭檢查遺漏的 evidence |
| Step 7d PR create hook 擋 | 停止。回頭檢查 evidence |
| Step 7d deliverable 回寫失敗 | **HALT** — inconsistent state，不繼續 Step 8 |
| Step 8a Finalize Delivery FAIL | **HALT** — 不得回報完成；若 completion gate fail，回頭補齊 Layer A/B evidence；若 lifecycle mark fail，修 task.md/pr-release invariant |

---

## Evidence — AND Gate Model（DP-032 D12/D15/D16/D18）

三個 evidence dimension，各由專屬 script 產出：

| Dimension | Script | Evidence path | Writer |
|-----------|--------|--------------|--------|
| A — CI | `ci-local.sh`（repo-level） | `/tmp/polaris-ci-local-{branch}-{head_sha}.json` | `ci-local.sh` |
| B — Verify | `run-verify-command.sh` | `/tmp/polaris-verified-{ticket}-{head_sha}.json` | `run-verify-command.sh` |
| C — VR | `run-visual-snapshot.sh` | `/tmp/polaris-vr-{ticket}-{head_sha}.json` | `run-visual-snapshot.sh` |

### Core Invariants

1. Evidence file **只能由指定 scripts 寫入**；LLM 對 evidence paths 的 Write/Edit 會被 `no-direct-evidence-write.sh` PreToolUse hook 擋下（D16）
2. evidence 內的 `head_sha` 必須匹配目前 `git rev-parse --short HEAD`；stale evidence 會自動被拒絕
3. `writer` field 必須在 known-writer whitelist 內（`verification-evidence-gate.sh` 檢查，D16 cross-LLM）
4. PR creation、local extension handoff、post-PR release handoff 前，Layer A + B（+ triggered Layer C）必須全部存在且 PASS；這是 **AND gate，不是 OR**
5. **evidence 沒有 bypass env var**（D16 NO bypass stance；`POLARIS_SKIP_CI_LOCAL=1` 是唯一 emergency escape，且只涵蓋 Layer A）

### Hook Enforcement（DP-032 Wave δ — 跨 LLM）

| 機制 | 觸發時機 | 檢查內容 | 適用範圍 |
|------|---------|--------|---------|
| `gate-ci-local.sh` git pre-commit | `git commit` | Layer A evidence | 四通（Claude / Codex / Copilot / 人類） |
| `gate-ci-local.sh` git pre-push | `git push` | Layer A evidence（push mode） | 四通 |
| `gate-revision-rebase.sh` git pre-push | `git push` on an existing PR branch | Revision R0 evidence for current HEAD | 四通 |
| `gate-evidence.sh` git pre-push | `git push` | delegated shared `verification_passed` gate（Layer B + triggered Layer C）+ Layer D if declared | 四通 |
| `gate-changeset.sh` git pre-push | `git push` | Developer ticket-bound changeset 缺漏檢查 | 四通 |
| `gate-base-check.sh` in `polaris-pr-create.sh` | PR 建立 | base branch = resolve 結果 | 四通 |
| `polaris-pr-create.sh` wrapper | PR 建立 | 依序跑 base-check → evidence → ci-local | 四通 |
| `check-delivery-completion.sh` | user-facing completion report | Layer A always if `ci-local.sh` exists; Layer B for Developer / Local Extension when helper exists; Developer deliverable PR must be remote PR ready (`state=OPEN`, `isDraft=false`) and body-template compliant | 四通 |
| `no-direct-evidence-write.sh` PostToolUse | Write/Edit on evidence paths | **Blocks** — LLM 不可偽造 evidence | Claude Code only（advisory） |

> **Legacy hooks removed（DP-032 Wave δ）**：`ci-local-gate.sh`、`verification-evidence-gate.sh`、`pr-base-gate.sh`、`pr-create-guard.sh` PreToolUse hooks 已刪除，功能全部移至 portable gate scripts + git hooks。

---

## Role-Specific Notes

### Developer 呼叫端責任（engineering SKILL.md）

呼叫前：
- 已通過 Task Existence Gate（task.md 存在）
- 已 checkout 正確 branch（或現在建立）
- 已完成 handbook gate，直接讀取 workspace-owned `{company}/polaris-config/`；不部署或修改 repo-owned AI 設定

呼叫時 context：
- Role: `developer`
- task.md 完整內容（或路徑）
- JIRA ticket key
- Base branch

## Iteration & Halting Metrics

Risk signal（若多次觸發，呼叫端應停下回報使用者而非繼續）：

- Step 1-3 任一 step 重跑 ≥ 3 次
- evidence file 重寫 ≥ 2 次
- 同一檔案連續被修 ≥ 4 次
- 總 tool call 數超過 40 但仍未進 Step 7

符合 ≥ 2 項 → 停止，回報當前狀態給使用者判斷（對應 `sub-agent-delegation.md § Self-Regulation Scoring`）。

---

## 和其他 reference 的關係

- [behavioral-verification.md](behavioral-verification.md) — Step 3 verify command 的延伸工具（效能 A/B Worktree、goal-backward wiring 等）
- [pipeline-handoff.md](pipeline-handoff.md) — 角色邊界與 task.md schema（Developer 上游）
- [repo-handbook.md](repo-handbook.md) — handbook 結構
- [cascade-rebase.md](cascade-rebase.md) — Step 2 前置 Rebase 的 cascade 邏輯 + depends_on chain 處理
- [sub-agent-roles.md](sub-agent-roles.md) — Step 1.3 Reviewer sub-agent 規格（Phase 3 exit gate）
- [pr-body-builder.md](pr-body-builder.md) — Step 7 PR template detection + body 組裝
- [pr-input-resolver.md](pr-input-resolver.md) — PR URL/number/branch 解析
- [commit-convention-default.md](commit-convention-default.md) — Step 6a commit message fallback chain

## 來源

本 reference 是 `engineering` 的共用 delivery backbone。DP-032 Wave γ-δ 重構為 Two-Segment Architecture：LLM 實作段（Phase 3）+ 機械自驗段（Step 1.5+），引入 script-mediated evidence AND gate model、scope gate、前置 rebase、base freshness detection、VR skill sunset。DP-040 後，framework repo 也透過 DP-backed `engineering` 進入本流程。
