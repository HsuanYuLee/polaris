# Polaris 快速上手指南

> 這份指南是 [README Quick Start](../README.md#quick-start) 的中文版，內容完全對應。

## 前置需求

**所有人都需要：**
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — CLI、桌面應用程式或 IDE 擴充套件。需要 Claude Pro、Team 或 Enterprise 方案

> **注意：** 大部分 Polaris 技能會使用 sub-agent，需要 **Max 方案**（$100/月）或 API 存取。Pro/Team 方案只能使用單步技能。

- **Atlassian MCP** — 連接 Claude Code 到 JIRA 和 Confluence
- **Slack MCP** — 用於通知和報表（`standup`、`review-inbox`、`worklog-report`）

**開發者還需要：**
- **Git** 和 **GitHub CLI**（`gh`）— 已對組織認證

**選用：**
- **Google Calendar MCP** — 在 standup 加入會議上下文
- **Figma MCP** — JIRA 票卡引用 Figma 設計時使用

> **MCP 設定**：MCP server 將 Claude Code 連接到外部服務。在 Claude Code 設定中新增，或透過 CLI：
> ```
> claude mcp add atlassian -- npx -y @anthropic-ai/claude-code-mcp-atlassian
> claude mcp add slack -- npx -y @anthropic-ai/claude-code-mcp-slack
> ```

## 開始設定

### 1. 複製並進入工作區

```bash
# 從 Polaris 範本建立你的工作區（GitHub → "Use this template"）
# 然後 clone 你的新 repo：
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

> **提示**：選一個專用的目錄名稱。避免使用 `~/work` — 很多開發者已經在用這個路徑。

> **PM 和非開發者：** 請團隊的開發者幫你跑步驟 1-3，大約需要 10 分鐘。然後直接跳到步驟 4。

### 2. 設定 workspace config

```bash
cp workspace-config.yaml.example workspace-config.yaml
```

你不需要手動編輯這個檔案 — `/init` 會在下一步幫你填好。

### 3. 初始化公司目錄

在工作區內開啟 Claude Code — 在終端機中，從工作區目錄執行 `claude`（或在 VS Code 中開啟資料夾並使用 Claude Code 擴充套件）。然後輸入：

```
/init
```

互動式精靈會：
- 偵測你的 GitHub 組織和 repos
- 建立公司目錄和 `workspace-config.yaml`
- 設定專案對應（JIRA 票號 → 本地 repo 路徑）

### 4. 開始使用技能

> **注意：** 像 `/init` 這樣的指令是在 Claude Code 對話中輸入，不是在終端機 shell 中。

初始化完成後，用自然語言和 Claude Code 對話 — 中文英文都可以：

```
「做 PROJ-123」           → 完整開發流程（讀 JIRA → 估點 → 開 branch → 寫 code → 發 PR）
「修 bug PROJ-456」       → 根因分析 → 修復 → 發 PR
「review 這個 PR」        → 程式碼審查，會留 inline comment
「估點 PROJ-789」         → Story point 估算
「standup」               → 產出每日站會報告
「排 sprint」             → 拉票、算容量、建議優先順序
「學習這個 <url>」        → 研究外部資源，萃取可用模式
```

### 從這裡開始

不需要一次學會全部 30 個技能。從符合你角色的開始：

| 你的角色 | 先試這個 | 會發生什麼 |
|----------|---------|-----------|
| **開發者** | `「做 PROJ-123」` | 讀 JIRA → 估點 → 開 branch → 寫 code → 發 PR |
| **PM / Scrum Master** | `「standup」` | 收集昨天的 JIRA + git 活動 → 整理成報告 |
| **Tech Lead** | `「排 sprint」` | 拉 backlog → 算容量 → 建議優先順序 |

其他技能在你熟悉之後再慢慢探索。

## PM 與 Scrum 工作流程

如果你是 PM 或 Scrum Master，以下是 Polaris 覆蓋的 Sprint 生命週期：

```
Sprint 規劃        →  「排 sprint」
                       拉 JIRA backlog → 算團隊容量 → 偵測 carry-over
                       → 建議優先順序 → 產出 Release page 草稿

每日站會           →  「standup」
                       收集 JIRA 狀態變更 + git commit + 行事曆會議
                       → 分團隊整理 → 格式化為 YDY/TDT/BOS
                       （Yesterday Did / Today Do / Blockers or Shoutouts）

需求釐清           →  「refinement EPIC-100」
                       讀 Epic 內容 → 找出缺漏（Polaris 會自動讀程式碼，你只需要有 JIRA 權限）
                       → 產生 AC、範圍、邊界情況草稿 → 寫回 JIRA

拆單估點           →  「做 EPIC-100」
                       Epic → 拆成子任務 + 估 story point → 批次建在 JIRA

工時報表           →  「worklog report 2w」
                       查詢過去兩週完成的票 → 按 assignee 分組 → 發到 Slack
```

> 所有 PM 技能需要 **Max 方案**（$100/月）或 API 存取。這些技能不需要寫 code，也不需要了解 git。只要 Claude Code + JIRA MCP + Slack MCP 設定好就能使用。
> 如果技能沒有反應，請確認 Atlassian MCP 和 Slack MCP 連線正常 — 這能解決 90% 的 PM 設定問題。

---

> 更多開發者相關內容（架構、自訂、升級）請參考英文版 [README](../README.md#how-it-works)。
