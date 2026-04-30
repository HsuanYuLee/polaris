# Daily Learning Scan — 規格模板

本文件是 `/learning setup` 建立 daily scanner 時的模板。
`/learning setup` 讀取此模板，結合使用者輸入（tech stack, repos, Slack channel），組裝成 RemoteTrigger prompt。

## 掃描類別

| 類別 | 篇數 | 必選 | 說明 |
|------|------|------|------|
| **AI/Agent** | 2-3 | ✅ | Claude Code、MCP、multi-agent、skill patterns、AI-assisted dev |
| **使用者技術棧** | 4-5 | | 依使用者 tech stack 填入（如 Nuxt/Vue/Vitest/Turborepo） |
| **Architecture / DX** | 1-2 | | 跨 repo 通用：monorepo、CI/CD、ESLint、效能、設計模式 |

> AI/Agent 是必選類別 — 每日至少 2 篇。

## 品質篩選標準

- **發佈時間**：優先 3 個月內，最多 6 個月
- **深度**：有具體 code examples 或 config 範例，不是純概念介紹
- **實用性**：可直接應用到使用者的專案
- **去重**：比對 `learning-archive.md` 的 URL，不重複加入

## Slack 訊息格式

Scanner 發送一則 Slack 訊息，包含所有文章：

```
📚 Daily Learning Queue — {YYYY-MM-DD}

*1. {Article Title}*
• URL: {url}
• Category: {category}
• Tags: {tag1}, {tag2}
• Relevant Repos: {repo1}, {repo2} 或 all
• Summary: {一段話摘要}

*2. {Article Title}*
...

────────────────────
Scanned {N} sources, selected {M} articles.
```

**Slack 格式注意事項：**
- 禁用 `---`（horizontal rule）— Slack 會當成 invalid block 拒絕發送
- 用 `────────────────────`（unicode box drawing）代替分隔線
- 用 `*bold*` 而非 `### heading`（Slack mrkdwn 不支援 heading）

若無文章通過篩選：`📚 Daily Learning Queue — {date}: No new articles found today.`

## Trigger Prompt 組裝指引

`/learning setup` 組裝 RemoteTrigger prompt 時，需填入以下資訊：

1. **Slack Channel ID** — 使用者指定的通知 channel
2. **Tech Stack 關鍵字** — 從使用者回答組裝搜尋 query（如 `Nuxt 4 optimization`, `Vitest mock patterns`）
3. **Active Repos** — 使用者的 repo 列表 + 每個 repo 的技術棧，用於 Relevant Repos 標記
4. **自訂偏好** — 使用者額外指定的關注主題

Prompt 結構：
- Step 0: 讀 `learning-archive.md` 做去重（skip if not found）
- Step 1: WebSearch 各類別（AI/Agent 必選 + tech stack + architecture）
- Step 2: 品質篩選
- Step 3: 標記 Relevant Repos
- Step 4: 發 Slack 訊息

## 排程建議

- **預設 cron**: `57 13 * * *`（每天 21:57 UTC+8）
- **Model class**: `standard_coding`
- **Allowed tools**: `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `mcp__claude_ai_Slack__slack_send_message`
- **Sources**: 使用者的 workspace repo（需包含 `learning-archive.md`）
