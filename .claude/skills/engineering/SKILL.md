---
name: engineering
description: >
  Engineer-minded execution orchestrator: takes a planned JIRA ticket and implements it with strict quality discipline — TDD, lint, typecheck, test, behavioral verify, PR.
  Two modes: first-cut (new implementation) and revision (fix PR review comments by returning to the work order).
  Supports batch mode via parallel sub-agents.
  Trigger: "做 PROJ-123", "work on", "engineering", "開始做", "接這張", "做這張",
  "修 PROJ-123", "fix review on PROJ-123", PR URL (from pr-pickup or direct),
  or user provides JIRA ticket key(s).
  NOT for planning: Bug → bug-triage first; Story/Task/Epic → breakdown first.
  Key distinction: "下一步" / "繼續" without ticket key → my-triage (zero-input router + resume scan).
tier: product
metadata:
  author: Polaris
  version: 5.2.3
---

# Engineering — 工程師施工

使用者說「做 PROJ-448」或「做 PROJ-100 PROJ-101 PROJ-102」，engineering skill 以工程師標準執行：品質檢查是確定性 gate（不是可跳過的步驟）、scope 變更需要理由、CI 全綠才能開 PR。規劃（根因分析、拆單、估點、測試計畫）由 `bug-triage` 或 `breakdown` 負責，本 skill 不做規劃。

## Authority Boundary（DP-032 意圖補全）

本 skill 的核心不是「盡量遵守流程」，而是**LLM 不得自行重寫流程權限**。

- **Mandatory gate 只有兩種合法狀態**：執行並通過，或執行後 fail-stop；不存在「我判斷這次可以先略過」第三條路
- **Hook / wrapper / completion gate 是補位與 enforcement，不是豁免令**。後面有 `git commit` / `git push` / `gh pr create` hook 會擋，**不代表前面可以不跑該步驟**
- **更短路徑只能發生在 skill 明文允許的分流內**；若 skill 沒寫可裁剪，LLM 無權自行裁剪
- **若想偏離 skill**（例：跳過 `ci-local.sh`、不進 revision mode、先修 blocker 再補 gate），必須先停下來取得使用者明確同意；未同意前一律視為違規
- **「技術上能修好」不等於「流程上可這樣做」**。engineering 的完成權限不在 LLM 自述，在 mechanical evidence + gates
- **任何以「hook 之後會擋」「問題很聚焦」「改動很小」「這次只是 patch coverage」為理由的 shortcut，預設無效**
- **Scope escalation 證據只能寫 sidecar，不能改 planner-owned 欄位**：當機械 gate 失敗且修法會踩到 planner-owned 欄位（Allowed Files / estimate / Test Command / Verify Command / Test Environment / depends_on），停止施工、寫 `specs/{EPIC}/escalations/T{n}-{count}.md` sidecar、交回 `breakdown`（DP-044）。engineering **不得直接 Edit/Write task.md**；唯一例外是透過 approved lifecycle writer scripts 寫回 execution-owned metadata（例如 `write-deliverable.sh` 寫 `deliverable.*`、`mark-spec-implemented.sh` 寫 `status: IMPLEMENTED` + move-first）
- **task.md 欄位權限分層**：planner-owned 欄位一律由 `breakdown` / `bug-triage` 維護；engineering 只能透過 helper-only contract 寫 execution-owned lifecycle metadata（`deliverable.pr_url` / `deliverable.pr_state` / `deliverable.head_sha` / `status: IMPLEMENTED` / `jira_transition_log[]`）。不得手動編輯 lifecycle 欄位，也不得新增 helper 以外的 task.md write-back path
- **Scope escalation 必須以 gate closure 為單位**：engineering 不只是找第一個 out-of-scope file，而是要診斷「要讓這個 mandatory gate 通過，需要哪些 planner decision」。若 proposed scope change 只是必要但不充分，sidecar 必須明寫 residual blockers 與 closure forecast，不得把半套權限請求交回 breakdown

## Pipeline 角色

本 skill 是 pipeline 的 **Execution** 環節（見 [pipeline-handoff.md](../references/pipeline-handoff.md)）。上游 breakdown 已打包出 self-contained task.md work order；本 skill 消費 **codebase + task.md + repo handbook（須主動讀取 `{repo}/.claude/rules/handbook/`）**，不再回頭讀 breakdown.md / refinement.md。

