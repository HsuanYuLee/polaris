# GitHub → Slack User Mapping

Shared reference for resolving a GitHub username to a Slack user ID. Used by skills that send Slack notifications mentioning specific users.

## Consumers

- `review-inbox` Step 5b-1 (PR authors)
- `review-pr` Step 7a (PR author)
- `fix-pr-review` Step 12a (reviewers)
- `check-pr-approvals` (PR reviewers for 催 review)

## Lookup Chain (依序嘗試，找到即停)

### 1. Context Match（零成本）

若當前流程已有 Slack 訊息資料（如 review-inbox 從 channel 讀取的訊息），比對訊息中的 Slack user ID 與 GitHub username 的對應關係。

適用場景：Slack 模式的 review-inbox（Step 1 已讀取 channel 訊息）。其他 skill 通常沒有現成的 Slack 訊息上下文，跳過此步。

### 2. Slack Search by GitHub Username

```
slack_search_users({ query: "<github_username>" })
```

直接用 GitHub username 搜尋 Slack。有時能命中（username 與 display name 相同的情況）。

### 3. GitHub API 取真名 → Slack Search

```bash
gh api users/<github_username> --jq '.name'
```

取得 GitHub profile 上的真名（如 `Daniel Lee`），再用真名搜 Slack：

```
slack_search_users({ query: "<real_name>" })
```

**為什麼需要這步**：GitHub username（如 `daniel-lee-kk`）常與 Slack display name（如 `Daniel Lee`）不同，Step 2 搜不到時這步通常能命中。

### 4. Fallback：純文字

以上都找不到 → 用 `@{github_username}` 純文字顯示（不含 `<@U...>` mention）。

不要因為找不到 Slack user 就跳過通知 — 純文字 @mention 至少讓讀者知道是誰。

## 效能提示

- Step 1 幾乎不花成本（資料已在手上），優先使用
- Step 2-3 各需 1 次 API call，只在前一步失敗時才執行
- 批次處理多個 username 時，先收集所有 username 去重，再逐個查找，避免重複 API call
