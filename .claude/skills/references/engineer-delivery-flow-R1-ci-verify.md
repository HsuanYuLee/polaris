## Step 2 — Local CI Mirror

執行 `bash "${POLARIS_ROOT}/scripts/ci-local-run.sh"`（wrapper 自動解 main checkout canonical + 用 `--repo $PWD` 跑當前 worktree／checkout）。

此 script 由 `scripts/ci-local-generate.sh` 從 repo 的 CI config（Woodpecker / GitHub Actions / GitLab CI / husky / `.pre-commit-config.yaml` / `package.json` scripts）推導產出，序列化執行 install / lint / typecheck / test / coverage 類別的 commands，並嵌入 codecov patch coverage compute。每個 repo 一份 self-contained script，框架本體不再做 CI re-discovery。

**CI declaration read-only boundary**：Step 2 只消費 repo CI declarations，不修改它們。若 `ci-local` 與遠端 CI 的差異指向 Woodpecker / GitHub Actions / GitLab CI / Codecov / husky / pre-commit / package script 設定，Developer lane 必須停止並記錄 framework 或 repo-owner 決策需求；不得在產品 PR 內改 CI config 來讓 local/remote gate 通過。

**Repo-level CI false-positive override**：若遠端 CI 已證實有 repo-level false-positive / fail-open 行為（例如 CI typecheck OOM 但 repo script 誤判 PASS），不得要求一般 task 修 unrelated full-package baseline debt。把決策記在 workspace-owned `{company}/polaris-config/{project}/ci-local-overrides.json`，由 `ci-local-generate.sh` 讀取並在 generated `ci-local.sh` / evidence 中以 `SKIP` + `repo_override:<id>:<reason>` 顯示。這不是 task-level bypass；每筆 override 必須 match 具體 `source_file` / `job` / `category` / `command`，並保留 repo-owner 後續修 CI 的 reason。產品 repo CI 宣告仍為 read-only。

**Existence invariant**：`{company}/polaris-config/{project}/generated-scripts/ci-local.sh` 存在 → 此 repo 已宣告 Local CI Mirror，所有 worktree 共用此 workspace-owned canonical script。repo-local `.claude/scripts/ci-local.sh` 是 legacy migration error，不可作為完成依據。是否需要跑由 canonical 檔案存在決定，不由 git status 類型決定。

**Re-test-after-fix 鐵律**：若本 step 發現問題並修改 code，必須**重跑一次** `ci-local.sh`。上一輪修改前的結果無效。

> **Dimension model (DP-029 D6 v2 / D11；DP-032 D12-c)**：engineering 的品質要求分兩層：
> - **Dimension A — Framework Baseline（一律執行）**：TDD discipline（red-green-refactor）+ 功能驗證（`Verify Command` Step 3d）+ VR（conditional, Step 3.5）
> - **Dimension B — Repo CI-Equivalent（repo 有 `ci-local.sh` 就跑、沒有就跳）**：`ci-local.sh` 模擬 repo CI 的 patch gate / lint / typecheck / 其他 workflow jobs。repo 有配就跑，沒配就不跑 — **patch coverage 歸 repo 責任，框架不主動追加**
>
> Commit / push / `gh pr create` 前必須確認 Dimension B 全綠。Dimension A 的 TDD discipline 由 `tdd-bypass-no-assertion-weakening` canary 把關（見 `mechanism-registry.md`）。
>
> **Deterministic script TDD trigger**：Polaris-owned deterministic script (`scripts/*.sh`, `scripts/*.py`, `scripts/*.mjs` or enrolled selftest) 若會改變 behavior、dependency usage、selected suite、bootstrap、doctor、release preflight 或 lifecycle gate，必須先在 task.md 定義 script test contract，並優先補 failing selftest 再 implementation。text-only、comment-only、typo、help output 或 changelog-only 這類 trivial change 不強迫新增 failing selftest，除非該文字是 machine-read contract 或被其他 script parse。
>
> **Remote CI wait policy**：`ci-local.sh` 是 repo CI-equivalent 的本地 authority。push / PR 後，GitHub / Woodpecker / GitLab 等遠端 CI 若仍是 queued / pending / running，不阻擋 Step 8.5 或 user-facing complete。遠端 check 若已完成且明確 FAIL，才進 revision mode 作為 CI failure signal；不因等待遠端 CI 太久而延後 complete。

