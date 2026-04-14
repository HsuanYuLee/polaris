---
name: engineering
description: >
  Engineer-minded execution orchestrator: takes a planned JIRA ticket and implements it with strict quality discipline — TDD, lint, typecheck, test, behavioral verify, PR.
  Supports batch mode via parallel sub-agents.
  Trigger: "做 PROJ-123", "work on", "engineering", "開始做", "接這張", "做這張",
  or user provides JIRA ticket key(s).
  NOT for planning: Bug → bug-triage first; Story/Task/Epic → breakdown first.
  Key distinction: "下一步" / "繼續" without ticket key → next skill (context auto-detect).
tier: product
metadata:
  author: Polaris
  version: 4.0.0
---

# Engineering — 工程師施工

使用者說「做 PROJ-448」或「做 PROJ-100 PROJ-101 PROJ-102」，engineering skill 以工程師標準執行：品質檢查是確定性 gate（不是可跳過的步驟）、scope 變更需要理由、CI 全綠才能開 PR。規劃（根因分析、拆單、估點、測試計畫）由 `bug-triage` 或 `breakdown` 負責，本 skill 不做規劃。

## Pipeline 角色

本 skill 是 pipeline 的 **Execution** 環節（見 [pipeline-handoff.md](../references/pipeline-handoff.md)）。上游 breakdown 已打包出 self-contained task.md work order；本 skill 消費 **codebase + task.md + handbook（自動載入）**，不再回頭讀 breakdown.md / refinement.md。

**輸入優先順序**：
1. `specs/{EPIC}/tasks/T{n}.md` — breakdown v2 產出（新 pipeline 的主要輸入）
2. `specs/{TICKET}/plan.md` — legacy 格式（過渡期 fallback；P5 cutover 後移除）

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 0. 批次偵測

解析使用者輸入，提取所有 JIRA ticket key（格式：`[A-Z]+-\d+`）。

- **1 個 ticket** → 跳至 Step 1 正常流程
- **2 個以上** → 進入批次模式

### 批次模式 — 兩階段執行

分為 **Phase 1（路由）** 和 **Phase 2（實作）**，中間有使用者確認點。

---

### Phase 1：平行路由（輕量，不做分析）

**1a. 平行取得所有 ticket 的 JIRA 資訊**（直接用 MCP tool，不需 sub-agent）：

每張 ticket 並行呼叫：
- `getJiraIssue`（summary, status, issuetype, description, comment）
- `searchJiraIssuesUsingJql`（查子單：`parent = <TICKET>`）
- `gh pr list --search "<TICKET>" --state open`

**1b. Plan Existence Check**（每張 ticket）：

對每張 ticket 檢查規劃產出是否存在（見 § Plan Existence Gate）。

**1c. 呈現路由總覽表**：

```
| # | Ticket | Type | Status | Work Order | 路由決定 |
|---|--------|------|--------|-----------|---------|
| 1 | TASK-123 | Task | IN DEV | ✅ task.md | checkout → 開發 → PR |
| 2 | TASK-123 | Task | 開放 | ✅ task.md | 轉 IN DEV → 建 branch → 開發 |
| 3 | TASK-123 | Task | IN DEV | ✅ plan.md (legacy) | checkout → 開發 → PR |
| 4 | TASK-123 | Bug | 開放 | ❌ 無 work order | ⛔ 先跑 bug-triage |
| 5 | TASK-123 | Task | QA TESTING | — | ⏭️ 跳過（已進入 QA） |
```

等使用者確認後繼續。無 work order 的 ticket 自動排除，列出需要先跑哪個規劃 skill。

### Phase 1.5：API Contract Check（if fixtures involved）

若當前 ticket 涉及的頁面有 Mockoon fixtures，在實作前跑 contract check（見 `references/api-contract-guard.md`）：

```bash
scripts/contract-check.sh --env-dir <mockoon-environments-dir> --epic <epic>
```

- Exit 0 → 繼續 Phase 2
- Exit 1（breaking drift）→ 顯示差異報告，提醒使用者先更新 fixture + 型別定義
- Exit 2 → warn，繼續

### Phase 2：平行實作

**2a. 篩選可實作的 ticket**：

