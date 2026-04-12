---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates. Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate'."
metadata:
  author: Polaris
  version: 2.0.0
---

# Breakdown — 通用派工器

三層架構的 Layer 2：接收已理解的需求（bug-triage 或 refinement 產出），進行拆單、估點、品質挑戰、建立 JIRA 子單與開發 branch。

適用所有 ticket 類型：Bug / Story / Task / Epic。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. 取得 Ticket + 偵測類型

從以下來源取得 ticket key（優先順序）：
1. 使用者直接提供的 issue key（如 `PROJ-432`）
2. 當前 branch 名稱：`feat/PROJ-432` → `PROJ-432`
3. 詢問使用者

使用 MCP 工具讀取 ticket：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
```

讀取後判斷 **Issue Type** 並路由：

| Type | Path | 前置條件 |
|------|------|---------|
| Bug | Bug Path (B1-B4) | 必須有 `[ROOT_CAUSE]` comment（由 bug-triage 產出）|
| Story / Task / Spike | Planning Path (4-16) | — |
| Epic | Planning Path (4-16) | — |

**Bug 前置檢查**：用 JQL 或 getJiraIssue 的 comment 檢查是否有 `[ROOT_CAUSE]` 標記。若無：
> 「這張 Bug 還沒有根因分析。請先跑 `bug-triage {TICKET}` 完成診斷。」

同時檢查 ticket 是否**已有估點**或**已有子單**。若是，提示使用者確認是否覆蓋。

### 2. 辨識對應專案

從 ticket 的 **Summary** 中擷取 `[...]` tag，依 `references/project-mapping.md` 對應到本地專案路徑（`{base_dir}/<專案目錄>`）。不分大小寫比對。

若 Summary 中沒有 tag，進一步檢查 **Labels** 和 **Components** 欄位。仍無法匹配時，詢問使用者指定專案。

### 3. 偵測開發進度

在分析需求之前，先確認這張 ticket 是否已有開發進度：

1. **檢查既有子單** — 用 JQL `parent = <TICKET_KEY>` 查詢
2. **檢查 feature branch** — `git branch -a | grep <TICKET_KEY>`
3. **檢查 commit 紀錄** — 如果有 branch，用 `git log` 檢視已完成的工作

根據偵測結果調整行為：
- **已有子單** → 列出既有子單，詢問是否要補充
- **已有 branch + commits 但無子單** → 提示根據已完成工作建立子單追蹤
- **全新** → 進入正常流程

---

## Bug Path（Bug only）

### B1. 讀取根因分析

從 JIRA comment 中擷取 bug-triage 產出的結構化資訊：
- `[ROOT_CAUSE]` — 根因、檔案位置、問題描述
- `[IMPACT]` — 影響範圍、變更風險
- `[PROPOSED_FIX]` — 修正方向、預估改動範圍

### B2. 估點 + 規劃

依 `references/estimation-scale.md` 評估修正工作量。

**依複雜度分流：**

| 複雜度 | 條件 | 處理方式 |
|--------|------|---------|
| 簡單 | 1-2pt，改動 ≤ 3 檔案 | 不建子單，直接估點 → 銜接 work-on |
| 複雜 | 3+pt 或跨模組 | 拆子單（進入 Planning Path Step 6 起） |

**簡單 Bug 規劃輸出：**

```
## Bug 修復規劃

**Root Cause**: （摘要自 bug-triage）
**Proposed Fix**: （修正方案 + 涉及檔案）
**估點**: X pt（對應標準：...）

### 驗證計畫
**Local 驗證（PR 前）：**
- 重現原 bug 步驟 → 預期修正後不再發生
- 邊界場景 → 預期行為正常