**輸入優先順序**：
1. `specs/{EPIC}/tasks/T{n}.md` — breakdown v2 產出（新 pipeline 的主要輸入）；若 active `tasks/` 找不到，fallback `tasks/complete/T{n}.md`（DP-033 D8）
2. `specs/{TICKET}/plan.md` — legacy 格式（過渡期 fallback；P5 cutover 後移除）

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 0. Entry Resolution

engineering 的入口目標只有一個：**找到 authoritative work order**，然後從 work order 派生 mode。不要先讀 JIRA 狀態再猜流程。能用 script 解的，直接用 script，不要臨場手拼 grep / gh 查詢流程。

### 0a. 支援輸入

| 輸入形式 | 解析方式 |
|----------|---------|
| `task.md` / `plan.md` 路徑 | `scripts/resolve-task-md.sh --write-lock <path>` |
| JIRA ticket key（`[A-Z]+-\d+`） | `scripts/resolve-task-md.sh --write-lock <KEY>` |
| PR URL / PR number | `scripts/resolve-task-md.sh --write-lock <PR_REF>` |
| 目前 branch / 原始使用者訊息 | `scripts/resolve-task-md.sh --write-lock --current` / `scripts/resolve-task-md.sh --write-lock --from-input "{raw_user_msg}"` |

### 0b. Work Order Gate

- **唯一合法輸入**：`task.md`（優先）或 legacy `plan.md`
- **resolver 成功後的結果是 authoritative**：不得再用 `find` / `rg` / `grep` 對 `specs/**/tasks` 做人肉 fallback 覆寫結論；若要放棄當前 resolver 結論，先 `scripts/resolve-task-md.sh --clear-lock` 再重新 resolve
- **JIRA 在 engineering 是 write-only side-effect**：可寫 transition / comment；**不可**把 task ticket 的 description / comment / status 當施工指令來源
- **不要 fallback 到舊 breakdown 產物或 JIRA 內嵌方案**
- **Epic key 不直接進 engineering**：若找不到單一 task.md，fail loud，回上游挑子單或補規劃
- **命中多個 task.md**：fail loud；同一 JIRA key 不應對應多張 work order

### 0c. Mode 由 Work Order 派生

解析 work order 後，以 `deliverable.pr_url` 決定 mode：

| 條件 | Mode |
|------|------|
| `deliverable.pr_url` 為空 / null | **first-cut mode** |
| `deliverable.pr_url` 有值，且 `gh pr view` 顯示 `OPEN` | **revision mode** |
| `deliverable.pr_url` 有值，但 PR `MERGED` / `CLOSED` | **fail loud**（先修 task.md / deliverable 狀態） |

## 批次模式（精簡）

當輸入包含多張 ticket / 多個 task 路徑時：

1. 先把每一項都 resolve 成單一 `task.md` / `plan.md`
2. 無法 resolve 的項目直接標示阻擋，不進施工
3. 可 resolve 的項目依同一套規則派生成 `first-cut` 或 `revision`
4. 同 repo 使用 worktree 隔離；跨 repo 可平行

批次 dispatch prompt 保持最小化，避免把過時流程複製進子代理：

```text
你是開發 agent。唯一工作指令來源是 task.md / plan.md。

- 先讀 repo handbook：{repo}/.claude/rules/handbook/index.md + 引用子文件
- 不要讀 JIRA task description/comment 當施工來源
- 所有 task.md 欄位一律用 scripts/parse-task-md.sh 取得
- first-cut：用 scripts/engineering-branch-setup.sh 建 branch + worktree；不要再跑獨立 pre-dev rebase
- revision：先跑 scripts/revision-rebase.sh，再進 R1-R6
- TDD 參考 references/tdd-loop.md，不依賴 unit-test skill frontmatter
- 驗證與交付依 references/engineer-delivery-flow.md；完成前必跑 check-delivery-completion.sh
```

## First-Cut Workflow

> 適用於：work order 尚無 `deliverable.pr_url`，需要從頭建 branch → 實作 → 開 PR。

### 1. Resolve Work Order

先用 `scripts/resolve-task-md.sh --write-lock --from-input "{raw_user_msg}"` 或等價單一輸入，定位單一 `task.md` / `plan.md`。找不到就阻擋，不開工。

```text
⛔ Work Order Gate — 找不到 task.md / plan.md

engineering 是純施工 skill，沒有 work order 就不施工。
請先回上游補 breakdown / bug-triage 產出。
```

### 2. Optional Contract Check

若 work order 涉及 fixtures / API contract，先跑對應 contract check（見 `references/api-contract-guard.md`）。這是前置驗證，不改變 mode。

### 3. Branch + Worktree Setup

