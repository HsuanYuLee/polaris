---
name: work-on
description: >
  Smart orchestrator that detects JIRA ticket state and routes to the right next step
  (estimate, breakdown, branch, or coding). Single entry point for working on tickets.
  Supports batch mode via parallel sub-agents. Trigger: "做 PROJ-123", "work on",
  "開始做", "接這張", "做這張", "估點", "estimate", "幫我估",
  or user provides JIRA ticket key(s). NOT for single bug fix ("修 bug" → fix-bug).
  Key distinction: "下一步" / "繼續" without ticket key → next skill (context auto-detect).
metadata:
  author: Polaris
  version: 2.4.0
---

# Work On — 智慧開發路由

使用者只需要說「做 PROJ-448」或「做 PROJ-100 PROJ-101 PROJ-102」，skill 自動判斷 ticket 狀態並執行對應步驟。多張 ticket 時自動進入批次模式，以 sub-agent 平行處理。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 0. 批次偵測

解析使用者輸入，提取所有 JIRA ticket key（格式：`[A-Z]+-\d+`）。

- **1 個 ticket** → 跳至 Step 1 正常流程
- **2 個以上** → 進入批次模式

### 批次模式 — 兩階段執行

分為 **Phase 1（分析）** 和 **Phase 2（實作）**，中間有使用者確認點，解決多單平行時的互動問題。

---

### Phase 1：平行分析

**1a. 平行取得所有 ticket 的 JIRA 資訊**（直接用 MCP tool，不需 sub-agent）：

每張 ticket 並行呼叫：
- `getJiraIssue`（summary, status, issuetype, description, comment）
- `searchJiraIssuesUsingJql`（查子單：`parent = <TICKET>`）
- `gh pr list --search "<TICKET>" --state open`

**1b. 呈現路由總覽表**：

```
| # | Ticket | Type | Status | Project | 路由決定 |
|---|--------|------|--------|---------|---------|
| 1 | PROJ-100 | Bug | 開放 | repo-a | 根因分析 → 估點 → 開發 → PR |
| 2 | PROJ-101 | Story | IN DEV | repo-a | 已有 branch → 估點 → 開發 |
| 3 | PROJ-300 | Epic | 開放 | repo-b | 拆單估點 |
| 4 | PROJ-400 | Task | QA TESTING | — | ⏭️ 跳過（已進入 QA 流程） |
```

等使用者確認後繼續。使用者可在此排除特定 ticket。

**1c. 為每個需要分析的 ticket 啟動 Phase 1 sub-agent**（平行）：

每個 sub-agent 的 prompt：

```
你是 JIRA ticket 分析 agent。分析以下 ticket 並回傳結果，**不要修改任何檔案、不要建立 JIRA issue、不要建 branch**。

## Ticket
{ticket_key}: {summary}
Type: {issue_type}
Description: {description}

## 專案路徑
{base_dir}/{repo}（base_dir 從 workspace-config.yaml 取得）

## 分析指示

### Codebase 探索
先讀取 `skills/references/explore-pattern.md`，使用自適應探索模式掃描 codebase。探索目標依 issue type 而定（見下方）。探索摘要取得後，再進入估點分析。

### 估點參考
讀取以下 skill 檔案，遵循其中的**分析/估點步驟**（僅分析，不執行寫入操作）：
- 讀取 `jira-estimation` SKILL.md
- `skills/references/estimation-scale.md`

{根據 issue type 附加對應指示：}

### Bug
探索目標：從 bug 描述追蹤相關程式碼，找出可疑的根因位置。
分析 codebase 找出根因（具體檔案和行號），以 Root Cause + Solution + 估點格式回傳。

### Story / Task
探索目標：找出與需求相關的檔案，評估改動複雜度和影響範圍。
依 estimation SKILL.md 的 Step 8 分析程式碼、撰寫子單 description（SASD 格式）。
回傳：估點、子單拆分表格（含 description 全文）、依賴關係。

### Epic
探索目標：找出與 Epic 相關的現有程式碼結構，識別可複用模組和依賴順序。
讀取 `epic-breakdown` SKILL.md 並遵循其分析流程。
回傳：拆單表格、每張子單估點和 description。

## 限制
- 只做 research（Read tool、本地 git 指令），不要編輯檔案
- 用本地 repo 讀取程式碼，不要用 gh api repos/.../contents/
- 回傳完整分析結果文字，主 agent 會彙整給使用者
```