**Post-deploy 驗證（如適用）：**
- 需真實環境確認的項目
```

### B3. 確認

呈現規劃給使用者確認。使用者可調整估點或修正方案。

### B4. 寫入 JIRA + 銜接

1. 查詢 Story Points 欄位 ID（依 `references/jira-story-points.md`）
2. 更新 ticket 估點 + 回查驗證
3. 將規劃以 comment 寫入 JIRA（格式同 B2 輸出）

**銜接：**
- 簡單 Bug → 「規劃完成。輸入 `做 {TICKET}` 開始修復。」
- 複雜 Bug → 進入 Planning Path Step 6（拆子單），帶入 ROOT_CAUSE 作為分析基礎，跳過 Step 4-5 的探索（根因已知）

---

## Planning Path（Story / Task / Epic）

### 4. 分析需求 + Codebase 探索（自適應 Explore）

從 ticket 中提取關鍵資訊：
- **Summary** — 概述
- **Description** — 詳細需求、AC
- **附件連結** — PRD、Figma、API doc

如果 description 資訊不足以拆單，主動列出缺少的資訊並詢問使用者補充。

**Codebase 掃描（與需求分析平行）：**

使用 `references/explore-pattern.md` 的自適應探索模式。啟動 1 個 Explore subagent，帶入需求摘要和專案路徑。Subagent 會自行判斷範圍大小。

收到探索摘要後，彙整 codebase 現況，結合需求進入 Step 5。

### 5. 評估拆單粒度

根據 ticket 規模決定拆單策略：

| 規模 | 預估總點數 | 策略 |
|------|-----------|------|
| 小型 | ≤ 5 pt | 一張 Task 涵蓋所有改動 |
| 中型 | 6-13 pt | 拆為 2-4 張子單 |
| 大型 | 13+ pt | 拆為 4+ 張子單，每張 2-5 pt |

### 6. 拆解子任務

將 ticket 拆解為具體的開發任務。

**拆解原則：**
- 依功能模組或頁面拆分，非依技術層（不要拆成「寫 API」「寫 UI」「寫測試」）
- 單一功能無法切分獨立測試時，不要硬拆 — 開一張集中處理
- 每張子單 story point 建議 **2-5 pt**，超過 5 pt 考慮再拆
- 如有 BFF 層改動，可獨立成子單
- 埋點量大時獨立成子單
- Spike / POC 類探索獨立出來
- 已有 feature branch 時，以實際 commit 改動範圍為準

**API-first 排序規則：**

涉及 cross-repo API 變更時，API 變更 task 排第一（前端消費 API，自然依賴順序）。

**穩定測資單（Fixture Recording Task）：**

若 project 有 `visual_regression` config，自動加入穩定測資 task（1pt），排在 API task 之後、前端 task 之前。

排序：`API/cross-repo → 穩定測資 → 前端開發`

**子任務結構（每張需包含）：**

- **Summary** — 格式：`[TICKET_KEY] 簡短描述`
- **Description** — 包含：需求、異動範圍（Dev Scope）、前端設計（如適用）、測試計畫
- **Story Points** — 依估點標準評估

> 實作細節寫在子單 description 中，不更新母單。

### 7. 估點

依 `references/estimation-scale.md` 對每個子任務評估 Story Point。

### 7.5. Quality Challenge 自動迴圈（最多 3 輪）

拆單 + 估點完成後，**自動** invoke `scope-challenge`（拆單審查模式）。

**檢查項目：**
- 每張子單是否 ≤ 5 pt
- 子單之間是否有循環依賴或邊界不清
- 每張子單是否有明確 AC 和 Happy Flow
- 是否有更簡單的替代方案被忽略
- 是否有隱藏假設未驗證

**迴圈邏輯：**
```
拆單結果 → scope-challenge
  → 全部 PASS → Step 8
  → 有 FAIL → 自動調整 → 再送 scope-challenge → ...
  → 最多 3 輪。超過仍有 FAIL → 連同未解決問題呈現給使用者
```

### 8. 呈現拆單結果並確認

以表格呈現通過 Quality Challenge 的拆單結果：

```
## [TICKET_KEY] Summary

