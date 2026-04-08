---
name: jira-estimation
description: "Internal estimation engine — invoked by work-on, fix-bug, and epic-breakdown. Use when another skill needs story point estimation for a Story/Task, Bug, or Epic. Do NOT trigger directly from user input — route through work-on or fix-bug."
metadata:
  author: Polaris
  version: 1.2.0
---

# JIRA 估點建議

根據 Web team 估點度量衡（Confluence 文件，見 workspace-config.yaml 的 `confluence` 設定）提供 story point 建議。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 估點標準

> 完整估點標準與考量因素請參考共用文件：`.claude/skills/references/estimation-scale.md`

## Story Points 欄位操作

依 `references/jira-story-points.md` 的流程動態查詢 Story Points 欄位 ID 並執行寫入驗證。

本 skill 中所有寫入估點的步驟（Step 8.5 建立子單、母單估點更新）都必須遵循該 reference 的回查驗證流程。

## Workflow

### 1. 取得 JIRA 單內容並判斷類型

從以下來源取得 ticket key（優先順序）：
1. 使用者直接提供的 issue key（如 `PROJ-432`）
2. 當前 branch 名稱：`feat/PROJ-432` → `PROJ-432`
3. 詢問使用者

使用 MCP 工具讀取 ticket：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
```

讀取後立即檢查 **Issue Type**：

- **Epic（大型工作）** → 此 skill 不處理 Epic。告知使用者「這是一張 Epic，改用 epic-breakdown 處理」，然後委派給該 skill。
- **Bug** → 進入 Bug 流程（Step 3 分析根因）
- **Story / Task / Spike** → 進入一般估點流程

同時檢查 ticket 是否**已有估點**（Story Points 欄位有值）或**已有子單**（`fields.subtasks` 非空）。若是，提示使用者：
> 此 ticket 目前已有 X 點 / 已有 N 張子單，是否要覆蓋？

使用者確認後才繼續。

### 2. 辨識對應專案

從 ticket 的 **Summary** 中擷取 `[...]` tag，依 `references/project-mapping.md` 對應到本地專案路徑（`{base_dir}/<專案目錄>`）。不分大小寫比對。

若 Summary 中沒有 tag，進一步檢查 **Labels** 和 **Components** 欄位。仍無法匹配時，詢問使用者指定專案。

後續分析 codebase 時，以此專案路徑為根目錄。

### 3. 分析 ticket 內容

閱讀以下欄位來評估複雜度：
- **Summary** — 任務概述
- **Description** — 詳細需求、AC (Acceptance Criteria)
- **Issue Type** — Story / Task / Bug / Spike
- **Sub-tasks** — 是否有拆分子任務
- **Labels / Components** — 涉及的系統範圍

如果是 **Bug ticket**，在對應專案中分析 codebase 找出根因與修正方案（可搭配 `systematic-debugging` skill 的調查流程）。

### 4. 根據估點標準評估

依 `references/estimation-scale.md` 的估點標準與考量因素進行評估。

### 5. 輸出建議

#### Bug ticket — [ROOT_CAUSE] + [SOLUTION] 格式

如果 Issue Type 為 Bug，以下列格式回覆：

> **[ROOT_CAUSE]**
> 簡述問題的根本原因，指出具體的程式碼位置或邏輯錯誤
>
> **[SOLUTION]**
> 簡述修正方案，列出需要改動的檔案/模組
>
> **[VERIFICATION]**
> 預計驗證方式（類似 AC），分兩層列出：
>
> **Local 驗證（PR 前，RD 負責）：**
> - 重現原 bug 的操作步驟 → 預期修正後不再發生
> - 相關邊界場景 → 預期行為正常
> - 可自動化的寫 unit test，可手動驗的用 Playwright/curl 截圖
>
> **Post-deploy 驗證（SIT/Prod，[驗證] 子任務追蹤）：**
> - 需要真實環境才能確認的項目（第三方服務、數據面、跨服務）
>
> **建議點數：X 點**
>
> **對應標準：** （引用估點表中對應的描述）

#### 其他 ticket（Story / Task / Spike）

> **建議點數：X 點**
>
> **理由：**
> - （列出 2-4 個關鍵考量因素）
>
> **對應標準：** （引用估點表中對應的描述）

如果 ticket 資訊不足以準確估點，主動指出哪些資訊缺失，並給出一個範圍（如 3~5 點）。

### 6. 確認

詢問使用者是否同意此估點，或是否需要調整。

### 7. 更新到 JIRA 並依類型分流

使用者確認後，依 Issue Type 走不同流程：

#### Bug ticket → 估點 + 留言，不建子單

1. 將 [ROOT_CAUSE] + [SOLUTION] 以 comment 留在 ticket 上：

```
mcp__claude_ai_Atlassian__addCommentToJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  body: |
    ## [ROOT_CAUSE]
    <根因描述>

    ## [SOLUTION]
    <修正方案>

    ## [VERIFICATION]
    ### Local 驗證（PR 前）
    - <重現原 bug 步驟> → 預期修正後不再發生
    - <邊界場景> → 預期行為正常

    ### Post-deploy 驗證（SIT/Prod）
    - <數據/監控確認>（如適用）
    - <第三方服務/跨服務確認>（如適用）

    ## 估點
    <X> 點（<對應標準描述>）
```

2. 查詢 Story Points 欄位 ID（見「Story Points 欄位 ID 查詢」），然後更新 ticket 的 story points，並依「Story Points 回查驗證流程」確認寫入成功：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  fields:
    <storyPointsFieldId>: <估點數字>
```

