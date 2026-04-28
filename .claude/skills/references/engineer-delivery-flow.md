# Engineer Delivery Flow

共用的「工程師交付」執行流程。**受消費者**：
- **`engineering`**（Developer 角色，ticket-driven，產品 repo）
- **`git-pr-workflow`**（Admin 角色，無 ticket，框架/docs 維護）

兩個 skill 都 include 本 reference 作為 execution backbone。唯一分歧在少數 role-specific 步驟（見 § Role Matrix）。

## Delivery Contract

### Preconditions（呼叫端必須提供）

| 項目 | Developer | Admin |
|------|-----------|-------|
| Branch | Task branch 已 checkout（`task/PROJ-NNN-*`）| 非 main 的工作 branch |
| Code | 實作完成、可 commit 的狀態 | 變更完成 |
| task.md | 路徑或完整內容（含 Repo、測試計畫、行為驗證 Layer B）；所有欄位讀取走 `scripts/parse-task-md.sh`（DP-032 D8） | 不需要 |
| JIRA ticket key | 必填 | 不需要 |
| Base branch | 從 task.md 或 JIRA parent 推導 | 當前 branch upstream 或 `origin/main` |
| Role declaration | context 明確說 `role: developer` | context 明確說 `role: admin` |

### Postconditions（本流程保證）

- Code 經過 /simplify + Self-Review（Phase 3 exit gates）
- Scope 在 task.md Allowed Files 範圍內（Step 1.5 gate）
- Local CI mirror PASS — evidence: `/tmp/polaris-ci-local-{branch}-{head_sha}.json`（Layer A）
- Behavioral verify PASS — evidence: `/tmp/polaris-verified-{ticket}-{head_sha}.json`（Layer B，via `run-verify-command.sh`）
- VR PASS（if triggered）— evidence: `/tmp/polaris-vr-{ticket}-{head_sha}.json`（Layer C，via `run-visual-snapshot.sh`）
- **Layer A+B(+C) evidence AND gate**：所有必要 evidence 檔案存在且 `head_sha` 匹配當前 HEAD 才放行 PR
- **Completion gate before user-facing done**：回報完成前必須再檢查一次 Layer A（and Developer Layer B）是否仍對應當前 HEAD，避免在 git 動作前先口頭結案
- **Remote repo CI is non-blocking when still queued / pending / running**：本流程以本地 LLM + mechanism evidence 為 completion authority；不等待遠端 CI 排隊或長時間執行完畢
- PR 建立在正確 base branch，body 依 repo template 填充
- JIRA 狀態轉為 CODE REVIEW（Developer only，soft-fail）
- task.md `deliverable.pr_url` + `head_sha` 寫回（Developer only）

### 不做的事

- **不做 AC 業務驗收** — 那是 `verify-AC` 的工作
- **不做 planning / breakdown** — 上游 skill 負責
- **不做 branch 建立** — 呼叫端已 checkout
- **不做 JIRA 讀取決定行為** — JIRA 是 write-only side-effect（D1）
- **不做 handbook/codebase discovery 推論** — config 缺失 → fail loud（D11）

---

## 設計原則

1. **單一源** — execution 紀律在此定義，skill 不重寫。skill SKILL.md 只負責路由、輸入解析、角色標註，具體怎麼做全部讀這份。
2. **框架無關** — 不寫死 Nuxt / Laravel / Rails 的命令。repo 的啟動方式由 **workspace-config + handbook config** 宣告（D11 composable primitives），script 消費宣告，不假設 stack。這也包含 **依賴安裝**：worktree / fresh checkout 在跑任何 test / build / dev-server 前，先透過 `scripts/env/install-project-deps.sh` 讀 `projects[].dev_environment.install_command`；未宣告時才由 script 根據 lockfile / manifest 決定（`pnpm-lock.yaml` → `pnpm install --frozen-lockfile`、`poetry.lock` → `poetry install --sync` 等），避免把「先裝套件」留給 LLM 自行猜測。
3. **task.md authoritative（D1）** — task.md 是 engineering 內部的唯一 state container。Verification URLs, allowed files, verify command, deliverable 全在 task.md。Engineering 對 JIRA 是 write-only（side-effect display）。
4. **Positive-evidence + fail-loud（D11/D12）** — script exit 0 必須代表「實際做了且通過」；config 缺失 → fail loud，不 fallback 推論。
5. **Evidence 只由 script 產出（D15/D16）** — LLM 不直接寫 evidence file（hook 物理擋 Write/Edit on `/tmp/polaris-verified-*` / `/tmp/polaris-ci-local-*`）；evidence `writer` 欄位 + whitelist gate 提供 cross-LLM 保護。
6. **終態是 evidence AND gate** — Layer A（`ci-local.sh`）+ Layer B（`run-verify-command.sh`）+ Layer C（`run-visual-snapshot.sh`, conditional）三檔 evidence 全部 `head_sha` 匹配當前 HEAD 才放行 PR。

## Two-Segment Architecture（D21）

```
┌─ LLM 實作段（可迭代，fail-cheap）───────┐  ┌─ 機械自驗段（線性，fail-stop）──────────────────┐
│ Phase 3: TDD → /simplify → Self-Review │  │ Step 1.5 Scope → 2 Rebase+Quality+CI          │
│          (exit: 三者全綠)              │  │   → 3 Verify → 3.5 VR → 5 Base Detect         │
│                                        │  │   → 6 Commit → 7 PR → 8 JIRA                  │
└────────────────────────────────────────┘  └──────────────────────────────────────────────┘
```