**1d. 彙整分析報告**：

收集所有 sub-agent 結果，呈現統一報告：

```
## 批次分析報告

### 1. PROJ-100 (Bug) — repo-a — 建議 3 點
**Root Cause:** ...
**Solution:** ...

### 2. PROJ-101 (Story) — repo-a — 建議 5 點
| # | 子單 Summary | Points | 依賴 |
|---|-------------|--------|------|
| 1 | ... | 2 | — |
| 2 | ... | 3 | #1 |

### 3. PROJ-300 (Epic) — &lt;design-system&gt; — 建議 13 點
（拆單表格...）
```

**使用者逐一或整體確認**，可調整估點、修改子單、排除 ticket。

**1e. 持久化 Design Doc**

確認後、JIRA 寫入前，為每張確認的 ticket 寫一份 design doc：

```
路徑: {base_dir}/{repo}/.claude/designs/{TICKET-KEY}.md
```

內容從確認後的分析結果提取（不重新分析）：

```markdown
# {TICKET-KEY}: {Summary}

## Context
- Type: {Bug/Story/Task/Epic}
- Repo: {repo_path}
- Base branch: {base_branch or "TBD"}
- Created: {today's date}

## Technical Approach
{Phase 1 sub-agent 分析精華：Root Cause/Solution (Bug) 或 影響檔案 + approach (Story/Task)}

## Sub-tasks
{拆出的子單列表 + 估點，如有}

## Decisions
（開發過程中 T2 taste calls 記錄於此 — 初始為空）
```

此檔案供 Phase 2 sub-agent 讀取（取代 inline 傳遞全文），也供 cross-session resume 使用。`.claude/designs/` 應在 `.gitignore` 中。

確認後，批次執行 JIRA 寫入（可用 sub-agent 平行，`model: "haiku"` — 純 JIRA 模板操作）：
- Bug → 留 JIRA comment + 更新估點
- Story/Task → 建立子單 + 更新估點
- Epic → 建立子單 + 更新估點

---

### Phase 1.5：API Contract Check（if fixtures involved）

若當前 ticket 涉及的頁面有 Mockoon fixtures，在實作前跑 contract check（見 `references/api-contract-guard.md`）：

```bash
scripts/contract-check.sh --env-dir <mockoon-environments-dir> --epic <epic>
```

- Exit 0 → 繼續 Phase 2
- Exit 1（breaking drift）→ 顯示差異報告。Breaking change 可能影響實作方向（型別、欄位名）。提醒使用者先更新 fixture + 型別定義
- Exit 2 → warn，繼續

### Phase 2：平行實作

**2a. 篩選可實作的 ticket**：

| 情境 | 處理方式 |
|------|---------|
| Bug / Story / Task（已確認分析） | ✅ 進入 Phase 2 |
| Epic | ❌ 不進入 — 使用者選擇要做的子單後，子單才進入 Phase 2 |
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

## Design Doc
讀取 `{base_dir}/{repo}/.claude/designs/{ticket_key}.md` 取得完整技術方案。

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
- **先跑品質檢查**：讀取 `dev-quality-check` SKILL.md — lint + test + coverage。品質檢查是自動化快速回饋，幾秒到幾分鐘就有結果。未通過則先修正，不進入行為驗證
- **品質檢查通過後才跑行為驗證**：讀取 `verify-completion` SKILL.md — 逐張執行 JIRA [驗證] sub-task。每張子單獨立：執行驗證 → 在該子單留 comment（含測試環境、驗證項目、結果）→ 轉狀態（開放 → IN DEVELOPMENT → 完成/BLOCKED）。行為驗證需要啟動服務（dev server、Mockoon 等），setup 成本較高，品質檢查沒過就做行為驗證是白費功夫
- **驗證 Gate**：所有驗證子單必須為「完成」才可繼續。若有 BLOCKED/FAIL → 停止，回傳問題描述
- 驗證子單全數通過後，讀取 `git-pr-workflow` SKILL.md — **自動執行完整 PR 流程**（不等使用者指示）
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
| 1 | PROJ-100 | task/PROJ-100-fix-xxx | #100 ✅ | CODE REVIEW |
| 2 | PROJ-101 | task/PROJ-101-add-xxx | #101 ✅ | CODE REVIEW |
| 3 | PROJ-300-1 | — | — ⚠️ | 估點變動 > 30%，需確認 |
```

**結果驗證**：收集 sub-agent 回傳時，檢查每個「完成」的 ticket 是否包含有效的 PR URL（`https://github.com/...`）。若 sub-agent 回報完成但無 PR URL → 標記為 ⚠️ 待處理（git-pr-workflow 可能被跳過或提前中斷）。

