# JIRA Sub-task 批次建立

建立子任務並填入估點的共用流程。每個子任務需兩步驟完成。

## 前置條件

- Story Points 欄位 ID 已透過 `references/jira-story-points.md` 查詢取得
- 子任務清單已經使用者確認
- Assignee accountId 已取得（見 § Assignee 規則）

## Assignee 規則

所有子單的 assignee 預設為**母單的 assignee**。從 `getJiraIssue` 回傳的 `fields.assignee.accountId` 取得。

若母單無 assignee，從 memory `user_scrum_role.md` 取得使用者的 JIRA accountId 作為 fallback。

> 不設定 assignee 不是預設行為。子單建出來就應該有 owner。

**MCP 參數名注意**：`createJiraIssue` 的 assignee 參數是 **`assignee_account_id`**（不是 `assignee`）。傳錯參數名會被靜默忽略，導致 assignee 落到專案預設值。

## Step 0 — 查詢既有子單（必須）

在建立任何新子單之前，先查詢母單是否已有子單。`getJiraIssue` 的 `subtasks` 欄位**只回傳同專案的 Sub-task**，跨專案的 Task + parent link 不會出現。必須用 JQL：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: project = {子單專案key} AND parent = {母單key} ORDER BY created ASC
  fields: ["summary", "status", "<storyPointsFieldId>", "issuetype"]
  # storyPointsFieldId：依 references/jira-story-points.md Step 0 動態探測，不可寫死
  maxResults: 50
```

根據查詢結果決定動作：

| 情境 | 動作 |
|------|------|
| 無既有子單 | 正常進入建立迴圈 |
| 有既有子單，SP 已填 | 回報現有子單，跳過建立，僅補缺（驗收單、測試計劃） |
| 有既有子單，SP 未填 | 回報現有子單，進入補估點流程（Step B），不重複建立 |
| 有部分子單 | 回報現有 + 識別缺少的，僅建立缺少的部分 |

> **為什麼不能省略**：exampleco 慣例子單建在 KB2CW 用 parent link，`getJiraIssue` 的 `subtasks` 會回傳空陣列，造成「以為沒有子單」的誤判。EPIC-480 就是此 bug 的實例。

## 建立迴圈

對每個子任務依序執行以下兩步驟（不可省略任何一步）：

### Step A — 建立子單

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  projectKey: <從母單 key 提取，如 PROJ-123 → PROJ>
  issueTypeName: 任務
  summary: <子任務 summary>
  description: <子任務 description，Markdown 格式>
  contentFormat: markdown
  parent: <母單 KEY>
  assignee_account_id: <母單 fields.assignee.accountId，fallback: memory user_scrum_role.md>
```

### Step B — 填入估點（必須，createIssue 不支援此欄位）

建立成功後，**立刻**對同一張子單呼叫 editJiraIssue 補上 story points：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <剛建立的子任務 key>
  fields:
    <storyPointsFieldId>: <估點數字>
```

### Step B 驗證

依 `references/jira-story-points.md` 的回查驗證流程確認寫入成功。若不符，立即報錯告知使用者「子單 XX 的 story points 設定失敗（預期 N，實際 M）」，不繼續建立下一張。

> 迴圈：對每個子任務重複 Step A → Step B（含驗證），完成後再處理下一個。每完成一個回報進度。

## 母單估點更新

所有子單建立完成後，更新母單的 story points 為子單總和：

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <母單 KEY>
  fields:
    <storyPointsFieldId>: <子單估點加總>
```

同樣依回查驗證流程確認寫入。

## Step C — 建立測試計劃 sub-task（每張實作子單必須）

每張**實作子單**建立完成後（Step A + B 驗證通過），立刻建立對應的測試計劃 sub-task：

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}
  projectKey: <與實作子單相同>
  issueTypeName: 任務
  summary: [<實作子單 KEY>][測試計劃] <實作子單 summary 簡寫>
  parent: <實作子單 KEY>
  assignee_account_id: <同實作子單的 assignee>
  contentFormat: markdown
  description: |
    ## 測試場景

    （從實作子單的「測試計畫」章節複製）
    - [ ] 場景 1：...
    - [ ] 場景 2：...

    ## 測試紀錄

    （開發完成後填入）
    - 測試方式：unit test / Playwright / curl / 手動
    - 測試結果：pass / fail
    - 截圖或 log（如適用）
```

測試計劃 sub-task **不估點**（紀錄用）。穩定測資單不需要測試計劃。

> 迴圈更新：每張實作子單的完整流程為 Step A → Step B（含驗證）→ Step C，三步完成後再處理下一張。

## Step D — 建立驗收單（所有實作子單完成後）

所有實作子單 + 測試計劃建立完成後，依 `references/epic-verification-structure.md` 的規則建立驗收單：

1. 判斷大/小 Epic（> 8 pts 或 > 2 task → 大 → per-AC；否則 → 小 → 合併一張）
2. 建立驗收單（`issueTypeName: 任務`，`parent: <母單 KEY>`）
3. 填入估點（per-AC 每張 1 pt；合併版 ≤ 3 AC → 1 pt，> 3 AC → 2 pt）
4. 驗收單的母單估點也要計入總和

## 注意事項

- `projectKey` 從母單 key 動態提取，子單開在與母單相同的專案
- `issueTypeName` 使用 `任務`（中文）— 搭配 `parent` 欄位建立父子關係
- 若 createJiraIssue 失敗（權限不足、欄位錯誤等），記錄失敗的子單並告知使用者，繼續建立其餘子單
- **assignee 必須設定**：預設為母單的 assignee（見 § Assignee 規則）