`ci-local-run.sh` 會先嘗試用目前 branch 對應的 `task.md` 解析 resolved base，再把 `--base-branch` 傳給 generated `ci-local.sh`。這讓 stacked PR 的本地 Codecov patch diff 對齊實際 PR base，而不是誤用 branch upstream 或 `develop`。

**執行**：

```bash
bash "${POLARIS_ROOT}/scripts/ci-local-run.sh"
```

- exit 0 → Dimension B PASS，進 Step 3
- exit 1 → Dimension B FAIL，**回到實作階段修 root cause**，禁止放寬 assertion / `.skip()` / `as any` 繞過（canary: `tdd-bypass-no-assertion-weakening`）；修完回 Step 2 開頭重跑
- exit 1 + evidence `status: BLOCKED_ENV` → Dimension B 仍然 **blocking**，但不是 implementation FAIL。`ci-local-env-blocker.md` 是 status schema、reason enum、secret scrub 與 retry/escalation contract authority；`ci-local-run.sh` 會用同一 repo/context 自動重跑一次。若仍 blocked，輸出 runtime-neutral `RETRY_WITH_ESCALATION` payload（原始 command、reason、host、context hash、manual remediation）。真正 elevated / unsandboxed execution 由當前 runtime adapter 或人類 shell 處理，framework core 不自行升權，也不把 `BLOCKED_ENV` 當 degraded pass。

**Evidence file（自動寫入）**：`ci-local.sh` 執行完必寫 `/tmp/polaris-ci-local-{branch}-{head_sha}-{context_hash}.json`（status / branch / head_sha / CI context / timestamp / commands / summary）。`context_hash` 來自 event/base/source/ref，避免同一 head 在不同 PR base 下誤用 PASS cache。`gate-ci-local.sh` 在 git pre-commit / pre-push 及 `polaris-pr-create.sh` 前會呼叫 `ci-local-run.sh`；cache hit 由 generated `ci-local.sh` 自行處理，cache miss 或非 PASS 則同步實跑，PASS 放行 / FAIL 擋。跳過本 step ≠ 漏網 — gate 會在第一個 git 動作補位執行。

**沒有 repo CI 配置（例如框架 repo / prototype）**：`ci-local-generate.sh` 偵測不到任何可推導的 commands → 產出 NO_CHECKS_CONFIGURED 純路徑 `ci-local.sh`，直接 PASS（仍寫 evidence file status: PASS）。這是 design — 框架尊重 repo maintainer 的 CI 決策，不主動強加 coverage baseline。

**Empty-coverage 安全網（`ci-local.sh` 內建 invariant）**：若所有 patch gate 結果為 SKIP（`no_instrumented_patch_lines`）、diff 中有匹配 gate path 的檔案、且沒有任何匹配檔案出現在 lcov coverage data，`ci-local.sh` 判定 FAIL（tests 很可能沒跑出 coverage data）。若 lcov 已包含該檔案但本次 patch lines 不可 instrument，維持 SKIP。defense-in-depth — 攔截 test runner 靜默跳過 / coverage 生成失敗等未預見原因，同時避免把有 coverage data 的 type-only / non-instrumented patch 誤判成 coverage 沒跑。

**Bypass**：`POLARIS_SKIP_CI_LOCAL=1` — emergency escape only，不應日常使用。**沒有** `wip:` commit-msg skip / **沒有** main-develop branch skip / **沒有** deprecation shim（D12-c 一次到位的 breaking change）。

