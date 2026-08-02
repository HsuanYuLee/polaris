# Confluence Page Update

搜尋、讀取、附加內容到 Confluence 頁面的共用流程，含版本衝突偵測。

## 流程

### 1. 搜尋目標頁面

```
mcp__claude_ai_Atlassian__searchConfluenceUsingCql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  cql: space = "{config: confluence.space}" AND title = "<page_title>" AND type = page
```

- 找到 → 取得 `pageId`，進入 Step 2
- 找不到 → 依 skill 決定：建立新頁面（`createConfluencePage`）或告知使用者

### 2. 取得現有內容並記錄版本號

```
mcp__claude_ai_Atlassian__getConfluencePage
  cloudId: {config: jira.instance}
  pageId: <found_page_id>
  contentFormat: markdown
```

從回應中記錄 `version.number`（例如 `30`）。

### 3. 版本衝突偵測（Optimistic Locking）

更新前，先確認目前版本號與 Step 2 取得的一致。

如果版本號已變動（代表有人在你取得內容後編輯了頁面）：
1. 告知使用者「頁面在你編輯期間被修改（版本從 N 變為 M）」
2. 重新取得最新內容（回到 Step 2）
3. 在最新內容上附加新內容

### 4. 附加內容並更新

版本號一致時，在現有內容末尾附加新內容，然後更新：

```
mcp__claude_ai_Atlassian__updateConfluencePage
  cloudId: {config: jira.instance}
  pageId: <page_id>
  body: <existing_content + new_content>
  contentFormat: markdown
  versionMessage: "<描述性版本訊息>"
```

更新完成後告知使用者並附上 Confluence 頁面連結。

## 簡化模式

部分 skill（如 sprint-planning）不需要版本衝突偵測，可簡化為：
- 搜尋 → 存在則 `updateConfluencePage`，不存在則 `createConfluencePage`

使用完整模式（含版本偵測）或簡化模式由呼叫端決定。
