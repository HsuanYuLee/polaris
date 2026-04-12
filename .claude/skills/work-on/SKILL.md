---
name: work-on
description: >
  Execution-only orchestrator: takes a planned JIRA ticket (with existing plan.md or breakdown)
  and implements it — branch, TDD, quality check, verification, PR.
  Supports batch mode via parallel sub-agents.
  Trigger: "做 PROJ-123", "work on", "開始做", "接這張", "做這張",
  or user provides JIRA ticket key(s).
  NOT for planning: Bug → bug-triage first; Story/Task/Epic → breakdown first.
  Key distinction: "下一步" / "繼續" without ticket key → next skill (context auto-detect).
metadata:
  author: Polaris
  version: 3.0.0
---

# Work On — 純施工路由

使用者說「做 PROJ-448」或「做 PROJ-100 PROJ-101 PROJ-102」，skill 檢查規劃產出是否就緒，然後執行實作。規劃（根因分析、拆單、估點、測試計畫）由 `bug-triage` 或 `breakdown` 負責，本 skill 不做規劃。

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
| # | Ticket | Type | Status | Plan | 路由決定 |
|---|--------|------|--------|------|---------|
| 1 | TASK-123 | Task | IN DEV | ✅ plan.md | checkout → 開發 → PR |
| 2 | TASK-123 | Task | 開放 | ✅ plan.md | 轉 IN DEV → 建 branch → 開發 |
| 3 | TASK-123 | Bug | 開放 | ❌ 無 plan | ⛔ 先跑 bug-triage |
| 4 | TASK-123 | Task | QA TESTING | — | ⏭️ 跳過（已進入 QA） |
```

等使用者確認後繼續。無 plan 的 ticket 自動排除，列出需要先跑哪個規劃 skill。

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

## Spec Folder
讀取 `{company_base_dir}/specs/{ticket_key}/plan.md` 取得完整技術方案。
若為 Epic 子單，讀取 `{company_base_dir}/specs/{epic_key}/` 下的相關 task 檔案。

## 流程

依序執行（讀取對應 SKILL.md 了解詳細步驟）：

### 1. 轉 IN DEVELOPMENT + 建 branch
- 讀取 `start-dev` SKILL.md — 設定需求來源、轉狀態
- 讀取 `jira-branch-checkout` SKILL.md — 建 branch
- branch 建立後執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定

### 2. TDD 開發（預設模式）
- 讀取專案 CLAUDE.md — 遵循專案規範
- 讀取 `tdd` SKILL.md — 以 Red-Green-Refactor 循環實作
- **TDD 智慧判斷**：依 `references/tdd-smart-judgment.md` 判斷每個檔案是否走 TDD 循環
- 發現情況不同時，在 JIRA 新增 comment 標註修正版

### 3. 品質檢查 → 行為驗證 → PR（自動銜接，順序不可調換）
- **先跑品質檢查**：讀取 `dev-quality-check` SKILL.md — lint + test + coverage。未通過則先修正
- **品質檢查通過後才跑行為驗證**：讀取 `verify-completion` SKILL.md — 逐張執行 JIRA [驗證] sub-task
- **驗證 Gate**：所有驗證子單必須為「完成」才可繼續。若有 BLOCKED/FAIL → 停止，回傳問題描述
- 驗證全數通過後，讀取 `git-pr-workflow` SKILL.md — **自動執行完整 PR 流程**
- PR 建立後用 MCP tool 轉 JIRA 為 CODE REVIEW

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

在路由之前，確認規劃產出是否就緒。work-on 是純施工 skill，沒有規劃產出就不開工。

**檢查順序：**

1. `{company_base_dir}/specs/{TICKET}/plan.md` 存在？→ 讀取，進入 Step 4
2. Ticket 有 parent Epic？→ `{company_base_dir}/specs/{EPIC}/` 存在？→ 規劃已做，進入 Step 4
3. JIRA description 有結構化技術方案（`## Technical Approach` 或 `## 測試計畫`）？→ 進入 Step 4
4. 以上皆無 → 阻擋，告知使用者需要先做規劃：

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
  └→ 檢查 JIRA comments 是否有依賴標記（base on / depends on）
     └→ 有 → 走依賴分支流程（jira-branch-checkout step 4a-4c）
     └→ 無 → 觸發 jira-branch-checkout（標準流程）
  └→ branch 建立後 → 執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定