- JIRA transition：`{workspace_root}/scripts/polaris-jira-transition.sh {TICKET} in_development`（D25，soft-fail）
- 建 branch / worktree：`bash "${POLARIS_ROOT}/scripts/engineering-branch-setup.sh" "<path/to/task.md>"`

**注意**：first-cut **不再有獨立 pre-development rebase**。D4 已把它消化進 branch setup 契約；新 branch 從 `origin/{resolved_base}` tip 切出，本質上不需要再 rebase 一次。

### 4. TDD 開發

1. 讀 repo handbook：若在 git worktree 內，先用 `scripts/lib/main-checkout.sh` 的 `resolve_main_checkout` 找 repo 主 checkout，再讀 `{main_checkout}/.claude/rules/handbook/index.md` + 引用子文件（repo handbook 是 gitignored local artifact，不保證存在於 worktree）
2. 讀專案 `CLAUDE.md`
3. 讀 `references/tdd-loop.md` 與 `references/tdd-smart-judgment.md`
4. 先跑依賴安裝：`bash {polaris_root}/scripts/env/install-project-deps.sh --task-md {task_md_path} --cwd "$(git rev-parse --show-toplevel)"`
5. 用 `scripts/parse-task-md.sh <task_md_path> --field test_command` 取得測試指令；不可自行推導
6. 用 `scripts/parse-task-md.sh <task_md_path> --field level` / `--field fixtures` 決定 verify 前置環境
7. `level=runtime` 時，透過 `scripts/start-test-env.sh` 啟動；不要手動拼 `docker compose up` / `pnpm dev`
8. repo 主 checkout 有 `.claude/scripts/ci-local.sh` 就必跑；在 worktree 內一律用 `bash "${POLARIS_ROOT}/scripts/ci-local-run.sh" --repo "$(git rev-parse --show-toplevel)"`，不要直接查 worktree 的 `.claude/scripts/ci-local.sh`；`hook` 只負責補位，不是可省略理由

> `Runtime consistency` 不再由 engineering 消費時臨場判斷；它屬於 work order 合法性，應由上游 artifact gate 擋住。

### 5. 交付流程

開發完成後，讀 `references/engineer-delivery-flow.md`，以 **Role: Developer** 執行：

- Phase 3：Simplify → Self-Review
- Phase 4：Scope Gate → Step 2 `ci-local.sh` → Step 3 `run-verify-command.sh` → Step 3.5 VR → Base Freshness → Commit → PR → JIRA → Completion Gate

完成前必跑：

```bash
bash "${POLARIS_ROOT}/scripts/check-delivery-completion.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --ticket "{ticket_key}"
```

## 開發中 Scope 追加

實作過程中發現需要追加改動時，**不可直接改 code**，必須先對齊再動手：

1. **暫停實作**，向使用者說明追加原因
2. 使用者確認後，**在 JIRA 留 comment** 記錄 scope 追加：
   - 追加原因（實測數據 vs 預期、根因分析）
   - 追加的改動檔案和內容
   - 測試計畫是否需要調整
3. 若測試計畫需要新增項目 → 建立新的 [驗證] sub-task
4. 若 plan file 存在 → 同步更新 plan file
5. 繼續實作

**不需要追加測試計畫**：改動只影響內部實作，API 回傳結構不變，現有驗證子單已涵蓋。
**需要追加測試計畫**：改動引入新的 API 欄位、新的錯誤處理路徑、新的 service 依賴。

### 開發中 Scope Escalation（DP-044）

> 這是「無法在 engineering 內部消化」的 scope 追加分支。本節**取代**任何「直接修 task.md 然後繼續做」的衝動。
>
> 觸發條件（同時成立才適用）：
> 1. 機械 gate 失敗（`ci-local.sh`、`tsc:baseline`、`run-verify-command.sh` 等回非 0）
> 2. 失敗檔案落在本 task `Allowed Files` **之外**
> 3. 修這個失敗的方式會異動 planner-owned 欄位：`Allowed Files` / estimates / `Test Command` / `Verify Command` / `Test Environment` / `depends_on`
>
> 三條只要少一條就走前面的 § 開發中 Scope 追加 流程，不寫 sidecar。

**步驟（依序）：**