**Step 完整序列**：Step 1 Simplify → Step 1.3 Self-Review → Step 1.5 Scope Gate → Step 2 前置 Rebase → Step 2 Local CI Mirror → Step 3 Verify → Step 3.5 VR → Step 5 Base Freshness → Step 6 Commit+Changeset → Step 7 PR → Step 8 JIRA → Step 8a IMPLEMENTED → Step 8.5 Completion Gate

## Role Matrix

| 步驟 | Developer（engineering） | Admin（git-pr-workflow） |
|------|---------------------|------------------------|
| Input | task.md（含 Repo、測試計畫、行為驗證）；active `tasks/` 找不到時 fallback `tasks/pr-release/`（DP-033 D8）| 無 — 直接讀當前 diff |
| Step 1 Simplify | ✅ | ✅ |
| **Step 1.3 Self-Review（Phase 3 exit gate，D21）** | ✅ | ✅ |
| **Step 1.5 Scope Gate（`check-scope.sh`，D20）** | ✅ | ⏭️ 無 task.md 則跳過 |
| **Step 2 前置 Rebase（`engineering-rebase.sh`，D6/D19）** | ✅ | ✅ |
| Step 2 Local CI Mirror（`ci-local.sh`，D12） | ✅ | ✅ |
| Step 3 Behavioral Verify（`run-verify-command.sh`，D15） | ✅ | ⏭️ 無 task.md 則跳過 |
| Step 3.5 Visual Regression（`run-visual-snapshot.sh`，conditional，D18） | ✅ 若 task.md VR 觸發 | ⏭️ 無 task.md 則跳過 |
| ~~Step 4~~（已搬至 Step 1.3 — Phase 3 exit gate，編號留空避免下游 reference 斷裂） | — | — |
| Step 5 Base Freshness Detection（`check-base-fresh.sh`，D19） | ✅ | ✅ |
| Step 6 Commit + Changeset | ✅ | ✅ |
| Step 7 PR Create（含 7a Evidence AND Gate） | ✅ | ✅ |
| Step 8 JIRA Transition → CODE REVIEW | ✅ | ⏭️ 跳過（無 JIRA ticket） |
| Step 8a Mark IMPLEMENTED | ✅ | ⏭️ 跳過 |
| **Step 8.5 Completion Gate（`check-delivery-completion.sh`）** | ✅ | ✅（`--admin`） |
| Evidence file 鍵 | `/tmp/polaris-verified-{TICKET}-{head_sha}.json` | `/tmp/polaris-verified-{branch-slug}-{head_sha}.json` |

**Role 由呼叫端傳入**，reference 不做角色偵測。呼叫端在 dispatch prompt 或 context 說明「你是 Developer / Admin」。

---

## Step 1 — Simplify Loop

在品質檢查前，先審查本次 diff 的簡潔性。

**執行方式**：invoke user-level `/simplify` skill（`~/.claude/skills/simplify/`）。若該 skill 不存在，降級為 inline 自審 — 跑一輪「讀 diff、找重複邏輯、抽共用、移除不必要複雜度」。

**迭代邏輯**：
- 每輪 `/simplify` 結束後，若 `git diff` 有新變動 → 再跑一輪（新改動可能引入新簡化機會）
- 無變動 → 進入 Step 2
- **最多 3 輪**。第 3 輪仍有修改則停止，記錄並報給使用者判斷

**不要**做：範圍超出本次 diff 的重構、重新命名無關檔案的變數、為了「美化」而動測試檔案。

---

## Step 1.3 — Self-Review（Phase 3 exit gate）

> **DP-032 D21（v3.63.0+）**：原 Step 4 Pre-PR Self-Review Loop 概念前移為 Phase 3 的 exit gate，發生在 Step 1 /simplify 之後、Step 1.5 Scope Gate 之前。Phase 3 = LLM 實作段（TDD → /simplify → Self-Review，可迭代，fail-cheap）；Phase 4 Step 1.5 起 = 機械自驗段（線性 fail-stop）。Self-Review blocking **絕不跨段回圈**。

啟動獨立 Reviewer sub-agent 對本地 diff 做 code review。

**Reviewer 規格**：見 `references/sub-agent-roles.md § Critic (Pre-PR Review)`。回傳 JSON `{ passed, blocking[], non_blocking[], summary }`，`blocking[]` 細項含 `file:line` + `rule`（引 handbook path）+ `message`。

**Reviewer baseline — handbook-first 硬規格**：

| 來源 | 用途 |
|------|------|
| `{repo}/.claude/rules/handbook/**/*.md` + `{repo}/CLAUDE.md` + `{repo}/.claude/rules/**/*.md` | **Primary compliance baseline**（judge against） |
| task.md `## 改動範圍` / `## 估點理由` | **Context only**（理解 PR 意圖，**不**作 compliance spec） |
| task.md `Allowed Files` / `verification.*` / `depends_on` | **不讀**（D20 Scope Gate / D15 verify evidence / D14 artifact gate 已處理） |

Rationale：handbook 是 repo long-term convention（repo SoT）；reviewer 以「這 PR 對 repo 是不是好的」為基準，不是「這 PR 是否符合 task.md 文字」。避免 task.md rubber stamp workaround。

**迭代規則**：

- `passed: true` → Phase 3 exit，進 Step 1.5 Scope Gate
- `passed: false` → 回 **Phase 3**（LLM 可自由改 test / 改實作 / 重跑 /simplify 任一），不只是回 /simplify
- 回到 Phase 3 後**必然重走** TDD → /simplify → Self-Review（Phase 3 exit condition 強制）
- **Hard cap 3 輪**，超過 → halt → 使用者手動介入
- **NO bypass**（無「強制繼續」flag；承 D11 / D12 / D14 / D15 / D16 / D20 一致立場：LLM 不自己決定跳過 gate）