若有 sub-agent 回報問題（估點變動、技術難題、品質檢查失敗、無 PR URL），列出待處理事項讓使用者決定。

**批次摘要統計**（表格下方附上）：

```
### 總結
- ✅ 完成：N/{total} 張（PR 已開）
- ⚠️ 待處理：M 張（列出每張的原因：估點變動 / 品質檢查失敗 / 技術難題）
- 總估點：X 點（已完成 Y 點 / 待處理 Z 點）
```

摘要讓使用者一眼掌握批次進度，不需逐行看表格。Phase 1 分析報告（1d）也附同樣格式的摘要。

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
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  fields: ["summary", "status", "issuetype", "comment"]
```

**2b. 查詢子單（Epic/Story 才需要）：**

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: parent = <TICKET>
  fields: ["summary", "status", "issuetype"]
```

**2c. 查詢是否有對應的 branch/PR：**

```bash
gh pr list --search "<TICKET>" --state open --json headRefName,number,title --limit 5
git branch --list "*<TICKET>*"
```

### 3. Readiness Gate — Ticket 品質檢查

讀取 JIRA ticket 後、進入路由/估點前，檢查 ticket 品質。**Bug 類型**和**已進入 QA 以後狀態**的 ticket 跳過此 gate。

**3a. 大 scope 偵測 — 自動跑 refinement**

以下任一條件符合 → 直接用 Skill tool 執行 `/refinement`（Phase 1），refinement 完成後回到 work-on 繼續：

- Issue type = **Epic**（所有 Epic 強制過 refinement）
- Description 提及**跨專案**改動（同時涉及 DS + B2C、或多個 repo）
- Description 提及 **3 個以上獨立功能或頁面**

> 偵測方式：掃描 description 中的專案關鍵字（參照 CLAUDE.md 專案 Mapping 表）和功能/頁面列舉。若 Epic 已有 `refinement-ready` label，跳過此步（已做過 refinement）。

**3b. 最低門檻檢查（非大 scope 的 Story/Task）**

3 項全過才放行，缺項則阻擋：

| # | 項目 | 合格標準 | 不合格範例 |
|---|------|---------|-----------|
| 1 | Summary | 明確描述目標功能或改動 | 「優化」「改善」「調整」（過於模糊） |
| 2 | AC / 完成條件 | 至少 1 條可驗證的條件 | 無 AC、或只有「改善使用者體驗」 |
| 3 | Scope | 可辨識哪個專案、哪個區域 | 無 description、或 description 沒提到具體頁面/元件 |

**缺項處理**：列出缺少的項目和建議內容格式，要求使用者在對話中補齊。補齊後用 `addCommentToJiraIssue` 寫回 JIRA（持久化），才繼續下一步。

```
⚠️ Readiness Gate — 缺項
  ❌ AC：缺少可驗證的完成條件
  ❌ Scope：無法辨識涉及的專案和區域

請補齊以下資訊：
1. AC（至少 1 條）：格式「{操作/條件} → {預期結果}」
2. Scope：涉及哪個專案的哪些頁面/元件

補齊後我會寫回 JIRA，再繼續流程。
```

**3c. AC 品質驗證（AC 存在時也要驗）**

即使 AC 存在，檢查每條 AC 是否符合品質標準：

| 品質維度 | ✅ 合格 | ❌ 不合格 |
|---------|--------|---------|
| 可驗證 | 「API timeout > 3s → 顯示 skeleton + retry 按鈕」 | 「處理錯誤」 |
| 有邊界 | 「選擇日期後，價格區塊在 300ms 內更新」 | 「價格要即時更新」 |
| 不含實作細節 | 「切換幣別後顯示對應價格」 | 「用 Vue watch 監聽幣別變更」 |

