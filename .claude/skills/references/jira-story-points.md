# JIRA Story Points 欄位操作

動態查詢 Story Points 欄位 ID 及寫入驗證的共用流程。

## 欄位 ID 查詢

不同 JIRA 專案的 Story Points 欄位 ID 可能不同（`customfield_10016`、`customfield_10031` 等），**不可寫死**。每次 session 首次寫入估點前，必須動態查詢：

```
mcp__claude_ai_Atlassian__getJiraIssueTypeMetaWithFields
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  projectKey: <目標專案 key，如 PROJ 或 BACK>
  issueTypeName: 任務
```

在回傳的 fields 中搜尋 `name` 含 "Story Points" 的欄位，取得其 `fieldId`。

> 查詢一次即可，同一 session 內可重複使用。但不同專案 key 需要各自查詢。

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

1. 使用 `editJiraIssue` 寫入動態查詢到的 Story Points fieldId
2. 檢查 editJiraIssue 回傳的 response 中 `fields.<fieldId>` 是否為預期值
3. 若不符：
   - 用 `getJiraIssue` 回查，在 `fields` 中搜尋含有 `story` 或 `point` 的 key
   - 嘗試用找到的正確欄位 ID 重新寫入
   - 若仍失敗，告知使用者需手動填入

## 注意

- 如果漏填估點，JIRA 看板上該子單不會顯示點數，影響 sprint 計算
- `projectKey` 從 ticket key 動態提取（如 `PROJ-123` → `PROJ`）