**Evidence**：

- Self-Review **不寫 evidence file**，**不進 Layer A+B+C AND gate**（gate 仍只涵蓋 Layer A verify + Layer B behavioral + Layer C VR）
- Self-Review 是 LLM 語意 checkpoint，不是 CI-class gate；加 evidence 成本高、revision R5 重跑無益
- Self-Review 產出仍可記入 Phase 6 Detail artifact（`specs/{EPIC}/artifacts/engineering-{ticket}-{ts}.md`），可追溯不擋 PR
- **Revision mode R5 不重跑 Self-Review**（R5 只跑 Layer A+B+C 機械 evidence；Phase 3 全段不進 R5）

---

## Step 1.5 — Scope Gate（D20）

> **機械自驗段起點**。在 Phase 3 exit（Self-Review pass）之後、Step 2 之前，catches scope creep at the earliest mechanical checkpoint after LLM implementation completes.

### Developer mode

使用 `scripts/check-scope.sh`：

```bash
SCOPE_JSON=$(bash "${POLARIS_ROOT}/scripts/check-scope.sh" "<path/to/task.md>")
```

Script 行為：
- 透過 `parse-task-md.sh` 讀取 task.md `## Allowed Files`
- 比對 `git diff --name-only` 的實際改動檔案

| 結果 | 動作 |
|------|------|
| exit 0 — 所有檔案在 scope 內 | ✅ 繼續 Step 2 前置 |
| exit 1 — scope 超出 | ❌ **HALT**。訊息：「Scope 超出 task.md Allowed Files {N} 個檔（{files}），回 `/breakdown {EPIC}` 更新 Allowed Files 或拆新子 task」 |

**嚴格立場**：
- **NO runtime override**（無 `allowed_files_override` 欄位）
- **NO bypass env var**
- Scope 超出 = 回到上游 breakdown 修正，不在 delivery flow 內自行豁免

### Admin mode

無 task.md → **跳過本步驟**。

---

## Step 2 前置 — Rebase Re-Sync（D6/D19）

> 在 Local CI Mirror 之前執行 rebase，確保 evidence 基於最新 base。

使用 `scripts/engineering-rebase.sh`：

```bash
REBASE_RESULT=$(bash "${POLARIS_ROOT}/scripts/engineering-rebase.sh" "<path/to/task.md>")
```

### Script protocol

| stdout | 意義 | 動作 |
|--------|------|------|
| `REBASE_NOOP` | base 無新 commit | 繼續 Step 2 |
| `REBASE_OK` | rebase 成功 | 繼續 Step 2 |
| `REBASE_CONFLICT: <files>` | 衝突，`.git/rebase-merge/` 保留 | **halt** — conflict resolution 是 LLM semantic work（同 Phase 3 TDD domain）；解完後 resume from Step 2 前置 |

### Post-rebase 衛生

Script 自動呼叫 `changeset-clean-inherited.sh`（D24）清理因 rebase 帶入的 inherited changeset。

### First-cut vs Revision

- **First-cut**：通常 `REBASE_NOOP`（branch 剛由 D4 `engineering-branch-setup.sh` 從最新 base 建立）
- **Revision R0**：always runs（base 可能在 review 期間前進）

### Evidence chain

Rebase 改變 HEAD → 舊 evidence 的 `head_sha` 自動失效 → 所有下游 evidence 自然重新產生。

### Admin mode

同行為（rebase against upstream）。

---

## Step 2 — Local CI Mirror

執行 `bash "${POLARIS_ROOT}/scripts/ci-local-run.sh"`（wrapper 自動解 main checkout canonical + 用 `--repo $PWD` 跑當前 worktree／checkout）。

此 script 由 `scripts/ci-local-generate.sh` 從 repo 的 CI config（Woodpecker / GitHub Actions / GitLab CI / husky / `.pre-commit-config.yaml` / `package.json` scripts）推導產出，序列化執行 install / lint / typecheck / test / coverage 類別的 commands，並嵌入 codecov patch coverage compute。每個 repo 一份 self-contained script，框架本體不再做 CI re-discovery。

**Existence invariant**：**main checkout** 的 `.claude/scripts/ci-local.sh` 存在 → 此 repo 已宣告 Local CI Mirror，所有 worktree 共用此 canonical script（DP-043 follow-up）。該檔由 generator 產出且自動寫進 `.git/info/exclude`（不入 commit）。是否需要跑由檔案存在決定，不由 git status 類型決定。

**Re-test-after-fix 鐵律**：若本 step 發現問題並修改 code，必須**重跑一次** `ci-local.sh`。上一輪修改前的結果無效。

> **Dimension model (DP-029 D6 v2 / D11；DP-032 D12-c)**：engineering 的品質要求分兩層：
> - **Dimension A — Framework Baseline（一律執行）**：TDD discipline（red-green-refactor）+ 功能驗證（`Verify Command` Step 3d）+ VR（conditional, Step 3.5）
> - **Dimension B — Repo CI-Equivalent（repo 有 `ci-local.sh` 就跑、沒有就跳）**：`ci-local.sh` 模擬 repo CI 的 patch gate / lint / typecheck / 其他 workflow jobs。repo 有配就跑，沒配就不跑 — **patch coverage 歸 repo 責任，框架不主動追加**
>
> Commit / push / `gh pr create` 前必須確認 Dimension B 全綠。Dimension A 的 TDD discipline 由 `tdd-bypass-no-assertion-weakening` canary 把關（見 `mechanism-registry.md`）。
>
> **Remote CI wait policy**：`ci-local.sh` 是 repo CI-equivalent 的本地 authority。push / PR 後，GitHub / Woodpecker / GitLab 等遠端 CI 若仍是 queued / pending / running，不阻擋 Step 8.5 或 user-facing complete。遠端 check 若已完成且明確 FAIL，才進 revision mode 作為 CI failure signal；不因等待遠端 CI 太久而延後 complete。