不合格的 AC → 列出具體問題和改寫建議，要求使用者修正後回覆。修正後寫回 JIRA comment。

> Readiness Gate 是阻擋性的——缺項或 AC 品質不合格時，不會跳過繼續，必須補齊才能往下走。

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
  └→ 詢問：「這張 Epic 還沒拆單，要先估點拆單嗎？」
     └→ 是 → 觸發 epic-breakdown
     └→ 否 → 繼續下一步

ticket 類型是 Epic 且有子單？
  └→ 列出 Epic 摘要 + 所有子單狀態表（開放/IN DEV/CODE REVIEW/QA+/有無 PR）
     詢問：「要做哪張子單？還是整張 Epic 重走新流程（refinement → 拆單 → AC 追溯）？」
     ├→ 使用者選子單 → 對該子單重新走 Step 2-3
     └→ 使用者說重走 →
        1. 標記有 open PR 的子單（保留，PR merge 後再處理）
        2. 批次關閉無 PR 的子單（transitionJiraIssue → 已關閉，
           留 comment「Epic 重走新流程」）
        3. 移除 `refinement-ready` label（如有）
        4. 對 Epic 執行 Readiness Gate（Step 3）→ refinement → breakdown

ticket 狀態是「開放」或「SA/SD」？
  └→ 提示目前狀態，詢問：「要轉 IN DEVELOPMENT 並建 branch 嗎？」
     └→ 是 → 觸發 start-dev → 繼續建 branch

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

### 5. AC Gate — 確保測試計畫存在並建立驗證子單

路由完成、準備進入開發前，檢查 ticket 是否有足夠的 AC 和測試計畫。**每張 ticket 進開發前都必須通過此 gate。**

> Step 3 Readiness Gate 已確保 AC 存在且品質合格。此步驟將 AC 轉化為可追蹤的測試計畫和 JIRA 驗證子單。

**5a. 檢查 description 中是否有測試計畫**

讀取 ticket description（Step 2a 已取得），尋找 `## 測試計畫` / `## 測試計劃` / `## Test Plan`
section 下的 checklist items（`- [ ] ...`）。

**分支：**

- **有測試計畫** → 跳至 5d
- **沒有測試計畫** → 進入 5b 自動補上

**5b. 自動生成 AC + 測試計畫（無測試計畫時）**

分析 ticket description + codebase（用 Explore subagent 快速掃描涉及的檔案），生成：

1. **AC（驗收條件）**：從需求推導出具體的驗收標準
2. **測試計畫**：使用者視角的操作步驟 + 預期結果，格式為 `- [ ]` checklist

參考 TEAM-1001 的結構化 description 格式：

```markdown
## 測試計畫

- [ ] {使用者操作} → {預期結果}
- [ ] {邊界場景} → {預期行為}
- [ ] {效能/cache 驗證} → {確認方式}
```

**5c. 寫回 JIRA description**

將生成的 AC + 測試計畫**追加**到 ticket description 末尾（不覆蓋既有內容）：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  fields:
    description: <原始 description + 追加的 AC 和測試計畫>
  contentFormat: markdown
```

回報使用者：

```
📋 AC Gate — 已補上測試計畫（N 項）
  - [ ] 項目 1
  - [ ] 項目 2
  ...
已寫回 JIRA description。
```

**5d. 檢查是否已有驗證子單**

查詢 JIRA 是否已有 `[驗證]` 子單（避免重複建立）：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: parent = <TICKET> AND summary ~ "驗證"
  fields: ["summary", "status"]
  maxResults: 20
```

若已有子單且數量與測試計畫項目一致 → 跳過建立，直接進 Step 6。
若無子單或數量不足 → 為缺少的項目建立子單。

**5e. 批次建立 [驗證] sub-task**

> 前置：先依 `references/jira-story-points.md` Step 0 探測 Story Points 欄位 ID（若本 session 尚未探測）。

為每個測試計畫項目建立 JIRA sub-task，平行呼叫 `createJiraIssue`：

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  projectKey: <PROJECT>
  issueTypeName: 子任務
  parent: <TICKET>
  summary: "[驗證] <test plan item>"
  assignee_account_id: <當前使用者 accountId>
```

建完後，**立即為每張驗證子單設定 Story Points**（平行呼叫 `editJiraIssue`）：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <新建的驗證子單 key>
  fields:
    <storyPointsFieldId>: 1   # 每張驗證子單 1 pt
```

