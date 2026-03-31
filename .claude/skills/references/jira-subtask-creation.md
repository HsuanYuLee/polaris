# JIRA Sub-task 批次建立

建立子任務並填入估點的共用流程。每個子任務需兩步驟完成。

## 前置條件

- Story Points 欄位 ID 已透過 `references/jira-story-points.md` 查詢取得
- 子任務清單已經使用者確認

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
  assignee: <使用者的 JIRA accountId，從 memory 取得>
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

## 注意事項

- `projectKey` 從母單 key 動態提取，子單開在與母單相同的專案
- `issueTypeName` 使用 `任務`（中文）— 搭配 `parent` 欄位建立父子關係
- 若 createJiraIssue 失敗（權限不足、欄位錯誤等），記錄失敗的子單並告知使用者，繼續建立其餘子單
- assignee 欄位可選——有些 skill（epic-breakdown）會設定，有些（jira-estimation）不設定，由呼叫端決定
