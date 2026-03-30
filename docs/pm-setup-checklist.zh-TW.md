[English](./pm-setup-checklist.md) | 中文

# PM 設定清單

> 這份清單是給想使用 Polaris 的 PM 和 Scrum Master。你不需要執行任何終端指令 — 請團隊中的開發者協助設定即可。

## 你需要準備的（你的部分）

- [ ] 一個 **Claude Pro、Team 或 Enterprise** 帳號 — 在 [claude.ai](https://claude.ai) 註冊
  - 大部分 PM 技能需要 **Max 方案**（$100/月）或 API 存取權限
- [ ] 你的團隊的 **JIRA** 和 **Confluence** 工作區存取權限
- [ ] 你的團隊的 **Slack** 工作區存取權限
- [ ] （選配）**Google Calendar** 存取權限 — 可為站會報告加入會議相關資訊

## 請開發者協助的（他們的部分）

把以下訊息傳給團隊中的開發者：

> **嗨，可以幫我設定 Polaris 嗎？需要以下幾個步驟：**
>
> 1. Clone Polaris workspace 並執行 `/init` 設定我們的公司
> 2. 確認 Claude Code 中以下 MCP 連線已設定好：
>    - **Atlassian MCP**（連接我們的 JIRA + Confluence）
>    - **Slack MCP**（用於通知和報告）
>    - **Google Calendar MCP**（選配，用於站會的會議資訊）
> 3. 驗證是否正常運作：輸入 `"standup"` 確認能讀到我們的 JIRA 資料
>
> 大概 10 分鐘就搞定了，謝謝！

## 設定完成後：驗證是否正常

打開 Claude Code（你的開發者可以教你怎麼開 — 它在 VS Code、終端機或桌面應用程式中）。然後嘗試：

1. 輸入 `"standup"` — 你應該會看到包含 JIRA 活動的站會報告
2. 輸入 `"排 sprint"` — 你應該會看到團隊的 JIRA backlog

如果其中任何一個失敗，請和你的開發者確認 Atlassian MCP 連線是否正常。

## 你的日常指令

| 時機 | 輸入這個 | 會發生什麼 |
|------|---------|-----------|
| 站會前 | `"standup"` | 從 JIRA + git + calendar 產生 YDY/TDT/BOS 報告 |
| Sprint 規劃 | `"排 sprint"` 或 `"sprint planning"` | 拉取 backlog、計算容量、建議優先順序 |
| 精煉 Epic | `"refinement EPIC-100"` | 讀取 Epic 內容、找出缺漏、草擬 AC 和範圍 |
| 拆解 Epic | `"做 EPIC-100"` 或 `"work on EPIC-100"` | 拆成子任務並附上故事點估算 |
| Sprint 結束時 | `"worklog report 2w"` | 顯示依 assignee 分組的已完成票券 |

## 疑難排解

| 問題 | 解決方法 |
|------|---------|
| Skill 沒有回應或出現錯誤 | 檢查 Claude Code 設定中 Atlassian MCP 和 Slack MCP 是否已連線 |
| 「Sub-agents not available」 | 你需要 Max 方案（$100/月）— 大部分 PM 技能會用到 sub-agents |
| 站會報告是空的 | 確認你的 JIRA 專案代碼已設定好（請開發者檢查 `workspace-config.yaml`） |
| 找不到 Claude Code | 它和 claude.ai 是不同的應用程式 — 請開發者幫你安裝 |