> 估點規則：per-AC 驗證子單 = 1 pt；若合併多條 AC 為一張 → ≤ 3 AC = 1 pt，> 3 AC = 2 pt。

建完後列出所有驗證子單連結（含點數）。

**5f. 🔍 QA Challenge — 自動解決循環（must-respond）**

驗證子單建完後，啟動 **QA 自動解決循環**（不需使用者逐條回應）：

**Round 1 — Challenge：**
Dispatch **QA Challenger** sub-agent（見 `skills/references/sub-agent-roles.md`）：
- **輸入**：測試計畫全文 + 驗證子單清單 + ticket AC + risk areas
- **Model**：sonnet
- **輸出**：挑戰報告（⚠️ 需回應 + ✅ 涵蓋完整）

**Round N — Resolve + Re-Challenge 循環：**
若有 ⚠️ 項目，dispatch **QA Resolver** sub-agent（同 sonnet）自動處理：

1. **Resolver pass**：對每個 ⚠️ 提出具體解決方案（更新驗證標準、補充步驟、或附理由駁回）
2. **Challenger pass**：重新審視所有解決方案，標記 ✅（resolved）或 ⚠️（仍有 gap）
3. 仍有 ⚠️ → 再一輪 Resolve + Challenge
4. 全部 ✅ → 循環結束

**循環終止條件**：
- 所有項目 ✅ → 正常結束
- 超過 3 輪仍有 ⚠️ → 將剩餘 ⚠️ 提交使用者決策

**結果處理：**
- 循環結束後，呈現**最終穩定測試計畫**給使用者確認（整體確認，非逐條回應）
- **新增項目**（Challenge 中發現的 missing scenarios，且被 Resolver 接受的）→ 建立額外的 [驗證] sub-task
- **被駁回的項目** → 記錄理由，不新增

使用者確認穩定測試計畫後才進入開發。

### 5g. 持久化 Design Doc（單張 ticket 模式）

AC Gate 結束後、進入開發前，寫一份 design doc 持久化技術方案：

```
路徑: {base_dir}/{repo}/.claude/designs/{TICKET-KEY}.md
```

內容從前面步驟已收集的資訊組合（不重新分析）：

```markdown
# {TICKET-KEY}: {Summary}

## Context
- Type: {Bug/Story/Task}
- Repo: {repo_path}
- Base branch: {branch_name}
- Created: {today's date}

## Technical Approach
{Step 5b explore 分析結果、Step 3 Readiness Gate 的 AC、或 JIRA description 中的技術描述}

## Test Plan
{Step 5 AC Gate 產出的測試計畫 checklist}

## Verification Sub-tasks
{Step 5d-5e 建立的 [驗證] 子單列表}

## Decisions
（開發過程中 T2 taste calls 記錄於此 — 初始為空）
```

此檔案供 cross-session resume 使用（`繼續 {TICKET-KEY}` → 讀取 design doc 恢復 context）。`.claude/designs/` 應在 `.gitignore` 中。

### 6. 開發摘要 → 自動進入 TDD 開發 → 品質檢查 → 發 PR

路由完成後，顯示開發摘要然後**自動銜接後續流程**（不停下來等使用者）：

```
📋 PROJ-448 — [Feature] Product listing optimization
├─ 狀態：IN DEVELOPMENT
├─ Branch：task/PROJ-448-product-listing-optimization
├─ Base：feat/PROJ-460-aggregate-structured-data（依賴 PROJ-450，PR #102）
├─ AI 設定：已套用（polaris-sync.sh）
├─ Readiness Gate：✅ 通過（AC 品質合格）
├─ 測試計畫：3 項（AC Gate 已確認）
├─ [驗證] 子任務：TEAM-1003, TEAM-1004, TEAM-1005
└─ PR base：feat/PROJ-460-aggregate-structured-data
→ 開始 TDD 開發...
```

**自動銜接流程（單張 ticket 模式）：**

1. **TDD 開發**：讀取 `tdd` SKILL.md + 專案 CLAUDE.md，以 Red-Green-Refactor 循環實作。依 `references/tdd-smart-judgment.md` 判斷哪些檔案走 TDD
2. **品質檢查 → 行為驗證 → PR**：開發完成後自動讀取 `git-pr-workflow` SKILL.md 執行完整 PR 流程（品質檢查 → verify-completion → Pre-PR Review Loop → Commit → 發 PR → 轉 CODE REVIEW）

