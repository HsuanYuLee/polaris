# Slack PR Input Resolver

從 Slack 訊息中擷取 GitHub PR URL 的共用流程。適用於所有接受 Slack 輸入的 skill。

## 偵測條件

使用者輸入包含以下任一：
- Slack URL（`*.slack.com/archives/*`）
- Slack 頻道名稱（如 `#code-review`）
- 提及「slack 上的 PR」

## 擷取流程

1. **Slack URL** → 解析出 channel ID 和 message timestamp，使用 `slack_read_thread` 或 `slack_read_channel` MCP tool 讀取訊息內容
2. **Slack 頻道名稱**（如 `#code-review`）→ 使用 `slack_search_channels` 找到頻道，再用 `slack_read_channel` 讀取近期訊息
3. 從訊息內容中提取所有 GitHub PR URL（格式：`https://github.com/{owner}/{repo}/pull/{number}`）
4. 若找到 PR URL，以這些 URL 作為輸入繼續後續流程

## `p` 參數轉 timestamp

Slack URL 的 `p` 參數需轉換為 API 用的 `thread_ts`：

```
去掉 `p` prefix，在倒數第 6 位前插入 `.`
例：p1773631805068619 → 1773631805.068619
```

## 保留 Slack Context

若輸入來源是 Slack，記住以下資訊供後續 Slack 回覆步驟使用：
- `slack_channel_id`：頻道 ID
- `slack_thread_ts`：訊息 timestamp（經上述轉換）
- `slack_source`：標記為 `true`

## 注意事項

- Slack 訊息中的連結可能被格式化為 `<https://...|顯示文字>` 格式，需要提取 `<` 和 `|` 之間的實際 URL
- `slack_channel_id` 的來源依 skill 不同：有些從 URL 直接取得，有些從 config `slack.channels.*` 讀取

## 多 PR 處理

若偵測到多個 PR URL，為每個 PR 啟動獨立的 sub-agent 平行處理（每個 sub-agent 使用 `isolation: "worktree"`），收集結果後統一回報 + Slack 通知。