**執行**：

```bash
bash "${POLARIS_ROOT}/scripts/ci-local-run.sh"
```

- exit 0 → Dimension B PASS，進 Step 3
- exit 1 → Dimension B FAIL，**回到實作階段修 root cause**，禁止放寬 assertion / `.skip()` / `as any` 繞過（canary: `tdd-bypass-no-assertion-weakening`）；修完回 Step 2 開頭重跑

**Evidence file（自動寫入）**：`ci-local.sh` 執行完必寫 `/tmp/polaris-ci-local-{branch}-{head_sha}.json`（status / branch / head_sha / timestamp / commands / summary）。`gate-ci-local.sh` 在 git pre-commit / pre-push 及 `polaris-pr-create.sh` 前讀此檔案：cache hit (head_sha + status PASS) → 放行；cache miss 或非 PASS → **同步實跑** `ci-local.sh`，PASS 放行 / FAIL 擋。跳過本 step ≠ 漏網 — gate 會在第一個 git 動作補位執行。

**沒有 repo CI 配置（例如框架 repo / prototype）**：`ci-local-generate.sh` 偵測不到任何可推導的 commands → 產出 NO_CHECKS_CONFIGURED 純路徑 `ci-local.sh`，直接 PASS（仍寫 evidence file status: PASS）。這是 design — 框架尊重 repo maintainer 的 CI 決策，不主動強加 coverage baseline。

**Empty-coverage 安全網（`ci-local.sh` 內建 invariant）**：若所有 patch gate 結果為 SKIP（`no_instrumented_patch_lines`）但 diff 中有匹配 gate path 的檔案，`ci-local.sh` 判定 FAIL（tests 很可能沒跑出 coverage data）。defense-in-depth — 攔截 test runner 靜默跳過 / coverage 生成失敗等未預見原因。

**Bypass**：`POLARIS_SKIP_CI_LOCAL=1` — emergency escape only，不應日常使用。**沒有** `wip:` commit-msg skip / **沒有** main-develop branch skip / **沒有** deprecation shim（D12-c 一次到位的 breaking change）。

**歷史**：KB2CW-3847 事件（useFetch key 改動沒補測試、本地 quality PASS 但 CI `codecov/patch/main-core` FAIL）促成 DP-029 Phase B 的 patch gate 精確模擬。早期版本掛了 framework-level `coverage-gate.sh`（D6 v1），D6 v2 (2026-04-24) 判定「repo 有配就由 Dimension B 接、沒配不追加」更乾淨，coverage-gate 下架。D12-c (v3.58.0) 進一步把 `ci-contract-run.sh` / `quality-gate.sh` / `pre-commit-quality.sh` 整批下架，改由 `ci-local-generate.sh` 為每個 repo 生成 self-contained `ci-local.sh`，框架本體只保留 `ci-local-gate.sh` PreToolUse hook 做 evidence 把關。

---

## Step 3 — Behavioral Verify（`run-verify-command.sh`）

### Developer mode

使用 `scripts/run-verify-command.sh`（D15）：

```bash
bash "${POLARIS_ROOT}/scripts/run-verify-command.sh" "<path/to/task.md>"
```

**Script 行為**：

1. 透過 `parse-task-md.sh --field verify_command,level,task_jira_key,repo` 讀取 task.md
2. D17 level-based dispatch：
   - `Level=static` → 直接執行 verify command
   - `Level=build` → 先呼叫 `run-test-prep.sh` → 再執行
   - `Level=runtime` → 先呼叫 `start-test-env.sh` orchestrator（D11 L3）→ 再執行
3. 執行 fenced shell verify command，captures stdout/stderr/exit + sha256 hash
4. Best-effort `curl URL → HTTP status` extraction from output
5. 原子寫入 evidence 到 `/tmp/polaris-verified-{ticket}-{head_sha}.json`（writer=`run-verify-command.sh`）
6. exit 0 = command exit 0 AND evidence file written
7. exit ≠ 0 = FAIL → **halt delivery flow**，report output to user

### LLM 行為界線

**LLM must NOT**：
- 直接執行 `curl` 做 behavioral verification（use the script）
- 透過 Write/Edit tool 寫 evidence file（D16 hook blocks；use the script）
- 自行判斷 verify command output 是否 pass（script handles exit code）

**LLM may**：
- 讀 script stdout 理解 failure context
- Debug root cause when script reports FAIL
- 修完 code 後再次 invoke `run-verify-command.sh`

### Admin mode

無 task.md → **跳過**（no verify command available）。

### Evidence schema

`/tmp/polaris-verified-{ticket}-{head_sha}.json`：

```json
{
  "ticket": "GT-521",
  "head_sha": "abc1234",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "command": "curl -sS ...",
  "stdout_hash": "sha256:...",
  "urls_detected": [{"url": "...", "http_status": 200}],
  "at": "2026-04-26T09:30:00Z"
}
```

---

## Step 3.5 — Visual Regression（`run-visual-snapshot.sh`，conditional，D18）

### 觸發條件

**Triggered by**：`task.md Test Environment Level=runtime` AND `task.md verification.visual_regression` is non-empty（from DP-033 schema）。

**NOT triggered by**：config glob ∩ git diff filename matching（old mechanism removed）。

無 task.md / task.md 無 VR 段落 → **跳過**。

### 執行