> 此流程與批次模式 Phase 2 sub-agent 的 Step 2-3 完全一致，差別只在單張 ticket 由主 agent 直接執行，不另開 sub-agent。

## 路由決策表（快速參考）

| Ticket 狀態 | 有子單？ | 有 Branch？ | 動作 |
|------------|---------|------------|------|
| 開放 | — | — | 轉 IN DEVELOPMENT → 建 branch |
| SA/SD | — | — | 轉 IN DEVELOPMENT → 建 branch |
| IN DEVELOPMENT | — | 無 | 建 branch |
| IN DEVELOPMENT | — | 有 | checkout branch → 開始開發 |
| CODE REVIEW | — | 有 | 提示修 review 或等 merge |
| QA 以後 | — | — | 提示無需開發 |
| Epic（開放） | 無 | — | 估點拆單 |
| Epic（開放） | 有 | — | 列出子單讓使用者選 |

## 開發中 Scope 追加

實作過程中發現需要追加改動（如：預估的優化效果不足、發現新瓶頸、依賴的 service 內部也需要改）時，**不可直接改 code**，必須先對齊再動手：

1. **暫停實作**，向使用者說明追加原因（為什麼原方案效果不足、新瓶頸在哪）
2. 使用者確認後，**在 JIRA 留 comment** 記錄 scope 追加：
   - 追加原因（實測數據 vs 預期、根因分析）
   - 追加的改動檔案和內容
   - 測試計畫是否需要調整（判斷基準：追加改動是否影響新的使用者行為或 API 回傳結構。若只是內部 implementation 改變但輸入輸出不變，現有測試計畫通常已涵蓋）
3. 若測試計畫需要新增項目 → 建立新的 [驗證] sub-task
4. 若 plan file 存在 → 同步更新 plan file
5. 繼續實作

**不需要追加測試計畫的情境**：改動只影響內部實作（如 sequential → parallel），API 回傳結構不變，現有驗證子單已涵蓋功能正確性和效能。

**需要追加測試計畫的情境**：改動引入新的 API 欄位、新的錯誤處理路徑、新的 service 依賴、或影響不同的使用者流程。

## Do / Don't

- Do: 每個路由決策前都向使用者確認，不要靜默跳步
- Do: 顯示完整摘要讓使用者知道目前狀態
- Do: 路由到其他 skill 時使用 Skill tool 觸發（不要手動重現步驟）
- Do: Readiness Gate（Step 3）檢查 ticket 品質，缺項阻擋、大 scope 自動跑 refinement
- Do: 開發前提取測試計畫建立 JIRA [驗證] sub-task（Step 5），每項可獨立追蹤
- Do: 開發預設使用 TDD（Red-Green-Refactor）。無法寫測試的檔案（config、純 style、型別定義）記錄原因後跳過，不阻擋流程
- Do: 實作完成後先跑 dev-quality-check（自動化快速回饋），通過後再跑 verify-completion（行為驗證，需啟動服務）。**順序不可調換**——品質檢查沒過就做行為驗證是白費功夫
- Do: 驗證全數通過後**自動銜接 git-pr-workflow 發 PR**，不需等使用者說「發 PR」
- Do: verify-completion 逐項驗證每張 JIRA [驗證] 子單，每張**獨立執行、獨立在該子單留驗證報告 comment、獨立切狀態**（開放 → IN DEVELOPMENT → 完成）。**全部通過才可 commit/push**
- Don't: 跳過 Readiness Gate — AC 缺失或品質不合格時不可繼續
- Don't: 跳過估點直接開發（除非使用者明確說不需要）
- Don't: 跳過品質檢查直接做行為驗證 — 品質檢查是行為驗證的前置條件
- Don't: 跳過行為驗證（verify-completion）直接 commit/push — 驗證子單全通過是 commit 的前置條件
- Don't: 把測試計畫只寫成 JIRA comment — 必須建成 [驗證] sub-task 才能追蹤狀態
- Don't: 自動決定依賴 branch（一定要確認）
- Don't: 在 QA 流程中的 ticket 上繼續開發


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