ticket 狀態是 IN DEVELOPMENT 且已有 branch？
  └→ checkout 到該 branch
  └→ 執行 `{base_dir}/polaris-sync.sh {project-name}` 部署 AI 設定
  └→ 提示：「已在 branch {name}，可以開始開發。」
```

### 5. 開發摘要 → 自動進入 TDD 開發 → 品質檢查 → 發 PR

路由完成後，顯示開發摘要然後**自動銜接後續流程**（不停下來等使用者）：

```
📋 PROJ-448 — [Feature] Product listing optimization
├─ 狀態：IN DEVELOPMENT
├─ Branch：task/PROJ-448-product-listing-optimization
├─ Base：feat/PROJ-460-aggregate-structured-data
├─ AI 設定：已套用（polaris-sync.sh）
├─ Plan：specs/PROJ-448/plan.md ✅
└─ PR base：feat/PROJ-460-aggregate-structured-data
→ 開始 TDD 開發...
```

**自動銜接流程：**

1. **TDD 開發**：讀取 `tdd` SKILL.md + 專案 CLAUDE.md，以 Red-Green-Refactor 循環實作。依 `references/tdd-smart-judgment.md` 判斷哪些檔案走 TDD
2. **品質檢查 → 行為驗證 → PR**：開發完成後自動讀取 `git-pr-workflow` SKILL.md 執行完整 PR 流程（品質檢查 → verify-completion → Pre-PR Review Loop → Commit → 發 PR → 轉 CODE REVIEW）

> 此流程與批次模式 Phase 2 sub-agent 的 Step 2-3 完全一致，差別只在單張 ticket 由主 agent 直接執行。

## 路由決策表（快速參考）

| Ticket 狀態 | 有 Plan？ | 有 Branch？ | 動作 |
|------------|----------|------------|------|
| 開放 | ✅ | — | 轉 IN DEVELOPMENT → 建 branch → 開發 |
| 開放 | ❌ | — | ⛔ 先跑規劃 skill |
| SA/SD | ✅ | — | 轉 IN DEVELOPMENT → 建 branch → 開發 |
| IN DEVELOPMENT | ✅ | 無 | 建 branch → 開發 |
| IN DEVELOPMENT | ✅ | 有 | checkout branch → 開發 |
| CODE REVIEW | — | 有 | 提示修 review 或等 merge |
| QA 以後 | — | — | 提示無需開發 |
| Epic（有子單） | — | — | 列出子單讓使用者選 |
| Epic（無子單） | — | — | 先跑拆單 |

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

- Do: 檢查 plan.md 是否存在，無 plan 不開工（除非使用者明確 bypass）
- Do: 每個路由決策前都向使用者確認
- Do: 路由到其他 skill 時使用 Skill tool 觸發
- Do: 開發預設使用 TDD（Red-Green-Refactor），無法寫測試的檔案記錄原因後跳過
- Do: 先跑 dev-quality-check，通過後再跑 verify-completion。**順序不可調換**
- Do: 驗證全數通過後**自動銜接 git-pr-workflow 發 PR**
- Do: verify-completion 逐項驗證每張 JIRA [驗證] 子單，**全部通過才可 commit/push**
- Don't: 在 work-on 裡做規劃（估點、拆單、根因分析、AC 生成）— 那是 breakdown/bug-triage 的工作
- Don't: 跳過 Plan Existence Gate
- Don't: 跳過品質檢查直接做行為驗證
- Don't: 跳過行為驗證直接 commit/push
- Don't: 自動決定依賴 branch（一定要確認）
- Don't: 在 QA 流程中的 ticket 上繼續開發

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
