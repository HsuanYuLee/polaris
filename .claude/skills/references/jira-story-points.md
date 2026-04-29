# JIRA Story Points 欄位操作

動態查詢 Story Points 欄位 ID 及讀寫驗證的共用流程。**所有讀寫 Story Points 的 skill 都必須引用本文件**。

## Step 0 — 欄位 ID 探測（必要）

不同 JIRA 專案的 Story Points 欄位 ID 可能不同（`customfield_10016`、`customfield_10031` 等），**不可寫死**。每次 session 首次操作估點前，必須動態查詢：

```
mcp__claude_ai_Atlassian__getJiraIssueTypeMetaWithFields
  cloudId: {config: jira.instance}
  projectIdOrKey: <目標專案 key，如 TASK>
  issueTypeId: <目標 issue type ID，如 10005（任務）>
```

在回傳的 fields 中搜尋 `name` 為 "Story Points" 的欄位，取得其 `key`（格式：`customfield_NNNNN`）。

> 回傳量大時用 bash + python3 解析：搜尋 `"name": "Story Points"` 附近的 `"key": "customfield_..."` 值。

**快取規則**：查詢一次即可，同一 session 內重複使用。不同專案 key 需各自查詢（但同公司通常相同）。

**⚠ 嚴禁**：在 `fields` 陣列、`editJiraIssue`、或任何 MCP 呼叫中直接寫 `customfield_10016` 或其他硬編欄位 ID。必須使用本步驟探測到的變數。

## 讀取方式

所有需要讀取 Story Points 的 JQL 查詢或 `getJiraIssue`，`fields` 陣列必須使用探測到的欄位 ID：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: parent = <TICKET>
  fields: ["summary", "status", "<storyPointsFieldId>", "issuetype"]
```

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
  fields: ["summary", "status", "<storyPointsFieldId>"]
```

## 寫入方式

```
mcp__claude_ai_Atlassian__editJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <ticket key>
  fields:
    <storyPointsFieldId>: <估點數字>
```

## 回查驗證流程

所有寫入 story points 的操作都必須遵循此流程：

1. 使用 `editJiraIssue` 寫入探測到的 Story Points fieldId
2. 檢查 editJiraIssue 回傳的 response 中 `fields.<fieldId>` 是否為預期值
3. 若不符：
   - 用 `getJiraIssue` 回查，在 `fields` 中搜尋含有 `story` 或 `point` 的 key
   - 嘗試用找到的正確欄位 ID 重新寫入
   - 若仍失敗，告知使用者需手動填入

## 注意

- 如果漏填估點，JIRA 看板上該子單不會顯示點數，影響 sprint 計算
- `projectKey` 從 ticket key 動態提取（如 `PROJ-123` → `PROJ`）
- 本文件是 Story Points 欄位的**唯一真相來源**。任何 skill 需要讀寫 SP，引用本文件的 Step 0 取得欄位 ID