| # | Summary | Points | 說明 |
|---|---------|--------|------|
| 1 | [TICKET_KEY] 子任務描述 | 3 | 改動範圍摘要 |
| 2 | [TICKET_KEY] 子任務描述 | 5 | 改動範圍摘要 |
| **Total** | | **N** | 預估 X 天（每日 2-3 pt） |
```

**必須等使用者明確確認後才進行下一步。**

### 9. 查詢 Story Points 欄位 ID

依 `references/jira-story-points.md` 動態查詢。後續 Step 10、11 使用此 fieldId。

### 10. 批次建立 JIRA Sub-task

依 `references/jira-subtask-creation.md` 完整流程（Step A → B → C → D）：

- Step A: 建立實作子單
- Step B: 填入估點 + 回查驗證
- Step C: 建立測試計劃 sub-task
- Step D: 建立驗收單（依 `references/epic-verification-structure.md`）

本 skill 設定：
- `parent` 指向母單（TICKET_KEY）
- `projectKey` 從 ticket key 動態提取
- assignee：從母單 assignee 取得（見 `references/jira-subtask-creation.md` § Assignee 規則）
- Step B 驗證失敗時立即報錯

> 迴圈：每張實作子單 A → B（含驗證）→ C，完成後下一張。全部完成後 Step D。

### 11. 更新母單估點（必須）

子單點數總和寫入母單 SP + 回查驗證。不可省略。

### 12. 建立完成回報

```
## 建立完成

| # | Key | Summary | Points | Repo | Branch |
|---|-----|---------|--------|------|--------|
| 1 | PROJ-1001 | 子任務描述 | 5 | <repo> | task/PROJ-1001-desc |

Total: N pt，預估 X 天
```

### 12.5. AC ↔ 子單追溯矩陣

> Epic 必須執行。Story/Task 有明確 AC 時也建議執行。

比對 ticket description 中的 AC 與子單覆蓋關係：

```
| AC | 對應子單 | 驗證場景 |
|----|---------|---------|
| AC1: ... | PROJ-501 | ✅ 已定義 |
| AC2: ... | ❌ 無對應 | — |
```

若有 AC 無對應子單 → 強制 block，詢問使用者新增子單或移到 Out of Scope。

通過後將追溯矩陣寫入 JIRA comment。

### 13. 整合母單描述

> Epic 必須執行。Story/Task 視 description 品質決定。

檢查母單 description 是否已結構化。若資訊散落在 comment 中或缺少拆單總覽，主動整合更新。

結構化 description 參考 `references/epic-template.md`，必須包含**拆單總覽**（子單 Key + Summary + Points）。

### 14. 建立 Branch

**14a. 按專案分組子單**（從子單 description 或 Step 2 的專案辨識結果）

**14b. 建立母單 feature branch**（每個涉及的 repo 一個）

```bash
git -C {base_dir}/<repo> checkout develop
git -C {base_dir}/<repo> pull origin develop
git -C {base_dir}/<repo> checkout -b feat/<TICKET_KEY>-<description>
git -C {base_dir}/<repo> push -u origin feat/<TICKET_KEY>-<description>
```

> 小型 ticket（≤ 5pt，單一子單）可跳過 feature branch，直接從 develop 開 task branch。

**14c. 為每張子單建立 branch**（從對應 repo 的母單 branch 開出）

```bash
git -C {base_dir}/<repo> checkout feat/<TICKET_KEY>-<description>
git -C {base_dir}/<repo> checkout -b task/<SUB_KEY>-<description>
git -C {base_dir}/<repo> push -u origin task/<SUB_KEY>-<description>
```

**14d. 回報 branch 結構**

### 15. 銜接 SA/SD（選擇性）

詢問使用者是否要產出 SA/SD 文件。確認則觸發 `sasd-review`。

### 16. 開工準備完成

所有子單已有 branch、測試計畫、驗證子單。

**觸發方式：** `做 <子單 key>` → `work-on`

## 注意事項

- Ticket 資訊太少時（只有 summary）不要硬拆，列出需要補充的資訊
- 拆單粒度以「一個 PR 能完成」為原則
- 小型 ticket（≤ 5 pt）直接一張子單，不要過度拆分
- 不要自動建單，一定要使用者確認後才建立
- **Do**：拆單後產出 AC 追溯矩陣（Epic 必須，其他建議）
- **Don't**：跳過追溯矩陣 — 有 AC 沒被覆蓋時必須處理

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