1. **立即停下所有 Edit/Write**。本節之後不允許再修 source code，直到 sidecar 落地、breakdown 接手。
2. **Gate Closure Diagnosis（LLM 必做，不可只列第一批檔案）**：
   - Gate to close：哪個 mandatory gate 失敗（例：`ci-local` / `type baseline` / `verify command` / `coverage`）
   - Pass condition：該 gate 的通過條件（例：`actual type_errors <= baseline type_errors`）
   - Current measurement：baseline、actual、exit code、evidence file
   - Explained delta：把可歸因的 delta 拆成因果群（例：`+2 storage typing`、`+12 residual baseline/env drift`）
   - Candidate fixes：每個因果群的可能修法、是否在 Allowed Files、是否需要 planner-owned 欄位異動
   - Closure forecast：若只批准某個候選修法，gate 是否會過；若答案是 No，必須明寫 residual blockers
   - Required planner decisions：讓 gate 可能通過的最小完整決策集合，不是第一個越界檔案集合
3. **計算 `escalation_count`**：
   ```bash
   ls "{company_base_dir}/specs/{EPIC}/escalations/T{n}-"*.md 2>/dev/null | wc -l
   ```
   既有檔案數 + 1 = 本次 `count`。
4. **Lineage cap 檢查（DP-044 D5）**：若 `count` 將 > 2，**不要**寫 sidecar；改向使用者回報「lineage 已達 cap，請改跑 `refinement {EPIC}`（不是 `breakdown`）」並結束本 session。
5. **First-pass flavor 分類**：依 `references/escalation-flavor-guide.md` 的 gate-closure 決策樹挑選 primary `flavor`。一張 sidecar 可以有多個 components；frontmatter `flavor` 放最能代表 gate closure 的 primary hint，細項放 `## Explained Delta` / `## Required Planner Decisions`。
6. **Scrub 原始證據**：把要進 `## Raw Evidence` 的內容（gate 輸出、normalized 失敗檔案清單、相關 commit / baseline 比對）先存暫存檔，再透過 scrubber 過濾後再 Write 進 sidecar：
   ```bash
   python3 "${POLARIS_ROOT}/scripts/snapshot-scrub.py" --file "{tmp_path}"
   ```
7. **產 sidecar**（D7 schema 對齊 `references/handoff-artifact.md`，刪 `scope` 欄、增 `flavor` + `escalation_count`，並加 gate-closure 必填段落）：
   ```
   {company_base_dir}/specs/{EPIC}/escalations/T{n}-{count}.md
   ```
   Frontmatter required：`skill: engineering`、`ticket`、`epic`、`flavor` ∈ {plan-defect, scope-drift, env-drift}、`escalation_count` ∈ {1,2}、`timestamp`（ISO 8601 with `Z`）、`truncated`、`scrubbed`。
   Body required：
   - `## Summary`（≤ 500 chars；headline gate + closure forecast）
   - `## Gate Closure`
   - `## Current Measurement`
   - `## Explained Delta`
   - `## Proposed Fixes`
   - `## Residual Blockers`
   - `## Closure Forecast`
   - `## Required Planner Decisions`
   - `## Raw Evidence`
8. **Validator gate（hard）**：
   ```bash
   bash "${POLARIS_ROOT}/scripts/validate-escalation-sidecar.sh" \
     "{company_base_dir}/specs/{EPIC}/escalations/T{n}-{count}.md"
   ```
   exit ≠ 0 → 修補 sidecar 直到 pass。**未過 validator 不得結束本 session**。
9. **Halt + report**：在主對話回報使用者：
   - sidecar 絕對路徑
   - 提案 flavor
   - closure forecast（特別是「若只批准部分修法，gate 是否仍會 fail」）
   - 建議下一步：`breakdown {EPIC}`（intake mode；breakdown 會自動掃 `escalations/`）
   不要繼續實作、不要 push、不要開 PR。

**硬性紅線（DP-044 D2）**：自進入本流程後，engineering session 對 `task.md` 的 planner-owned 欄位一律 read-only。所有 planner-owned 欄位異動必須由 `breakdown` 在 intake path 執行。進入本流程後不得再進行 delivery lifecycle write-back（不 push、不開 PR、不跑 `write-deliverable.sh` / `mark-spec-implemented.sh`）；違反 = critical drift（見 `mechanism-registry.md` § Scope Escalation）。

---

## Revision Mode

> 適用於：ticket 已有 open PR，需要回施工圖處理 review signals（review comments + CI failures）。
> 核心原則（D1）：「修 PR」= 回施工圖重新施工，不是逐一 patch review comments。

### R0. Pre-Revision Rebase + PR Base Sync（強制，DP-028）

