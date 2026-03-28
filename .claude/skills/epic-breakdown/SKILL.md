---
name: epic-breakdown
description: >
  Breaks down a JIRA Epic into actionable sub-tasks with story point estimates,
  then batch-creates them in JIRA after user confirmation. Use this skill whenever
  the user mentions 拆單, 拆解, 分解任務, 子單, break down epic, epic breakdown,
  create sub-tasks, 評估這張單, 評估 epic, or provides an Epic and asks to split
  it into tasks — even if they don't explicitly say "breakdown". Also trigger when
  the user gives an Epic key and says "evaluate", "assess", "plan", "評估", or
  asks "help me plan this epic". The key distinction from jira-estimation
  (single ticket estimation) is that this skill handles Epics that need to be
  decomposed into multiple sub-tasks with individual estimates.
metadata:
  author: ""
  version: 1.7.0
---

# Epic Breakdown — 拆單與估點

讀取 JIRA Epic 內容，分析需求後拆解為可執行的子任務，逐一估點，經使用者確認後批次建立 JIRA sub-task。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. 取得 Epic 內容

從以下來源取得 Epic key（優先順序）：
1. 使用者直接提供的 issue key（如 `TASK-123`）
2. 詢問使用者

使用 MCP 工具讀取 Epic：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <EPIC_KEY>
```

### 2. 辨識對應專案

從 Epic 的 **Summary** 中擷取 `[...]` tag，依 `references/project-mapping.md` 對應到本地專案路徑（`~/work/<專案目錄>`）。不分大小寫比對。

若 Summary 中沒有 tag 或無法匹配，詢問使用者指定專案。

後續分析 codebase 時，以此專案路徑為根目錄。

### 3. 偵測開發進度

在分析需求之前，先確認這張 Epic 是否已有開發進度：

1. **檢查既有子單** — 用 JQL `parent = <EPIC_KEY>` 查詢是否已有子任務
2. **檢查 feature branch** — 用 `git branch -a | grep <EPIC_KEY>` 或從當前 branch 名稱判斷是否已有對應的 feature branch
3. **檢查 commit 紀錄** — 如果有 feature branch，用 `git log` 檢視已完成的工作

根據偵測結果調整行為：
- **已有子單** → 列出既有子單，詢問是否要補充缺少的部分
- **已有 feature branch + commits 但無子單** → 提示使用者「看起來開發已有進度（N commits, M files changed），是否要根據已完成的工作建立子單做追蹤？」，並根據實際 commit 範圍而非 description 來拆單
- **全新 Epic** → 進入正常拆單流程

### 4. 分析 Epic 需求 + Codebase 探索（自適應 Explore）

從 Epic 中提取關鍵資訊：

- **Summary** — Epic 概述
- **Description** — 詳細需求、Acceptance Criteria
- **附件連結** — PRD、Figma、API doc（從 description 或 comment 中提取）

如果 Epic description 資訊不足以拆單，主動列出缺少的資訊並詢問使用者補充，例如：
- 缺少 Figma → 無法判斷 UI 複雜度
- 缺少 API doc → 無法評估串接工作量
- AC 不明確 → 無法確定驗收範圍

**Codebase 掃描（與需求分析平行進行）：**

使用 `references/explore-pattern.md` 的自適應探索模式掃描 codebase，讓拆單結果包含具體檔案路徑和準確的工作量估算。

**探索目標**：找出與 Epic 相關的現有程式碼結構，識別可複用模組和依賴順序。

啟動 1 個 Explore subagent，帶入 Epic 需求摘要和專案路徑。Subagent 會自行判斷範圍大小 — 小 Epic 直接探索，大 Epic 自動分裂成多個 sub-Explore 平行處理。

**收到探索摘要後**，主 agent 彙整 codebase 現況，結合 Epic 需求進入 Step 5 評估拆單粒度。Codebase 摘要直接用於子單的「涉及檔案」和「實作方式」描述，讓子單內容更具體。

### 5. 評估拆單粒度

根據 Epic 的規模決定拆單策略：

- **小型 Epic（預估總點數 ≤ 5 點）** — 不需拆成多張子單，直接建立**一張 Task** 涵蓋所有改動即可。避免為小型工作產生過多管理負擔。
- **中型 Epic（6-13 點）** — 拆為 2-4 張子單
- **大型 Epic（13+ 點）** — 拆為 4 張以上子單，每張控制在 2-5 點

### 6. 拆解子任務

將 Epic 拆解為具體的開發任務，每個子任務應該是一個可獨立開發、測試的工作項目。

**拆解原則：**

- 依功能模組或頁面拆分，而非依技術層（不要拆成「寫 API」「寫 UI」「寫測試」）
- **單一功能若無法切分獨立測試，不要硬拆成多張子單** — 應開一張子單集中處理，避免產生無法獨立驗收的碎片單
- 每個子任務的 story point 建議落在 **2-5 點**，超過 5 點考慮再拆
- 如果有 BFF 層改動，可以獨立成一個子任務
- 埋點（tracking）如果量大，獨立成一個子任務
- Spike / POC 類的探索任務獨立出來
- 如果是根據已完成的 feature branch 拆單，以實際 commit 的改動範圍為準，而非 description 中的建議

**子任務結構：**

每個子任務需包含：
- **Summary** — 格式：`[EPIC_KEY] 簡短描述`（如 `[TASK-123] 商品列表頁 UI 元件`）
- **Description** — 說明這個子任務要做什麼、涉及哪些檔案/模組、AC、實作方式
- **Story Points** — 依估點標準評估

**重要：實作細節（修改檔案、實作方式、技術決策）寫在子單 description 中，不要更新到母單或在母單留言。** 母單只保留需求概述與拆單總覽。

### 7. 估點

依 Web team 估點度量衡對每個子任務評估 Story Point。

> 估點標準與考量因素請參考共用文件：`.claude/skills/references/estimation-scale.md`

### 7.5. Scope Challenge 自動迴圈（最多 3 輪）

拆單 + 估點完成後，**自動** invoke `scope-challenge`，以「拆單審查模式」檢查拆單結果。不需使用者觸發。

**輸入**：完整拆單表格（每張子單的 Summary、Points、說明、Happy Flow）+ Epic 原始需求。

**檢查項目**：
- 每張子單是否 <= 5 點（過大需再拆）
- 子單之間是否有循環依賴或邊界不清
- 每張子單是否有明確 AC 和 Happy Flow
- 是否有更簡單的替代方案被忽略
- 是否有隱藏假設未驗證

**迴圈邏輯**：

```
拆單結果 → scope-challenge
  → 全部 PASS → 進入 Step 8（呈現給使用者確認）
  → 有 FAIL items → 自動根據回饋調整拆單（調整點數 / 再拆 / 合併 / 補 AC）
    → 再送 scope-challenge → ...
    → 最多 3 輪。超過 3 輪仍有 FAIL → 連同未解決的問題一起呈現給使用者
