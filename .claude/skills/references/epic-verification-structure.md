# Epic 驗證結構

Epic 拆單時自動產生的驗證相關 sub-tasks，確保每個 task 有測試紀錄、每個 Epic 有驗收證明。

## 三層驗證架構

> See `skills/references/epic-verification-workflow.md` § Three-Layer Verification (canonical source)。
> 三層：Task 測試計劃（PR 品質紀錄）→ Epic per-AC 驗收單（業務達標證明）→ Feature 整合測試（task 互動驗證）。

## 驗收單規則

### 大 / 小 Epic 分流

| 條件 | 驗收單做法 |
|------|----------|
| **大 Epic**（> 8 pts 或 > 2 task） | per-AC 拆驗收單，每條 AC 一張 |
| **小 Epic**（≤ 8 pts 或 ≤ 2 task） | 合併成一張「[EPIC_KEY][驗證] Epic 驗收」 |

### 驗收單格式

每張驗收單的 description：

```markdown
## 驗收目標

對應 AC：AC#N — {AC 描述}

## 驗證步驟

1. {具體操作步驟}
2. → 預期結果：{什麼算通過}

## 環境要求

- [ ] 可在 feature branch 驗
- [ ] 需要 stage 環境
```

### 驗收單排序

驗收單排在所有實作子單之後：

```
Task 1-N: 實作子單
Task N+1: [EPIC_KEY][驗證] AC#1 — {描述}
Task N+2: [EPIC_KEY][驗證] AC#2 — {描述}
...
（或合併為一張 [EPIC_KEY][驗證] Epic 驗收）
```

### 驗收單估點

驗收單預設 **0 pt**（驗收為 checklist 性質，簡單驗證的時間已含在實作子單估點中）。

只有符合以下條件的驗收單才給 **1 pt**：
- 需要獨立環境設置（啟動 Docker、部署到 staging）
- 需要跑 E2E 測試或 Playwright 腳本
- 需要多裝置截圖比對（desktop + mobile）
- 需要錄製或比對 baseline 資料

| 條件 | 驗收單點數 | 範例 |
|------|----------|------|
| curl / 檢視原始碼 / 簡單手動操作 | 0 pt | PROJ-123 檢查 JSON-LD |
| 需要啟動環境 + 多裝置截圖 + baseline 對比 | 1 pt | i18n 多頁面 VR 驗證 |

合併驗收單同理：依實際驗收複雜度判斷 0-2 pt。

## 驗收單 Lifecycle

驗收單建立後的狀態流轉，確保 Epic 層級能一眼看出驗收進度。

### 狀態流

```
驗收單建立（Open）
  → 實作子單 merge 回 feature branch
    → RD 逐條跑驗收步驟
      → 驗過 → 驗收單轉 Done + 貼驗證結果 comment
      → 沒過 → 驗收單留 Open + 貼失敗原因 + 回頭修 code
```

### 驗證結果 Comment 格式

驗收通過時，在驗收單貼 comment 記錄結果：

```markdown
## 驗證結果 — [日期]

**結論：PASS ✅**

| 步驟 | 結果 | 備註 |
|------|------|------|
| 1. {操作} | ✅ | {觀察到的結果} |
| 2. {操作} | ✅ | {觀察到的結果} |

環境：{SIT / local / staging}
```

驗收未通過時：

```markdown
## 驗證結果 — [日期]

**結論：FAIL ❌**

| 步驟 | 結果 | 備註 |
|------|------|------|
| 1. {操作} | ✅ | OK |
| 2. {操作} | ❌ | {實際結果 vs 預期結果} |

需要修正：{描述問題，link 回實作子單}
```

### Epic 完成判定

Epic 可以 close 的條件：
- 所有實作子單 → Done
- 所有驗收單 → Done（每張都有 PASS comment）
- 母單 feature branch → merge 回 develop

在 JIRA board 上一眼可判斷：全部子單 Done = Epic 可 close。

## 實作子單 Description 結構

實作子單的 description 必須將驗證內容分為兩個獨立章節，供下游的測試子單和驗收單各自引用。混合會導致兩層重疊。

```markdown
## 目標
{這個 task 要做什麼}

## 涉及檔案
{具體的檔案路徑和改動方式}

## 測試計畫（code-level）
驗證「code 改對了」的項目。供測試子單機械式複製。
- unit test: {具體 test case 描述}
- integration test: {具體 test case 描述}

## AC 驗證場景（business-level）
驗證「業務 AC 達標」的項目。供驗收單參照，不可複製到測試子單。
- AC#1: {使用者可見的操作 → 預期結果}
- AC#2: {使用者可見的操作 → 預期結果}
```

**邊界判斷**：如果驗證動作的對象是函式/API response/test runner output → code-level。如果對象是瀏覽器畫面/使用者操作/外部工具結果 → business-level。

## Task 測試 Sub-task

每張**實作子單**底下，為「## 測試計畫（code-level）」章節的每個測試項目各建立一張 JIRA Sub-task。

測試 Sub-task 全部通過 = 這個 Task 的 code 沒問題，可以 merge。

### 結構

```
Epic (大型工作)
├─ Task (實作子單, parent: Epic)
│   ├─ Sub-task (測試項目 1, issueType: 子任務, parent: Task)
│   ├─ Sub-task (測試項目 2, issueType: 子任務, parent: Task)
│   └─ Sub-task (測試項目 3, issueType: 子任務, parent: Task)
│
├─ Task (驗收 AC1, parent: Epic)
├─ Task (驗收 AC2, parent: Epic)
└─ ...
```

### 格式

- **issueType**：`子任務`（issueTypeId: 10006）— 不是 Task
- **parent**：實作子單的 key（不是 Epic）
- **Summary**：`[驗證] {測試項目描述}`
- **Points**：不估點（紀錄用）
- **Description**：

```markdown
## 驗證方式

{具體怎麼驗：跑哪個 test file、檢查什麼 output}

## 預期結果

{什麼算通過}

## 測試紀錄

（開發完成後填入）
- 測試結果：pass / fail
- 截圖或 log（如適用）
```

### 建立規則

- **來源**：從實作子單 description 的「## 測試計畫（code-level）」章節，**每個 item 各建一張 Sub-task**
- **時機**：`epic-breakdown` / `jira-estimation` 拆單建立實作子單時，立刻建立對應的測試 Sub-task
- **數量**：與「測試計畫」章節的 item 數量 1:1 對應，不合併、不增減
- **內容邊界**：只能包含 code-level 驗證。「## AC 驗證場景」的內容屬於驗收單，不可出現在測試 Sub-task

## Assignee 規則

> See `skills/references/jira-subtask-creation.md` § Assignee 規則 (canonical source)。適用於所有子單（實作 + 驗收 + 測試計劃）。

## 觸發流程

```
epic-breakdown / jira-estimation 拆單完成
  ├─ 每張實作子單：
  │   └─ 讀取「測試計畫（code-level）」章節
  │       └─ 每個 item → 建立 [驗證] Sub-task (issueType: 子任務, parent: 實作子單)
  ├─ 判斷大/小 Epic
  │   ├─ 大 → per-AC 建立 [驗證] Task (parent: Epic)
  │   └─ 小 → 合併一張 [驗證] Task (parent: Epic)
  └─ 更新母單估點（含驗收單點數）
```

## 來源

設計決策：2026-04-04，PROJ-483 試跑驗證。個別 task 都通過但 merge 回 feature 後出問題，證實 Feature 整合測試的必要性。