Revision mode 進入後、讀施工圖前，**先 rebase PR branch 到 task.md 規定的 base**，同步修正 PR 的 base 欄位。理由和 first-cut 的 branch-setup 原則一致：先把 base 對齊，再開始語意工作；且 PR 的 `baseRefName` 本身可能就是錯的（這正是 DP-028 要洗掉的情境）。

**單一指令** — 所有邏輯（task.md 定位、resolve base、fetch、rebase、PR base sync、legacy fallback）都在 script 內處理：

```bash
"${CLAUDE_PROJECT_DIR}/scripts/revision-rebase.sh"
```

可選 flag：`--task-md <path>`、`--pr <PR_NUMBER>`、`--repo <path>`。預設從 current branch + cwd 推導。

**Exit code**：
- `0` = rebase clean（或不需 rebase）+ PR base 已同步 → 進 R1
- `1` = conflict / fetch 失敗 / `gh pr edit` 失敗 → **停止**，回報使用者（rebase-in-progress 狀態須手動處理；script 已印 abort advisory）
- `2` = usage error

Stdout 為單行 JSON evidence（schema 見 script header）。

> **為什麼不讀 PR baseRefName**：PR 可能建立時就指向錯 base（pre-DP-028 手動建 PR 或其他漂移），把它當事實會複製錯誤。task.md 是 snapshot source-of-truth，resolve helper 是動態調整層。Script 內部已實作此邏輯（先 `resolve-task-md-by-branch.sh --current` 再 `resolve-task-base.sh`）。

> **Legacy PR fallback**：找不到 task.md → script 自動 fall back 到 PR `baseRefName` 當 base 做 fetch + rebase，但**不**做 PR base sync 步驟（無 source-of-truth 比對）。stderr 會印 advisory，evidence `legacy_fallback: true`。

> **Portable gate enforcement**：`gate-base-check.sh`（DP-032 Wave δ）在 `polaris-pr-create.sh` wrapper 及 git pre-push 中擋不符 resolve 結果的 base — 跳過 script 自己手動跑等價指令也會被 block。

### 前置：Plan Existence Gate（Legacy PR 硬擋，D8）

Revision mode 進入後，先檢查 work order 是否存在（同 § Plan Existence Gate 邏輯）。

- **有 plan（task.md / plan.md）** → 繼續 R1
- **無 plan（legacy PR）** → **硬擋**：

```
⛔ Revision Mode — 此 PR 無施工圖（legacy）

Review signals 無法與原計劃比對，因為沒有計劃。

建議：
  1. 先跑「breakdown {TICKET}」補一份施工圖，再回來修 review
  2. 或使用 `--bypass` 旗標跳過計劃比對（⚠️ 警告：會跳過 D1 驗證，
     直接以 reviewer comments 為指令修改 code，失去系統化工程標準保護）
```

若使用者加 `--bypass` → 退化為 comment-driven 修正（讀 comments → 改 code → 跑 engineer-delivery-flow），但在 JIRA 留 comment 記錄「revision mode bypassed — no work order」。

### R1. 讀施工圖

讀取 work order（task.md / plan.md），重建原始實作計劃的完整上下文。task.md 欄位讀取走 `scripts/parse-task-md.sh <task_md_path>`（一次取整包 JSON）或 `--field <key>` 抽單欄位（`allowed_files`、`test_command`、`verify_command`、`level` / `env_bootstrap_command` / `runtime_verify_target` / `fixtures` 等 Test Environment 欄位）：
- 改動範圍（`--field allowed_files` 取 Allowed Files、目標行為仍由 LLM 讀 § 目標 段落）
- 測試計畫（`--field test_command` 取單元測試指令；behavioral verify 仍由 LLM 讀 § 行為驗證 / `--field verify_command`）
- AC 驗收標準（以 work order 內的 `ac_verification_ticket` / Operational Context 為準；不要回頭讀 JIRA 補語意）

### R2. 收集 Review Signals

並行取得所有 review signals：

**2a. GitHub Review Comments：**

```bash
gh api repos/{org}/{repo}/pulls/{pr_number}/reviews --paginate
gh api repos/{org}/{repo}/pulls/{pr_number}/comments --paginate
```

**2b. CI Status：**

```bash
gh pr checks {pr_number} --repo {org}/{repo}
```

**2c. 彙整 signal 清單**：將所有 review comments + CI failures 整理成統一清單，每項標註來源（reviewer name / CI job name）。

**2d. Empty-Signal 路由（Rebase-Only Path）**：

若 R2 收集結果為空（所有 review comments 已回覆、CI 全綠、無新 signal），代表這是一次 **rebase-only revision**（常見觸發：QA 回報問題、rebase 後重測、使用者主動要求）。