```

**每輪回報**（靜默執行，只在有調整時簡要輸出）：

```
🔄 Scope Challenge Round 1/3：2 項需調整
  - 子單 #3「API 串接」(8pt) 過大 → 拆為 #3a + #3b
  - 子單 #5 缺 Happy Flow → 已補上
```

調整後的拆單結果直接覆蓋原版，進入下一輪或 Step 8。

### 8. 呈現拆單結果並確認

以表格呈現**通過 Scope Challenge 的**拆單結果：

```
## [EPIC_KEY] Epic Summary

| # | Summary | Points | 說明 |
|---|---------|--------|------|
| 1 | [EPIC_KEY] 子任務描述 | 3 | 簡要說明改動範圍 |
| 2 | [EPIC_KEY] 子任務描述 | 5 | 簡要說明改動範圍 |
| ... | ... | ... | ... |
| **Total** | | **N** | 預估 X 天（以每日 2-3 點計算） |
```

詢問使用者：
- 是否同意此拆法？
- 是否需要調整某個任務的範圍或點數？
- 是否要新增或合併任務？

**必須等使用者明確確認後才進行下一步。**

### 9. 查詢 Story Points 欄位 ID

建立子單前，先確認目標專案中 Story Points 的正確欄位 ID：

```
mcp__claude_ai_Atlassian__getJiraIssueTypeMetaWithFields
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  projectKey: <從 Epic key 提取，如 TASK>
  issueTypeName: 任務
```

在回傳的 fields 中搜尋 `name` 含 "Story Points" 的欄位，取得其 `fieldId`（例如 `customfield_10031`）。後續 Step 10、Step 11 的 editJiraIssue 都使用此 fieldId。

> ⚠️ 不要假設欄位 ID（不同 JIRA 專案的欄位 ID 可能不同），必須動態查詢。

### 10. 批次建立 JIRA Sub-task

使用者確認後，**對每個子任務依序執行以下兩步驟**（不可省略任何一步）：

**Step A — 建立子單：**

assignee 從 memory `user_scrum_role.md` 取得使用者的 JIRA accountId。

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  projectKey: <projectKey>（從 Epic key 提取，例如 PROJ-123 → GT，TASK-123 → TASK）
  issueTypeName: 任務
  summary: <子任務 summary>
  description: <子任務 description，Markdown 格式>
  contentFormat: markdown
  parent: <EPIC_KEY>
  assignee: <使用者的 JIRA accountId>
```

**Step B — 填入估點（必須，createIssue 不支援此欄位）：**