`scripts/run-visual-snapshot.sh`（D18，Wave δ scope — not yet landed）：
- `--mode baseline`：screenshot before state
- `--mode compare`：screenshot after + image diff + PASS/FAIL judgment per task.md `expected` field

### PASS/FAIL table

從 task.md `verification.visual_regression.expected` 讀取：

| expected | diff result | verdict |
|----------|------------|---------|
| `none_allowed` | any diff | FAIL |
| `none_allowed` | 0 diff | PASS |
| `baseline_required` | first run, no before | PASS, establish baseline |
| `update_baseline` | diff exists | PASS, new baseline + diff images in PR |
| `update_baseline` | 0 diff | FAIL (tentative strict) |

### Evidence

`/tmp/polaris-vr-{ticket}-{head_sha}.json`（Layer C, conditional — only required when trigger fires）。

### 暫行

`run-visual-snapshot.sh` is Wave δ scope（尚未實作）。Until landed, this step is a **NO-OP skip** with `vr: { triggered: false, reason: "script not yet available" }`。

### visual-regression skill sunset（D18）

獨立的 `visual-regression` skill 正在 sunset。VR execution 吸收進本 delivery flow step。**Do NOT invoke the `visual-regression` skill** — 待 `run-visual-snapshot.sh` 落地後使用。

---

## Step 4 — _(已搬至 Step 1.3 — Phase 3 exit gate)_

> **DP-032 D21（v3.63.0+）**：原 Pre-PR Self-Review Loop 概念前移為 Phase 3 的 exit gate，發生在 /simplify 之後、Step 1.5 Scope Gate 之前。
>
> - 新位置：本檔 § Step 1.3
> - Reviewer baseline：handbook-first（見 § Step 1.3）
> - 迭代：blocking → 回 **Phase 3**（不只 /simplify），hard cap 3 輪，**NO bypass**
> - Step 4 編號保留作為 placeholder，不重編後續 Step 5/6/7/8 以免下游 reference 斷裂

---

## Step 5 — Base Freshness Detection（D19）

> 純偵測，不做 side-effect。偵測與行動分離 — 本 step 只 detect，rebase action 集中在 Step 2 前置。

使用 `scripts/check-base-fresh.sh`：

```bash
bash "${POLARIS_ROOT}/scripts/check-base-fresh.sh" "<path/to/task.md>"
```

| 結果 | 動作 |
|------|------|
| exit 0 — fresh（base 自上次 rebase 後無新 commit） | ✅ 繼續 Step 6 |
| exit 1 — stale（base 有新 commit） | 🔄 **delivery flow loops back to Step 2 前置 Rebase** |

### Loop-back 行為

Step 2 前置 runs `engineering-rebase.sh` → rebase 改變 HEAD → 舊 evidence auto-invalidate → Steps 2→3→3.5 re-execute with new HEAD → Step 5 re-checks freshness。

### Admin mode

同行為（rebase against upstream）。

---

## Step 6 — Commit + Changeset

### 6a. Commit

依 `references/commit-convention-default.md` 的 fallback chain 解析 commit message 規範：

1. **L1 — Repo tooling**：`{repo}/.commitlintrc.*` / `commitlint.config.*` / `package.json#commitlint` / husky `commit-msg` hook（最權威；機器規則 + commit-msg hook 同源 SoT）
2. **L2 — Repo handbook**：`{repo}/.claude/rules/handbook/**/*.md` 的 commit convention 段（補 L1 未宣告的敘述要求）
3. **L3 — Polaris default**：`references/commit-convention-default.md`（本 framework 兜底；headline 格式、type enum、subject 規則、squash 策略、revision 規格皆由此檔提供）

**規則衝突處理**：L1 命中即停（type enum / scope / subject limit 走 L1）；L2 / L3 只在 L1 未宣告的維度補充。

**做法**：手動寫 commit message + `git commit`（不假設 `git ai-commit` 等 user-level 工具可用，DP-032 D22 已從 framework 拔除）。commit-msg hook fail → 讀 stderr → 對照 L1 config 修 msg → 重試。

### 6b. Changeset（Phase 3 deliverable — 此處確認/補建，D24）

Changeset 是 **Phase 3 code deliverable**（與程式碼、測試同層級），不是獨立的 delivery step。此處做最終確認/補建。

先偵測 repo 是否真的啟用 Changesets。只有同時存在 `.changeset/` 與 `.changeset/config.json` 才啟動 changeset 產生/檢查；只有空目錄或沒有 config 視為未啟用，直接 skip。

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "$REPO_ROOT/.changeset/config.json" ]]; then
  bash "${POLARIS_ROOT}/scripts/polaris-changeset.sh" new --task-md "<path/to/task.md>" --repo "$REPO_ROOT"