3. **流程結束。** Bug 不需要拆子單。

#### Story / Task / Spike → 估點 + 建立子單

進入 Step 8 分析程式碼並建立子單。

### 8. 分析程式碼並建立子單（僅 Story / Task / Spike）

> **Bug ticket 不進入此步驟。**

#### 8.1 分析專案程式碼（自適應 Explore）

使用 `references/explore-pattern.md` 的自適應探索模式掃描 codebase。保持後續 Step 8.2 的 context window 乾淨。

**探索目標**：找出與需求相關的檔案，評估改動複雜度和影響範圍。

啟動 1 個 Explore subagent，帶入 ticket 需求摘要和專案路徑。Subagent 會自行判斷範圍大小 — 小需求直接探索，大需求自動分裂成多個 sub-Explore 平行處理。

**收到探索摘要後**，主 agent 直接進入 Step 8.2。不要再額外讀取原始碼。若某個面向資訊不足，針對性地追加單一 Explore subagent 補充，不要回到全面掃描。

#### 8.2 撰寫子單 description（比照 SASD 標準）

每張子單的 description 必須包含以下章節：

```markdown
## 需求
簡述這張子單要完成什麼，引用母單需求

## 異動範圍（Dev Scope）
列出每個需要異動的檔案/模組，說明改動內容：
- 現有檔案：說明要修改什麼
- 新增檔案：說明用途

## 前端設計（Frontend Design）
說明實作方式：
- 新增/修改哪些元件、hook、composable
- 資料流向
- 關鍵邏輯說明

## 測試計畫
列出需要測試的場景
```

如果涉及 BFF 層，額外加上 **BFF Process** 章節。
如果有流程變更，額外加上 **流程（System Flow）** 章節（mermaid sequence diagram）。

#### 8.3 決定拆單策略

- **≤ 5 點** — 建立 **一張** 子單，涵蓋所有改動
- **6-13 點** — 拆為 2-4 張子單，每張 2-5 點
- **13+ 點** — 拆為 4 張以上子單，每張控制在 2-5 點

拆解原則：依功能模組拆分，不要依技術層拆（不要拆成「寫 API」「寫 UI」「寫測試」）。

#### 8.4 呈現子單內容並確認

以表格呈現拆單結果，標註子單間的依賴關係：

```
| # | Summary | Points | 依賴 | 異動範圍摘要 |
|---|---------|--------|------|-------------|
| 1 | [TICKET] 子任務描述 | N | — | 簡要列出涉及的檔案 |
| 2 | [TICKET] 子任務描述 | N | #1 | 簡要列出涉及的檔案 |
```

依賴欄說明哪些子單有先後順序（開發時有依賴的子單可在同一 branch 但分 commit）。

#### 8.4a 🏛️ Architect Challenge（must-respond）

呈現估點結果前，dispatch **Architect Challenger** sub-agent（見 `skills/references/sub-agent-roles.md`）：

- **輸入**：Step 8 產出的完整估點報告（子單拆分表格、影響範圍、技術方案）
- **Model**：sonnet
- **輸出**：挑戰報告（⚠️ 需回應 + ✅ 合理）

將 Architect Challenge 結果**附在估點報告下方**一併呈現給使用者。使用者必須**逐條回應**每個 ⚠️ 項目：
- **接受** → 主 agent 根據建議調整估點/拆單
- **駁回（附理由）** → 記錄理由，維持原估點

所有 ⚠️ 項目回應完畢後才能繼續。

**必須等使用者確認後才建立子單。**

#### 8.5 批次建立 JIRA Sub-task

依 `references/jira-subtask-creation.md` 的完整流程（Step A → B → C → D）逐一建立子任務：

- Step A: 建立實作子單（含估點）
- Step B: 填入估點 + 回查驗證
- Step C: 建立測試計劃 sub-task（每張實作子單必須）
- Step D: 建立驗收單（依 `references/epic-verification-structure.md` 規則）

本 skill 的特殊設定：
- `parent` 指向母單（TICKET_KEY）
- `summary` 格式：`[TICKET_KEY] 簡短描述`
- `description` 使用 SASD 格式
- assignee：從母單的 assignee 取得（見 `references/jira-subtask-creation.md` § Assignee 規則）

若 createJiraIssue 失敗（權限不足、欄位錯誤等），記錄失敗的子單並告知使用者，繼續建立其餘子單。

#### 8.6 更新母單估點

所有子單建立完成後，**必須**將母單的 story points 更新為子單點數總和（使用動態查詢到的 fieldId），並依「Story Points 回查驗證流程」確認寫入成功：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET_KEY>
  fields:
    <storyPointsFieldId>: <子單點數總和>
```

#### 8.7 建立完成回報

全部建立完成後，以表格呈現結果：

```
| # | Key | Summary | Points |
|---|-----|---------|--------|
| 1 | PROJ-XXX | 子任務描述 | N |

母單 <TICKET_KEY>：N 點（加總）
Total: N 點，預估 X 天（以每日 2-3 點計算）
```

#### 8.8 銜接下一步

回報完成後，主動詢問使用者：

> 是否需要產出 SA/SD？

- 若使用者**同意** → 產出 SA/SD 並推上 Confluence
- 若使用者**拒絕** → 主動接續詢問：「要開始開發嗎？」
  - 若同意 → 進入 CLAUDE.md 定義的「開發功能」流程（轉 JIRA 狀態、建分支、開始實作）
  - 若拒絕 → 流程結束


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