| 情境 | 處理方式 |
|------|---------|
| Bug / Story / Task（有 plan） | ✅ 進入 Phase 2 |
| Epic | ❌ 不進入 — 使用者選要做的子單 |
| 同 repo 的多張 ticket | 使用 `isolation: "worktree"` 隔離 |
| 跨 repo 的 ticket | 直接平行，不需 worktree |

**2b. 為每個 ticket 啟動 Phase 2 sub-agent**（平行，同 repo 用 worktree）：

每個 sub-agent 的 prompt：

```
你是開發 agent。完成以下 JIRA ticket 的實作，從建 branch 到發 PR。

## Ticket
{ticket_key}: {summary}
Type: {issue_type}
Project: {base_dir}/{repo}（base_dir 從 workspace-config.yaml 取得）

## Work Order（唯一輸入來源）

依優先順序定位並讀取：
1. **新格式（優先）** — 以 JIRA key 定位 task.md：
   ```bash
   grep -lE "^> .*JIRA: {ticket_key}\b" {company_base_dir}/specs/{epic_or_ticket}/tasks/T*.md
   ```
   命中的檔案即本 task 的 work order（schema 見 `skills/references/pipeline-handoff.md § task.md Schema`）
2. **Legacy fallback**：`{company_base_dir}/specs/{ticket_key}/plan.md`
   — 過渡期舊格式，P5 cutover 後移除

task.md / plan.md 已 self-contained（含目標、改動範圍、測試計畫、references 清單）。
**不要回頭讀 breakdown.md / refinement.md / INDEX.md**；handbook 自動載入。

## 流程

依序執行（讀取對應 SKILL.md 了解詳細步驟）：

### 1. 轉 IN DEVELOPMENT + 建 branch
- 讀取 `start-dev` SKILL.md — 設定需求來源、轉狀態
- 依 `references/branch-creation.md` 流程建 branch（或使用 `scripts/create-branch.sh`）
- branch 建立後執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定

### 2. TDD 開發（預設模式）
- 讀取專案 CLAUDE.md — 遵循專案規範
- 讀取 `unit-test` SKILL.md — 以 Red-Green-Refactor 循環實作
- **TDD 智慧判斷**：依 `references/tdd-smart-judgment.md` 判斷每個檔案是否走 TDD 循環
- 發現情況不同時，在 JIRA 新增 comment 標註修正版

### 3. 交付流程（quality → behavioral verify → PR）
- 讀取 `references/engineer-delivery-flow.md`，以 **Role: Developer** 執行 Step 1-8
- 流程包含：Simplify → Quality Check → Behavioral Verify (Layer A + Layer B) → Pre-PR Review → Rebase → Commit → PR → JIRA transition
- **AC 驗證由 verify-AC skill 接手**：work-on 不跑 AC 驗證。PR 開完後使用者跑「驗 {EPIC}」或 opportunistic 偵測觸發

### 4. 回傳結果
回傳：ticket key、branch name、PR URL、品質檢查摘要、測試計畫驗證結果。

## 限制
- 你無法使用 Skill tool，改為讀取 SKILL.md 並直接執行步驟
- 用 Read tool 讀本地檔案，不要用 gh api repos/.../contents/
- 品質檢查未通過 → 先修正再發 PR
- 估點變動 > 30% → 停止實作，回傳問題描述
- 不要 self-review 自己建立的 PR
```

**2c. 收集結果，呈現統一報告**：

```
## 批次實作報告

| # | Ticket | Branch | PR | JIRA 狀態 |
|---|--------|--------|----|----------|
| 1 | TASK-123 | task/TASK-123-fix-xxx | #100 ✅ | CODE REVIEW |
| 2 | TASK-123 | task/TASK-123-add-xxx | #101 ✅ | CODE REVIEW |
| 3 | TASK-123 | — | — ⚠️ | 估點變動 > 30%，需確認 |
```

**結果驗證**：檢查每個「完成」的 ticket 是否包含有效的 PR URL。若 sub-agent 回報完成但無 PR URL → 標記為 ⚠️。

**批次摘要統計**（表格下方）：

```
### 總結
- ✅ 完成：N/{total} 張（PR 已開）
- ⚠️ 待處理：M 張（列出原因）
- 總估點：X 點
```

---