**歷史**：TASK-3847 事件（useFetch key 改動沒補測試、本地 quality PASS 但 CI `codecov/patch/main-core` FAIL）促成 DP-029 Phase B 的 patch gate 精確模擬。早期版本掛了 framework-level `coverage-gate.sh`（D6 v1），D6 v2 (2026-04-24) 判定「repo 有配就由 Dimension B 接、沒配不追加」更乾淨，coverage-gate 下架。D12-c (v3.58.0) 進一步把 `ci-contract-run.sh` / `quality-gate.sh` / `pre-commit-quality.sh` 整批下架，改由 `ci-local-generate.sh` 為每個 repo 生成 self-contained `ci-local.sh`，框架本體只保留 `ci-local-gate.sh` PreToolUse hook 做 evidence 把關。

---

## Step 3 — Behavioral Verify（`run-verify-command.sh`）

### Developer mode

使用 `scripts/run-verify-command.sh`（D15）：

```bash
bash "${POLARIS_ROOT}/scripts/run-verify-command.sh" "<path/to/task.md>"
```

**Script 行為**：

1. 透過 `parse-task-md.sh --field verify_command,level,work_item_id,jira_key,repo` 讀取 task.md。`work_item_id` 是 evidence / branch / local-extension handoff 的 task identity；`jira_key` 只用於 JIRA side effect，無 JIRA 的 DP-backed task 會是空值。Migration 期舊 consumer 可讀 `task_jira_key` compatibility alias，但新流程不得把它當 canonical 欄位。
2. D17 level-based dispatch：
   - `Level=static` → 直接執行 verify command
   - `Level=build` → 先呼叫 `run-test-prep.sh` → 再執行
   - `Level=runtime` → 先呼叫 `start-test-env.sh` orchestrator（D11 L3；透過 `--repo` 指向實際 checkout/worktree；runtime config source 由 DP-035 handbook config reader 決定，缺 handbook config 時才 explicit fallback）→ 再執行
3. 在 `--repo` 解析出的 repo/worktree root 執行 fenced shell verify command；相對路徑不得依賴 agent 呼叫時的 shell cwd。Evidence 記錄 `execution_cwd`
4. Captures stdout/stderr/exit + sha256 hash
5. Best-effort `curl URL → HTTP status` extraction from output
6. 原子寫入 evidence 到 `/tmp/polaris-verified-{ticket}-{head_sha}.json`（writer=`run-verify-command.sh`）
7. exit 0 = command exit 0 AND evidence file written
8. exit ≠ 0 = FAIL → **halt delivery flow**，report output to user

### LLM 行為界線

**LLM must NOT**：
- 直接執行 `curl` 做 behavioral verification（use the script）
- 透過 Write/Edit tool 寫 evidence file（D16 hook blocks；use the script）
- 自行判斷 verify command output 是否 pass（script handles exit code）
- 自行改寫 `## Verify Command` 或改用 ad hoc output path；若 primary verify 因已確認的 repo baseline issue 無法產生 artifact，必須由 task.md 明確提供 `## Verify Fallback Command`，再讓 `run-verify-command.sh` 執行 primary→fallback 並寫入 fallback evidence

**LLM may**：
- 讀 script stdout 理解 failure context
- Debug root cause when script reports FAIL
- 修完 code 後再次 invoke `run-verify-command.sh`

### Explicit Verify Fallback

`## Verify Fallback Command` 是唯一允許的 behavioral verify fallback。使用條件：

1. task.md primary `## Verify Command` 保持不變，且 `run-verify-command.sh` 必須先執行 primary。
2. fallback command 必須寫在 task.md 的 `## Verify Fallback Command` fenced block；不得由 LLM 口頭替換。
3. fallback 只在 primary exit 非 0 時執行。
4. evidence 會記錄 `verification_mode=fallback`、`primary.exit_code`、`fallback.exit_code`、primary/fallback stdout/stderr hash。
5. final / handoff 必須明說 primary failure disposition 與 fallback reason；如果 fallback reason 是 repo baseline issue，應同步記錄到 repo handbook 或 task revision evidence。

沒有 `## Verify Fallback Command` 時，primary verify fail 仍是 fail-stop。

### No-task request

無 task.md 不進入本 delivery flow；沒有 verify command 時不得建立 PR 或宣稱完成。

---