建立成功後，**立刻**對同一張子單呼叫 editJiraIssue 補上 story points（使用 Step 9 查到的 fieldId）：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <剛建立的子任務 key>
  fields:
    <storyPointsFieldId>: <估點數字>
```

**Step B 驗證** — editJiraIssue 回傳後，檢查 response 中 `fields.<storyPointsFieldId>` 的值是否等於設定的估點數字。若不符，立即報錯告知使用者「子單 XX 的 story points 設定失敗（預期 N，實際 M）」，不繼續建立下一張。

> 迴圈：對每個子任務重複 Step A → Step B（含驗證），完成後再處理下一個。每完成一個回報進度。

**注意事項：**
- `projectKey` 從 Epic key 動態提取（如 `PROJ-123` → `GT`，`TASK-123` → `TASK`），子單開在與母單相同的專案
- `issueTypeName` 使用 `任務`（中文）— 搭配 `parent` 欄位建立父子關係
- `parent` 填入 Epic 的 issue key，確保子任務正確歸屬
- Story points 欄位 ID 必須使用 Step 9 動態查詢的結果，不可寫死
- **如果漏填估點，JIRA 看板上該子單不會顯示點數，影響 sprint 計算**

### 11. 更新母單估點（必須）

所有子單建立並填好估點後，**必須**將母單的 story points 更新為子單點數總和（使用 Step 9 查到的 fieldId）：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <EPIC_KEY>
  fields:
    <storyPointsFieldId>: <子單點數總和>
```

同樣檢查 editJiraIssue 回傳的 `fields.<storyPointsFieldId>` 是否正確寫入，不符則報錯。

> 這步不可省略。母單點數 = 所有子單點數加總，讓 sprint planning 能正確反映工作量。

### 12. 建立完成回報

全部建立完成後，以表格呈現結果：

```
## 建立完成

| # | Key | Summary | Points | Repo | Branch |
|---|-----|---------|--------|------|--------|
| 1 | TASK-123 | Nuxt SSR API parallel | 5 | your-app | task/TASK-123-nuxt-ssr-api-parallel |
| 2 | TASK-123 | Server-side cache | 2 | your-app | task/TASK-123-server-side-cache-footer |
| 3 | TASK-123 | your-backend category parallel | 3 | your-backend | task/TASK-123-category-parallel |
| 4 | TASK-123 | your-backend fetch_product parallel | 5 | your-backend | task/TASK-123-fetch-product-parallel |
| 5 | TASK-123 | 驗證跑分 | 2 | your-app | task/TASK-123-verify-benchmark |

Total: 17 點，預估 6-8 天
母單 branch: feat/PROJ-123-cwv-ttfb-server-response（your-app + your-backend 各一）
```

### 12.5. AC ↔ 子單追溯矩陣（必須）

子單建立完成後，立即比對 Epic description 中的 AC（驗收條件）與剛建立的子單，確保每一條 AC 都有對應的子單覆蓋。

**建立追溯矩陣：**

從 Epic description 的 AC 段落提取所有驗收條件，逐一對應到子單（依子單 description 和 summary 判斷涵蓋關係）：

```
## AC ↔ 子單追溯

| AC | 對應子單 | 驗證場景 |
|----|---------|---------|
| AC1: 點擊日期後價格 300ms 內更新 | PROJ-123 | ✅ 已定義 |
| AC2: API timeout → skeleton | PROJ-123 | ✅ 已定義 |
| AC3: 多幣別切換 | ❌ 無對應子單 | — |
```

**驗證場景欄位說明：**
- `✅ 已定義` — 子單 description 中有對應的 Happy Flow 驗證場景
- `⚠️ 未定義` — 子單存在但缺少 Happy Flow 描述（需補上）
- `❌ 無對應子單` — 此 AC 沒有任何子單覆蓋（必須處理）

**若有 AC 無對應子單 → 強制 block，詢問使用者：**

```
❌ 以下 AC 沒有對應子單，無法繼續：

- AC3: 多幣別切換

請選擇：
1. 新增子單覆蓋此 AC（提供 summary 即可，我來建立）
2. 明確移到 Out of Scope（請確認此 AC 不在本 Epic 範圍內）

在使用者回應前不繼續後續步驟。
```

**將追溯矩陣寫入 JIRA Epic comment：**

```
mcp__claude_ai_Atlassian__addCommentToJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <EPIC_KEY>
  body: <追溯矩陣的 Markdown 內容，包含標題「## AC ↔ 子單追溯」>
  contentFormat: markdown
```

> 這步確保追溯矩陣留存在 JIRA，未來 QA 或 PM 查驗時可直接參考，不需重新整理。

### 13. 整合母單描述（必須）

拆單建立完成後，檢查母單 description 是否已結構化。若母單經過 refinement 討論、資訊散落在多個 comment 中，或 description 缺少拆單總覽，主動整合更新：