此時跳過 R3-R4（無 signal 需分類/修正），**直接進入 R5**（重跑完整驗收）。

> **為什麼不能跳過 R5 直接 push**：rebase 會改變 code 的 dependency 版本和 merge 結果。即使 diff 為零，行為可能因 develop 上的新 code 而改變。本地行為驗證是工程師的基本責任，不因「沒改 code」而豁免。

### R3. 比對 & 分類（Classify）

將每個 review signal 與 R1 讀取的施工圖比對，分類為三種：

| 分類 | 定義 | 範例 |
|------|------|------|
| **code drift** | 實作偏離了計劃，但計劃本身是正確的。reviewer 指出的問題在 plan 的 scope 內，是實作沒做好 | 「這裡應該用 composable 而不是 inline」（plan 有寫要用 composable）、CI lint failure、test failure |
| **plan gap** | 計劃本身遺漏了某個 case。reviewer 指出的問題在 plan scope 之外，plan 沒有覆蓋到 | 「這個 edge case 沒處理」（plan 的測試計畫和 AC 都沒提到這個 edge case） |
| **spec issue** | AC / 需求本身有問題。reviewer 質疑的不是實作品質，而是需求方向 | 「這個行為跟 PM 說的不一樣」「為什麼要用 SSR？spec 說 CSR」 |

**分類原則（D2）：不分級，所有 comment 平等**。不區分「純格式」vs「邏輯問題」，全部走比對流程。AI 判錯的代價 >> 多讀一次 plan 的代價。

**Interactive variant（觸發詞：「逐一確認」「interactive」）**：classification 完成後，以**批次清單**展示修正策略給使用者確認，而非逐 comment 確認。互動點在「整體修正策略」：

```
## Revision 修正清單

| # | Signal（來源） | 分類 | 修正策略 |
|---|---------------|------|---------|
| 1 | 「composable 沒用」(reviewer A) | code drift | 重構為 composable pattern |
| 2 | lint: no-unused-vars (CI) | code drift | 移除未使用變數 |
| 3 | 「mobile breakpoint 沒處理」(reviewer B) | plan gap | ⛔ 退回 — plan 未覆蓋 |

code drift 項目將自動修正。plan gap / spec issue 項目需退回上游。
確認？（Y = 執行 / N = 逐項調整分類）
```

### R3a. Plan Gap / Spec Issue 硬擋（D3 + D7）

若 R3 分類結果包含 **plan gap** 或 **spec issue**，**硬擋**：

```
⛔ Revision Mode — 偵測到計劃層級問題

以下 review signal(s) 指向施工圖本身的漏洞，不是實作偏離：

| # | Signal | 分類 | 判定理由 |
|---|--------|------|---------|
| 3 | 「mobile breakpoint 沒處理」(reviewer B) | plan gap | task.md § Allowed Files 未列 mobile 相關檔案；測試計畫無 mobile viewport 項目 |

⚠️ 不在 revision mode 就地補 plan — 那會繞過規劃階段的品質門檻（估點、AC 生成、多角色挑戰）。

建議退回：
  - plan gap → 先跑「breakdown {TICKET}」補充遺漏的 case
  - spec issue → 先跑「refinement {EPIC}」釐清需求

請提供退回理由（「為什麼 plan 會漏這個」），將記錄到 learning queue 供未來規劃改善：
```

等使用者填寫退回理由後：

1. 寫入 learning queue（標籤 `plan-gap`）
   <!-- TODO: Phase 4 實作 learning pipeline 後，此處改為呼叫 learning pipeline API。
        目前先以 JIRA comment 記錄退回理由 + 標籤。 -->
2. 在 JIRA ticket 新增 comment，記錄：退回原因、哪些 review signals 指向 plan gap、使用者填寫的理由
3. 提示使用者手動觸發退回（`/breakdown {TICKET}` 或 `/refinement {EPIC}`）
4. **Revision mode 結束** — 不繼續修 code drift 項目（若有混合分類，code drift 項目等 plan 補完後一起修）

### R4. 執行修正（Code Drift Only）

若 R3 分類結果全部為 **code drift**（或使用者在 interactive mode 確認後），進入修正：

1. **Checkout PR branch**（若尚未在該 branch 上）
2. **依施工圖修正 code** — 每項 code drift 的修正必須對照 plan 的預期行為，不是照 reviewer 的字面建議改：
   - reviewer 說「這裡應該用 X」→ 查 plan 是否規定用 X → 是，則改用 X
   - reviewer 說「加個 null check」→ 查 plan 的 error handling 策略 → 若 plan 規定 throw 而非 null check，以 plan 為準