fi
```

**Script 行為**：
- `.changeset/config.json` absent → no-op exit 0（repo does not use changesets）
- 從 `.changeset/config.json` 推導 package scope
- 從 ticket+title 推導 filename slug
- Description = stripped task title（**LLM does NOT write description** — D24 BS-D24-1）
- `--bump {level}` optional（LLM 唯一的語意貢獻：`patch` default，override if warranted）
- Idempotent：same slug already exists → silent skip exit 0
- Multi-package without declaration → **fail-loud**

**Inherited changeset cleanup**：已由 `engineering-rebase.sh` post-rebase hook 處理（D24），此處不需另外清理。

**Admin mode**：若 repo 有 changeset requirements 但無 task.md → `polaris-changeset.sh` will fail。Admin 使用 Write tool 手動建 changeset with conventional description。

### 6c. JIRA Safety Net（Admin fallback）

Admin 模式無 ticket key。若 repo 的 changeset guideline 要求 ticket key：
- Admin branch 名含 `wip/` 或 `polaris/` → 允許省略
- 其他情況 → 提示使用者補 key，或走 `references/pr-input-resolver.md` 的 fallback 流程

---

## Step 7 — PR Create

### 7a. Evidence AND Gate（pre-PR verification）

Before creating PR，驗證所有必要 evidence 檔案存在且 `head_sha` 匹配當前 HEAD：

| Layer | Evidence file | Required? |
|-------|--------------|-----------|
| A (CI) | `/tmp/polaris-ci-local-{branch}-{head_sha}.json` | Always（if `ci-local.sh` exists） |
| B (Verify) | `/tmp/polaris-verified-{ticket}-{head_sha}.json` | Developer with verify_command |
| C (VR) | `/tmp/polaris-vr-{ticket}-{head_sha}.json` | Only if Step 3.5 triggered |

Missing 或 stale evidence → **halt**。不繼續 PR creation。

**Portable gate fallback**：`gate-evidence.sh` + `gate-ci-local.sh` 在 git pre-push 及 `polaris-pr-create.sh` wrapper 中也強制檢查；`gate-pr-title.sh` + `gate-changeset.sh` 在 `polaris-pr-create.sh` 與 completion gate 中強制檢查。Skill-level check here is **L2 cross-LLM authoritative**（所有 LLM 都走 SKILL.md → 一定到這步）。

### 7b. 讀 PR template

依 `references/pr-body-builder.md` 的 template detection 邏輯讀取 repo 的 `.github/pull_request_template.md`。無則 fallback 到預設格式。

### 7c. 組 PR body

| Template section | 填充來源 |
|------------------|---------|
| Description | Developer：task.md § 目標；Admin：commit messages 概要 |
| Changed | `git diff --name-only` + 人話摘要 |
| AC Coverage | Developer：task.md § AC + Layer B 驗證結果打勾；Admin：跳過 |
| Test Plan | Developer：task.md § 測試計畫；Admin：commit 摘要中的驗證摘要 |
| Related documents | 相關 JIRA / Figma / Confluence link |

### 7d. 開 PR / 推送至既有 PR

**First-cut mode**（新 PR）：

`--base` 值**必須**來自 resolve helper，不可直接抄 task.md 字面（見 § Base Branch Resolution + DP-028 D6）：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
bash "${CLAUDE_PROJECT_DIR}/scripts/polaris-pr-create.sh" --base "${RESOLVED_BASE}" --title "<title>" --body "<body>"
```

Admin 模式（無 task.md）直接用當前 branch upstream 或 `origin/main`，跳過 resolve helper。

`polaris-pr-create.sh` wrapper（DP-032 Wave δ）在 `gh pr create` 前依序執行 gate-base-check + gate-evidence + gate-ci-local + gate-pr-title + gate-changeset — `--base` 值與 resolve 結果不符、Developer title 不符、或 task changeset 缺失時 wrapper 直接 block。

- Developer title：先讀 company `workspace-config.yaml` 中 matching repo 的 `projects[].delivery.pr_title.developer`；未設定才 fallback `[{TICKET}] {summary}`
- Admin title：`<type>(<scope>): <summary>`（conventional commit 格式）

**PR 建立成功後（Developer first-cut mode）— deliverable 回寫（DP-033 A8）**：

`gh pr create` 成功取得 `PR_URL` 後，**立刻**呼叫 write-deliverable 寫回 task.md。此步驟是 hard gate — 失敗 = HALT，不繼續執行 Step 8：

```bash
HEAD_SHA=$(git rev-parse HEAD)
"${CLAUDE_PROJECT_DIR}/scripts/write-deliverable.sh" "<path/to/task.md>" "$PR_URL" "OPEN" "$HEAD_SHA"
```

- 腳本內部：寫入 `.tmp` → `mv`（atomic）→ re-read verify（`deliverable.pr_url` 必須 match）
- 失敗時（含 3 次 retry 後仍失敗）→ 腳本 exit 1，輸出：
  ```
  task is in inconsistent state — PR created but task.md not updated. Manual recovery required.
  ```
- **不得繼續執行 Step 8**（JIRA transition / Slack 通知 / next handoff）直到此步驟 exit 0
- 不得用 `/tmp` fallback 或 silent continue — inconsistent state 必須立刻被人類看到
- Admin 模式（無 task.md）跳過本段

**Revision mode**（既有 PR）：

當 engineering 以 revision mode 觸發時，PR 已存在（PR URL 是輸入之一）。此時不建新 PR，改為 push to existing PR：

1. **PR base sync 已於 R0 完成**（engineering SKILL.md § R0 步驟 4）：若 PR `baseRefName` != `RESOLVED_BASE` → R0 已跑 `gh pr edit --base "$RESOLVED_BASE"` 同步；`gate-base-check.sh`（git hook / `polaris-pr-create.sh` wrapper）同時擋 PR base 不符 resolve 結果
2. `git push` 到既有 PR 的 remote branch（branch 已 checkout）
3. 跳過 `gh pr create`（hook 不觸發）
4. 若 PR body 需更新（如新增修正摘要），用 `gh pr edit --body` 更新（不帶 `--base` 不會觸發 gate）
5. **更新 head_sha**（revision mode）：push 成功後更新 task.md 的 `deliverable.head_sha`（同 write-deliverable.sh；`pr_state` 不變，維持 `OPEN`）

`POLARIS_PR_WORKFLOW=1` 讓 legacy `pr-create-guard.sh` hook 放行（已被 `polaris-pr-create.sh` wrapper 取代）。僅 first-cut mode 需要。

### Base Branch Resolution（適用於 § 4.5 / § R0 / 本 Step 7d）