**結構化 description 應包含（完整格式參考 `references/epic-template.md`）：**
- 背景與目標
- Scope（做什麼 / 不做什麼）
- Baseline 數據（若有量化指標）
- 瓶頸分析（效能/優化類）
- AC（驗收條件）
- 開發驗收（RD 自驗方式，如 Lighthouse before/after）
- 可行做法（技術方案概述）
- **拆單總覽**（子單 Key + Summary + Points，含總點數）— 此步驟必填
- 依賴（跨團隊、跨專案前置條件）
- 待確認事項
- 參考資料（Figma、API doc、PRD 連結獨立成段）

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <EPIC_KEY>
  fields:
    description: <結構化 description，整合 comments 中的資訊>
  contentFormat: markdown
```

> 這步確保母單 description 是完整的「需求文件」，新加入的人能快速理解全貌，不需翻閱 comment 歷史。

### 14. 自動建立 Branch（母單 + 所有子單）

子單建完、母單描述整合後，**自動建立開發用的 branch 結構**（不需等使用者說「開始開發」）。

**14a. 按專案分組子單**

從每張子單的 description 或 Step 2 的專案辨識結果，將子單按 repo 分組：

```
例：PROJ-123 的子單分組
├─ your-app：TASK-123, TASK-123, TASK-123
└─ your-backend：TASK-123, TASK-123
```

**14b. 每個 repo 各建一個母單 feature branch**

從 develop 開出，每個涉及的 repo 一個：

```bash
# your-app
git -C ~/work/your-app checkout develop
git -C ~/work/your-app pull origin develop
git -C ~/work/your-app checkout -b feat/<EPIC_KEY>-<description>
git -C ~/work/your-app push -u origin feat/<EPIC_KEY>-<description>

# your-backend（若有跨 repo 子單）
git -C ~/work/your-backend checkout develop
git -C ~/work/your-backend pull origin develop
git -C ~/work/your-backend checkout -b feat/<EPIC_KEY>-<description>
git -C ~/work/your-backend push -u origin feat/<EPIC_KEY>-<description>
```

> 單一 repo 的 Epic 只有一個母單 branch。跨 repo Epic 每個 repo 各一個同名母單 branch。

**14c. 為每張子單建立 branch（從對應 repo 的母單 branch 開出）**

```bash
git -C ~/work/<repo> checkout feat/<EPIC_KEY>-<description>
git -C ~/work/<repo> checkout -b task/<SUB_KEY>-<description>
git -C ~/work/<repo> push -u origin task/<SUB_KEY>-<description>
```

Branch 命名遵循 `{任務類型}/{JIRA-KEY}-{語義說明}` 規範。description 從子單 summary 提取，kebab-case。

**14d. 回報 branch 結構**

```
🌳 Branch 結構已建立：

your-app:
  develop
    └─ feat/PROJ-123-cwv-ttfb-server-response（母單）
         ├─ task/TASK-123-nuxt-ssr-api-parallel
         ├─ task/TASK-123-server-side-cache-footer
         └─ task/TASK-123-verify-benchmark

your-backend:
  develop
    └─ feat/PROJ-123-cwv-ttfb-server-response（母單）
         ├─ task/TASK-123-your-backend-category-parallel
         └─ task/TASK-123-your-backend-fetch-product-parallel
```

> 所有 branch 已 push 到 remote。子單 branch 的 PR base 是**同 repo** 的母單 branch。

### 15. 銜接 SA/SD（選擇性）

branch 建立完成後，詢問使用者：「是否要接著為這個 Epic 產出 SA/SD 文件？」

如果使用者確認，直接觸發 `sasd-review` skill，並將已分析的 Epic 內容與拆單結果作為上下文傳遞，避免重複分析需求與程式碼。SA/SD 的 Task List 應直接沿用拆單結果，不需重新拆解。

### 16. 開工準備完成

SA/SD 完成（或跳過）後，所有子單已有 branch、測試計畫、驗證子單，隨時可以開始開發。

**觸發方式：** RD 說「做 <子單 key>」即可觸發 `work-on`，自動 checkout 到該子單 branch 並進入 TDD 開發。

## 注意事項

- 如果 Epic 資訊太少（只有 summary 沒有 description），不要硬拆，而是列出需要補充的資訊
- 拆單粒度以「一個 PR 能完成」為原則，避免過細或過粗
- 小型 Epic（≤ 5 點）直接開一張子單即可，不要過度拆分
- 不要自動建單，一定要使用者確認後才建立
- **Do**：拆單後產出 AC 追溯矩陣，確保沒有 AC 被遺漏
- **Don't**：跳過追溯矩陣 — 有 AC 沒被子單覆蓋時必須處理（新增子單或明確移到 Out of Scope）