3. **修正 CI failures** — lint、test、typecheck 失敗視為 code drift，直接修正

### R5. 重跑完整驗收（硬門檻 — 所有 revision path 必經）

**無論走哪條 path（code drift 修正、rebase-only、QA 回報），R5 都是必經步驟。Push 前必須通過行為驗證。**

修正完成後（或 rebase-only 無修正時），重跑 engineer-delivery-flow 機械自驗段（Revision mode R5 不重跑 Phase 3 LLM 實作段，D21）：

讀取 `references/engineer-delivery-flow.md`，以 **Role: Developer** 執行機械自驗段：Step 1.5 Scope Gate → Step 2 前置 Rebase → Step 2 `ci-local.sh` → Step 3 `run-verify-command.sh` → Step 3.5 VR → Step 5 Base Freshness → Step 6 Commit → Step 7 Push（含 Evidence AND Gate）→ Step 8 JIRA → Step 8.5 Completion Gate。
這確保修正後的 code 仍通過所有機械品質門檻。

> **⚠️ Step 2（`ci-local.sh`）在 revision mode 尤其重要**：revision 常見原因就是 CI fail（codecov patch coverage 不足等）。修完後必須重跑 `ci-local.sh` 確認本地模擬 CI 通過，否則 push 後 CI 可能再次失敗。repo root 只要存在 `.claude/scripts/ci-local.sh`（DP-043 路徑；該檔由 generator 產出且 gitignored），revision mode 就沒有豁免。`gate-ci-local.sh` 在 git pre-commit / pre-push 擋 evidence cache miss；`check-delivery-completion.sh` 則在回報完成前再擋一次，避免口頭結案。
>
> **補充**：`gate-ci-local.sh` 會在 git 動作前補位執行，不表示 revision mode 可以跳過 R5 Step 2 再事後合理化。工程流程要求的是「在 flow 內主動跑」，不是「等 hook 抓到再說」。

> 注意：R5 不重新開 PR（PR 已存在），而是在現有 PR 上 push 新 commit（或 rebase-only 時 force-with-lease push）。engineer-delivery-flow 的 Step 7（PR creation）在 revision mode 下改為「確認 PR 已存在 + push force-with-lease」。

### R6. 回覆 Reviewer + Lesson 萃取

**6a. 回覆 GitHub Review Comments：**

對每個已修正的 code drift comment，回覆說明修正內容：

```
Fixed — [簡要說明修正方式 + 對應 plan 的哪個預期行為]
```

回覆語言跟隨 PR description 的主要語言（見 `rules/pr-and-review.md § Review Language`）。

**6b. Review Lesson 萃取：**

<!-- TODO: Phase 4 實作 learning pipeline 後，此處改為呼叫 learning pipeline API。
     目前先以 placeholder 記錄。 -->

掃描本次 revision 中的 code drift 項目，萃取可學習的 pattern：

- 若 drift 涉及 coding convention（命名、結構、pattern 選擇）→ 標籤 `review-lesson`，記入 JIRA comment
- 若 drift 涉及 repo-specific 知識（框架 API、專案架構）→ 直接寫入 repo handbook（`{repo}/.claude/rules/handbook/`）

萃取結果暫時記錄在 JIRA comment 中（格式：`[REVIEW-LESSON] {description}`），待 Phase 4 learning pipeline 上線後自動收割。

---

## Post-Delivery L2 Deterministic Checks

First-cut 的 § 5 交付流程或 Revision mode 的 § R5 重跑跑完、PR 已建立 / 既有 PR 已 push 後，執行下列兩項 advisory 檢查。兩者 exit 0 恆成立（advisory only，不擋 flow），stdout 若有訊息代表 Strategist 要依訊息反思或補動作。

### Step 9 — L2 Deterministic Check: version-bump-reminder

改動若落在 `rules/` 或 `.claude/skills/` 且本次未同步 bump `VERSION`，提醒升版。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-version-bump-reminder.sh" \
  --mode post-pr \
  --base "<PR base branch, e.g. develop or main>" \
  --repo "$CLAUDE_PROJECT_DIR"
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 沒 framework 檔改動或已 bump VERSION，繼續 Step 10
- **exit 0 + 有 stdout** — 提醒使用者「這次改動涉及框架規則/技能，要升版嗎？」依框架升版 chain（VERSION + CHANGELOG + docs-sync + sync-to-polaris）決定是否執行