engineering 消費 task.md `Base branch` 欄位時，**一律經 resolve helper**，不可直接抄字面值：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
```

（Helper 腳本位於 repo 相對路徑 `scripts/resolve-task-base.sh`；engineering runs 以 `${CLAUDE_PROJECT_DIR}` 展開為絕對路徑呼叫。）

Helper 的行為（見 DP-028 D2 — Resolve 層）：
- 若 task.md 的 `Base branch`（即上游 task branch）**已 merged** 回 Epic feature branch → 回傳 feature branch 值
- 否則 → 回傳原 `Base branch` 字面值

task.md 若含 `Branch chain`，engineering 在 first-cut branch setup / revision R0 會先跑 cascade rebase：

```bash
"${CLAUDE_PROJECT_DIR}/scripts/cascade-rebase-chain.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --task-md "<path/to/task.md>"
```

`Branch chain` 只表達 rebase 順序（例：`develop -> feat/GT-478-... -> task/KB2CW-3711-... -> task/KB2CW-3900-...`）。PR base 仍只取 `resolve-task-base.sh` 的輸出，避免 `Base branch` / `PR base` 雙欄位同步問題。

**應用位置**（engineering SKILL.md 四處必呼叫 resolve helper）：

| 位置 | 目的 | 呼叫時機 |
|------|------|---------|
| § 4.5 Pre-Development Rebase | `Branch chain` cascade rebase；再以 `git rebase origin/<RESOLVED_BASE>` 的 target 切 / 對齊 task branch | first-cut 開工前 |
| § R0 Pre-Revision Rebase（步驟 1-3） | `Branch chain` cascade rebase；再以 `git rebase origin/<RESOLVED_BASE>` 的 target 對齊 PR branch | revision mode 進入後，讀施工圖前 |
| § R0 Pre-Revision Rebase（步驟 4） | `gh pr edit <PR> --base <RESOLVED_BASE>` 同步 PR base 欄位（若 PR baseRefName 不符） | 同上，rebase 成功後、讀施工圖前 |
| § Step 7d (本 flow) | `gh pr create --base <RESOLVED_BASE>` 的 `--base` 值 | 建新 PR 時（first-cut） |

**跨 LLM enforcement（DP-032 Wave δ）**：工程品質 gates 已從 Claude Code PreToolUse hooks 遷移至 portable 機制：
- `scripts/gates/gate-base-check.sh` — git pre-push + `polaris-pr-create.sh` wrapper 擋 `--base` 不符 resolve 結果
- `scripts/gates/gate-evidence.sh` — git pre-push 擋缺少 verification evidence
- `scripts/gates/gate-ci-local.sh` — git pre-commit + pre-push 擋 CI 未過
- `scripts/polaris-pr-create.sh` — 取代裸 `gh pr create`，內嵌三道 gate
跳過 resolve helper 在 Step 7d 或 R0 步驟 4 都會被 wrapper / git hook block。

---

## Step 8 — JIRA Transition（Developer only）

PR 建立後，轉 JIRA ticket 狀態為 `CODE REVIEW`：

```bash
{workspace_root}/scripts/polaris-jira-transition.sh {TICKET} code_review
```

`polaris-jira-transition.sh`（D25，DP-032 Wave α）統一所有 JIRA transition 呼叫，跨 LLM runtime 共用：built-in slug map（`code_review` → "Code Review"），workspace-config `jira.transitions.code_review` 可覆寫；ticket 已在目標狀態 / 找不到 transition / 沒 creds / API error 一律 stderr 訊息 + exit 0，不阻擋 delivery flow。

**Admin 模式跳過本 step**（無 ticket）。

### 8a. Mark task spec as IMPLEMENTED（Developer only）

PR 建立成功後，將對應的 task.md frontmatter 標為 `status: IMPLEMENTED`，讓 docs-viewer sidebar 顯示綠底完成樣式：

```bash
{workspace_root}/scripts/mark-spec-implemented.sh {TICKET}
```

Helper 會自動找 Task-level anchor（T{n}/V{n} key 或 `> JIRA: {TICKET}` header 比對）→ **move-first 順序**（DP-033 D6）：
  1. `mv tasks/{T}.md → tasks/pr-release/{T}.md`（先搬，永遠不會在 active `tasks/` 內寫 IMPLEMENTED）
  2. 在 `tasks/pr-release/{T}.md` 更新 frontmatter `status: IMPLEMENTED`
- `tasks/pr-release/` 若不存在自動建立
- Idempotent — 已在 pr-release/ 且已標過相同 status 不做事
- 同 key 衝突（active 與 pr-release/ 並存且內容不同）→ exit 2，須人工解決

失敗（找不到 anchor 等）不中斷流程，但需在對話中告知使用者。

**Admin 模式跳過本 step**（無 ticket / task.md）。

---

## Step 8.5 — Completion Gate（pre-report hard gate）

> 目的不是取代 Step 7a，而是封住另一個出口：agent 在還沒碰到 git / PR gate 前，就先口頭宣稱「完成」。

在任何 user-facing completion report 之前，執行：

```bash
bash "${POLARIS_ROOT}/scripts/check-delivery-completion.sh" --repo "$(git rev-parse --show-toplevel)" --ticket "<TICKET>"
```

Admin mode（無 ticket）：

```bash
bash "${POLARIS_ROOT}/scripts/check-delivery-completion.sh" --repo "$(git rev-parse --show-toplevel)" --admin
```

### Script contract

- Layer A：呼叫 `scripts/gates/gate-ci-local.sh --repo <path>`
  - repo root 無 `.claude/scripts/ci-local.sh` → skip
  - repo root 有 `.claude/scripts/ci-local.sh` → required，cache miss 會同步實跑 `ci-local.sh`
- Layer B（Developer only）：呼叫 `scripts/gates/gate-evidence.sh --repo <path> --ticket <TICKET>`
  - missing / malformed / stale verify evidence → block
- exit 0 = 可以回報完成
- exit 2 = **HALT**，不得回報「完成 / 可交付 / 已驗完」

Completion gate 不查詢或等待遠端 repo CI。只要本地 LLM gates 與 mechanical evidence gates 已通過，queued / pending / running 的遠端 CI 不阻擋完成回報。

### Why this exists

Step 7a 保證「不能開 PR」；Step 8.5 保證「不能嘴上結案」。兩者一起才算完整的 no-bypass delivery contract。

---

## Step 8.6 — Worktree Cleanup

PR 建立 / 既有 PR branch push 完成、task deliverable 已回寫、Completion Gate PASS 後，清掉本次 implementation worktree：

```bash
git worktree remove "<worktree_path>"
```

- PR 後不保留常駐 worktree；若後續 review / CI 需要 revision，從當下 PR branch/head 重新建立 fresh worktree
- 可刪除已不需要的 local temp branch；不要刪 remote PR branch
- 若 worktree 有 uncommitted changes，先停下來分類（應提交 / 應搬到 artifact / stale experiment），不得 silent discard

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
| Step 8.5 Completion Gate FAIL | **HALT** — 不得回報完成，回頭補齊 Layer A/B evidence |

---

## Evidence — AND Gate Model（DP-032 D12/D15/D16/D18）

三個 evidence dimension，各由專屬 script 產出：

| Dimension | Script | Evidence path | Writer |
|-----------|--------|--------------|--------|
| A — CI | `ci-local.sh`（repo-level） | `/tmp/polaris-ci-local-{branch}-{head_sha}.json` | `ci-local.sh` |
| B — Verify | `run-verify-command.sh` | `/tmp/polaris-verified-{ticket}-{head_sha}.json` | `run-verify-command.sh` |
| C — VR | `run-visual-snapshot.sh` | `/tmp/polaris-vr-{ticket}-{head_sha}.json` | `run-visual-snapshot.sh` |

### Core Invariants

1. Evidence files are **only written by their designated scripts** — LLM Write/Edit to evidence paths is blocked by `no-direct-evidence-write.sh` PreToolUse hook（D16）
2. `head_sha` in evidence must match current `git rev-parse --short HEAD` — stale evidence auto-rejected
3. `writer` field must be in the known-writer whitelist（`verification-evidence-gate.sh` checks，D16 cross-LLM）
4. Layer A + B（+ C if triggered）must ALL be present and PASS before PR creation — **AND gate, not OR**
5. **NO bypass env var for evidence**（D16 NO bypass stance；`POLARIS_SKIP_CI_LOCAL=1` is the only emergency escape，covers Layer A only）

### Hook Enforcement（DP-032 Wave δ — 跨 LLM）

| 機制 | 觸發時機 | 檢查內容 | 適用範圍 |
|------|---------|--------|---------|
| `gate-ci-local.sh` git pre-commit | `git commit` | Layer A evidence | 四通（Claude / Codex / Copilot / 人類） |
| `gate-ci-local.sh` git pre-push | `git push` | Layer A evidence（push mode） | 四通 |
| `gate-evidence.sh` git pre-push | `git push` | Layer B evidence + Layer C if triggered | 四通 |
| `gate-base-check.sh` in `polaris-pr-create.sh` | PR 建立 | base branch = resolve 結果 | 四通 |
| `polaris-pr-create.sh` wrapper | PR 建立 | 依序跑 base-check → evidence → ci-local | 四通 |
| `check-delivery-completion.sh` | user-facing completion report | Layer A always if `ci-local.sh` exists; Layer B for Developer | 四通 |
| `no-direct-evidence-write.sh` PostToolUse | Write/Edit on evidence paths | **Blocks** — LLM 不可偽造 evidence | Claude Code only（advisory） |

> **Legacy hooks removed（DP-032 Wave δ）**：`ci-local-gate.sh`、`verification-evidence-gate.sh`、`pr-base-gate.sh`、`pr-create-guard.sh` PreToolUse hooks 已刪除，功能全部移至 portable gate scripts + git hooks。

---

## Role-Specific Notes

### Developer 呼叫端責任（engineering SKILL.md）

呼叫前：
- 已通過 Task Existence Gate（task.md 存在）
- 已 checkout 正確 branch（或現在建立）
- 已執行 `polaris-sync.sh` 部署 AI 設定

呼叫時 context：
- Role: `developer`
- task.md 完整內容（或路徑）
- JIRA ticket key
- Base branch

### Admin 呼叫端責任（git-pr-workflow SKILL.md）

呼叫前：
- 確認當前 repo 是 Polaris framework / docs / 通用 repo（skill-routing 會擋產品 repo）
- 當前 branch 非 main

呼叫時 context：
- Role: `admin`
- 當前 branch
- PR type（framework / docs / other）

---

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

本 reference 從原 `git-pr-workflow` Step 2-9、原 `verify-completion` 行為驗證段、原 `dev-quality-check` Step 6 smoke test 整併而來。2026-04-14 engineering（原 work-on）重構 v2 抽出作為共用 backbone（見 memory `project_workon_redesign_v2.md`）。DP-032 Wave γ-δ 重構為 Two-Segment Architecture：LLM 實作段（Phase 3）+ 機械自驗段（Step 1.5+），引入 script-mediated evidence AND gate model、scope gate、前置 rebase、base freshness detection、VR skill sunset。