若只有 **1 個 ticket**，進入下方正常流程：

## Workflow

### 1. 解析 Ticket Key

從使用者輸入中提取 JIRA ticket key（如 `PROJ-448`、`TEAM-1234`）。

### 2. 收集 Ticket 狀態

並行取得所有需要的資訊：

**2a. 讀取 JIRA ticket：**

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
  fields: ["summary", "status", "issuetype", "comment"]
```

**2b. 查詢子單（Epic/Story 才需要）：**

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: parent = <TICKET>
  fields: ["summary", "status", "issuetype"]
```

**2c. 查詢是否有對應的 branch/PR：**

```bash
gh pr list --search "<TICKET>" --state open --json headRefName,number,title --limit 5
git branch --list "*<TICKET>*"
```

### 3. Plan Existence Gate

在路由之前，確認規劃產出（work order）是否就緒。work-on 是純施工 skill，沒有 work order 就不開工。

**檢查順序（優先取新格式）：**

1. **新格式** — 以 JIRA key 定位 task.md（task.md header 內建 `> JIRA: {TASK_KEY}` mapping）：
   - 判斷搜尋範圍：有 parent Epic → `specs/{EPIC}/tasks/`；否則 → `specs/{TICKET}/tasks/`
   - 執行：`grep -lE "^> .*JIRA: {TICKET}\b" {company_base_dir}/specs/{EPIC_OR_TICKET}/tasks/T*.md`
   - 命中單一檔案 → 讀取，進入 Step 4（新 pipeline 主要路徑）
   - 命中多個 → 異常，停下來告知使用者（同一 JIRA key 不該對應多張 task.md）
2. **Legacy fallback** — `{company_base_dir}/specs/{TICKET}/plan.md` 存在？→ 讀取，進入 Step 4
3. **舊 breakdown 產出** — 有 parent Epic 且 `{company_base_dir}/specs/{EPIC}/` 存在（無 tasks/ 子目錄）？→ 讀取 Epic 下相關檔案，進入 Step 4
4. **JIRA 內嵌方案** — description 有結構化技術方案（`## Technical Approach` 或 `## 測試計畫`）？→ 進入 Step 4
5. 以上皆無 → 阻擋，告知使用者需要先做規劃：

```
⛔ Plan Existence Gate — 找不到規劃產出

此 ticket 尚未經過規劃，work-on 需要 plan 才能開始施工。

建議：
{Bug}    → 先跑「bug-triage {TICKET}」進行根因分析和規劃
{Story/Task} → 先跑「breakdown {TICKET}」進行拆單和規劃
{Epic}   → 先跑「拆單 {TICKET}」進行 Epic 拆解
```

**例外：使用者明確說「直接做，不用規劃」** → 跳過 gate，但在 JIRA 留 comment 記錄「未經規劃直接實作」。

### 4. 判斷狀態並路由

根據收集到的資訊，依決策樹選擇下一步：

```
ticket 狀態是 CODE REVIEW？
  └→ 提示：「這張在 Code Review，要修 review comments 嗎？」
     └→ 是 → 觸發 fix-pr-review
     └→ 否 → 結束

ticket 狀態是 QA TESTING / WAITING FOR STAGE / REGRESSION / WAITING FOR RELEASE？
  └→ 提示：「這張已進入 QA 流程（{狀態}），無需開發。」→ 結束

ticket 類型是 Epic 且沒有子單？
  └→ 「這張 Epic 還沒拆單，先跑「拆單 {TICKET}」。」→ 結束

ticket 類型是 Epic 且有子單？
  └→ 列出 Epic 摘要 + 所有子單狀態表
     詢問：「要做哪張子單？」
     └→ 使用者選子單 → 對該子單重新走 Step 2-3

ticket 狀態是「開放」或「SA/SD」？
  └→ 觸發 start-dev → 繼續建 branch

ticket 狀態是 IN DEVELOPMENT 且沒有 branch？
  └→ **AC-FAIL Bug 偵測**：ticket description 或 comment 含 `[VERIFICATION_FAIL]`？
     └→ 是 → 從 [VERIFICATION_FAIL] block 擷取「分析對象 branch」（feature_branch_name）→ 作為 base branch → 開 fix branch `task/{BUG_KEY}-{slug}` from feature_branch_name（不是 develop）
     └→ 否 → 檢查 JIRA comments 是否有依賴標記（base on / depends on）
         └→ 有 → 走依賴分支流程（references/branch-creation.md § dependency branch）
         └→ 無 → 依 references/branch-creation.md 建 branch（或使用 scripts/create-branch.sh）
  └→ branch 建立後 → 執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定

ticket 狀態是 IN DEVELOPMENT 且已有 branch？
  └→ checkout 到該 branch
  └→ 執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定
  └→ 提示：「已在 branch {name}，可以開始開發。」
```