此 canary 原列 `rules/mechanism-registry.md § Framework Iteration`（behavioral），DP-030 Phase 2C 下放為 deterministic。L1 fallback 由 PostToolUse hook on `git commit`（`.claude/hooks/version-bump-reminder.sh`）補位，當 engineer 繞過本 skill 直接 commit 時仍會觸發。

### Step 10 — L2 Deterministic Check: post-task-feedback-reflection

本 session 若出現自糾正 / 自修 command 之類信號但無新 feedback memory 檔案，提醒反思。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-feedback-signals.sh" \
  --skill engineering
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 無反思訊號，繼續後續收尾
- **exit 0 + 有 stdout** — 依訊息做 `rules/feedback-and-memory.md` 的三層分類（framework / company handbook / repo handbook），決定寫 feedback memory 或更新 handbook

L1 fallback 由 Stop hook（`.claude/hooks/feedback-reflection-stop.sh`）在對話結束時再檢一次，防止 skill flow 中斷或使用者繞過本 skill。

> 兩個 check 都遵循 `skills/references/l2-script-conventions.md` 的 advisory 呼叫約定；exit 0 + stdout 的組合代表「提醒而非阻擋」，不吃 retry budget。

---

## Setup-Only Task 特例（無 code 可 commit）

少數任務（Mockoon fixture 建立、環境設定、dev-only infra）的 deliverable 完全在 workspace gitignore 範圍內 — 跑 delivery flow 會產出空 PR。此時：

1. 確認 task.md 的 Allowed Files 都屬於 gitignored 路徑（`specs/{EPIC}/tests/*`、`.env.local`、fixture JSON 等）
2. 跳過 Step 3.5 之後的 PR 流程
3. 在 JIRA 留 comment 記錄驗證證據（檔案清單、curl PASS 輸出、啟動指令）
4. Transition JIRA 直接到 `完成`（子任務開發完畢 transition）
5. **呼叫 helper 標記 task.md**：`{workspace_root}/scripts/mark-spec-implemented.sh {TICKET}`
6. 清理 task branch（local + remote，無 commit 可 push）

此路徑是例外不是常態 — 若任務有任何 code 會 commit，走標準 delivery flow（Step 8a 會自動呼叫同一 helper）。

## Do / Don't

- Do: 檢查 task.md（新）或 plan.md（legacy）是否存在，無 work order 不開工（除非使用者明確 bypass）
- Do: 開發預設使用 TDD（Red-Green-Refactor），無法寫測試的檔案記錄原因後跳過
- Do: 開發完成後讀取 `references/engineer-delivery-flow.md` 執行完整交付流程（Role: Developer）
- Do: AC 驗證交給 verify-AC skill，PR 開完後使用者或其他 skill 觸發
- Do: Revision mode 中每個修正都對照 plan 的預期行為，不是照 reviewer 字面建議改
- Do: Revision mode plan gap 時硬擋並要求使用者填退回理由
- Do: 把 hook / wrapper 視為 enforcement backup，不是執行流程的替代品
- Do: 若判斷有更短路徑，先向使用者提案並等待同意；未同意前仍照 skill 原流程執行
- Do: 對 task ticket 維持 JIRA write-only 姿態；施工語意以 task.md / plan.md 為準
- Don't: 在 work-on 裡做規劃（估點、拆單、根因分析、AC 生成）— 那是 breakdown/bug-triage 的工作
- Don't: 在 work-on 裡跑 AC 驗證 — 那是 verify-AC 的工作
- Don't: 跳過 Plan Existence Gate（first-cut 和 revision mode 都適用）
- Don't: 跳過 engineer-delivery-flow 直接 commit/push
- Don't: 用「我已經用 targeted tests / patch checker 驗過」取代 skill 明定的 mandatory gate
- Don't: 用「hook 之後會擋」「completion gate 最後會抓」當成前面不執行 gate 的理由
- Don't: 在已命中 engineering / revision mode 時，自行把 mandatory step 降級成 optional
- Don't: 自動決定依賴 branch（一定要確認）
- Don't: 在 QA 流程中的 ticket 上繼續開發
- Don't: 在 revision mode 就地補 plan — plan gap 必須退回上游規劃（D3）
- Don't: 在 revision mode 區分 comment 重要性（純格式 vs 邏輯）— 全部平等走比對流程（D2）
- Don't: 手動修 PR review comments 繞過 revision mode — 所有 PR 修正都走 revision mode（回施工圖比對）

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