### 5. 開發摘要 → 自動進入 TDD 開發 → 交付流程

路由完成後，顯示開發摘要然後**自動銜接後續流程**（不停下來等使用者）：

```
📋 PROJ-448 — [Feature] Product listing optimization
├─ 狀態：IN DEVELOPMENT
├─ Branch：task/PROJ-448-product-listing-optimization
├─ Base：feat/PROJ-460-aggregate-structured-data
├─ AI 設定：已套用（polaris-sync.sh）
├─ Work Order：specs/PROJ-460/tasks/T3.md ✅（或 legacy specs/PROJ-448/plan.md）
└─ PR base：feat/PROJ-460-aggregate-structured-data
→ 開始 TDD 開發...
```

**自動銜接流程：**

1. **TDD 開發**：讀取 `unit-test` SKILL.md + 專案 CLAUDE.md，以 Red-Green-Refactor 循環實作。依 `references/tdd-smart-judgment.md` 判斷哪些檔案走 TDD
2. **交付流程**：開發完成後讀取 `references/engineer-delivery-flow.md`，以 **Role: Developer** 執行 Step 1-8（Simplify → Quality Check → Behavioral Verify Layer A+B → Pre-PR Review → Rebase → Commit → PR → JIRA transition）。**AC 驗證不在本 skill**，PR 開完後由 verify-AC 接手

> 此流程與批次模式 Phase 2 sub-agent 的 Step 2-3 完全一致，差別只在單張 ticket 由主 agent 直接執行。

## 路由決策表（快速參考）

| Ticket 狀態 | 有 Work Order？ | 有 Branch？ | 動作 |
|------------|-----------------|------------|------|
| 開放 | ✅ task.md / plan.md | — | 轉 IN DEVELOPMENT → 建 branch → 開發 |
| 開放 | ❌ | — | ⛔ 先跑規劃 skill |
| SA/SD | ✅ | — | 轉 IN DEVELOPMENT → 建 branch → 開發 |
| IN DEVELOPMENT | ✅ | 無 | 建 branch → 開發 |
| IN DEVELOPMENT | ✅ | 有 | checkout branch → 開發 |
| CODE REVIEW | — | 有 | 提示修 review 或等 merge |
| QA 以後 | — | — | 提示無需開發 |
| Epic（有子單） | — | — | 列出子單讓使用者選 |
| Epic（無子單） | — | — | 先跑拆單 |

「Work Order」= `specs/{EPIC}/tasks/T{n}.md`（新）或 `specs/{TICKET}/plan.md`（legacy）。

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

## Do / Don't

- Do: 檢查 task.md（新）或 plan.md（legacy）是否存在，無 work order 不開工（除非使用者明確 bypass）
- Do: 每個路由決策前都向使用者確認
- Do: 路由到其他 skill 時使用 Skill tool 觸發
- Do: 開發預設使用 TDD（Red-Green-Refactor），無法寫測試的檔案記錄原因後跳過
- Do: 開發完成後讀取 `references/engineer-delivery-flow.md` 執行完整交付流程（Role: Developer）
- Do: AC 驗證交給 verify-AC skill，PR 開完後使用者或其他 skill 觸發
- Don't: 在 work-on 裡做規劃（估點、拆單、根因分析、AC 生成）— 那是 breakdown/bug-triage 的工作
- Don't: 在 work-on 裡跑 AC 驗證 — 那是 verify-AC 的工作
- Don't: 跳過 Plan Existence Gate
- Don't: 跳過 engineer-delivery-flow 直接 commit/push
- Don't: 自動決定依賴 branch（一定要確認）
- Don't: 在 QA 流程中的 ticket 上繼續開發

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
