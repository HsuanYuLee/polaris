# Polaris 快速上手指南

> 這份指南是 [中文 README](../README.zh-TW.md) 快速上手部分的精簡版。完整內容請參閱 [README.zh-TW.md](../README.zh-TW.md)。

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

### 1. 建立你的工作區

到 GitHub 上的 [Polaris 範本 repo](https://github.com/HsuanYuLee/polaris)，點 **「Use this template」→「Create a new repository」**，然後 clone：

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

> **提示**：選一個專用的目錄名稱。避免使用 `~/work` — 很多開發者已經在用這個路徑。

> **PM 和非開發者：** 請團隊的開發者幫你跑步驟 1-2，大約需要 10 分鐘。然後直接跳到步驟 3。

### 2. 執行 `/init` 初始化公司

在工作區內開啟 Claude Code — 在終端機中，從工作區目錄執行 `claude`（或在 VS Code 中開啟資料夾並使用 Claude Code 擴充套件）。然後輸入：

```
/init
```

互動式精靈會：
- 偵測你的 GitHub 組織和 repos
- 建立公司目錄和 `workspace-config.yaml`
- 設定專案對應（JIRA 票號 → 本地 repo 路徑）

完成後你的工作區會長這樣：

```
~/polaris-workspace/              ← 你的工作區根目錄（這個 repo）
├── CLAUDE.md                     ← AI 策略師指令
├── workspace-config.yaml         ← 路由 JIRA 票號到對應公司
├── .claude/
│   ├── rules/                    ← 通用規則 (L1)
│   │   └── your-company/         ← 公司專屬規則 (L2)
│   └── skills/                   ← 43 個工作流技能
└── your-company/                 ← 由 /init 建立
    ├── workspace-config.yaml     ← 公司設定（JIRA、Slack、repos）
    └── your-project/             ← 你的專案 repo（clone 或連結）
        └── .claude/CLAUDE.md     ← 專案層級規則 (L3)
```

### 3. 開始使用技能

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

不需要一次學會全部 43 個技能。從符合你角色的開始：

| 你的角色 | 先試這個 | 會發生什麼 |
|----------|---------|-----------|
| **開發者** | `「做 PROJ-123」` | 讀 JIRA → 估點 → 開 branch → 寫 code → 發 PR |
| **PM / Scrum Master** | `「standup」` | 收集昨天的 JIRA + git 活動 → 整理成報告 |
| **Tech Lead** | `「排 sprint」` | 拉 backlog → 算容量 → 建議優先順序 |

其他技能在你熟悉之後再慢慢探索。

## 三大支柱

Polaris 圍繞三大支柱組織你的 AI 輔助工作流程：

### 支柱一 — 輔助開發

從 JIRA 到 PR 的完整自動化：`「做 PROJ-123」` → 讀 JIRA → 估點 → 開 branch → 寫 code → 跑測試 → 發 PR → 轉 JIRA 狀態。涵蓋 `work-on`、`bug-triage`、`epic-breakdown`、`tdd`、`git-pr-workflow`、`review-pr` 等技能。

詳細流程 → [Developer Workflow Guide](workflow-guide.md)

### 支柱二 — 自我學習 ★

Polaris 與靜態範本的最大差異：它會從日常使用中累積團隊知識、自動演進規則。

1. **回饋捕捉** — 你糾正 Claude 的做法時，它記下教訓
2. **模式升格** — 同一回饋被引用 3 次以上，自動升為永久規則
3. **外部學習** — 研究文章、repo 或 PR，萃取可套用的模式
4. **挑戰者審計** — 發版前，sub-agent 從新使用者視角審查 workspace

> **範例：** 你在三次不同的 PR 中糾正 Claude 的 import 順序。第三次時，教訓自動升格為永久規則 — 之後所有 PR 自動遵循這個慣例。

### 支柱三 — 日常紀錄

Sprint 生命週期自動化，PM、Scrum Master、開發者都能用：`「standup」` → 收集 JIRA + git + 行事曆 → 整理成站會報告。涵蓋 `standup`、`sprint-planning`、`worklog-report`、`jira-worklog`、`refinement` 等技能。

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

## 架構

### 三層規則

| 層級 | 位置 | 載入時機 | 內容 |
|------|------|---------|------|
| **L1 — 工作區** | `CLAUDE.md` + `.claude/rules/` | 每次對話 | Strategist 人格、委派規則 |
| **L2 — 公司** | `.claude/rules/{company}/` | 每次對話 | PR 慣例、JIRA 流程、技能路由 |
| **L3 — 專案** | `{company}/{project}/CLAUDE.md` | 進入專案時 | Lint 設定、測試慣例、元件規範 |

規則（rules）永遠載入。技能（skills）按需觸發 — 沒觸發時不佔 context。

### 目錄結構

```
你的工作區/
├── CLAUDE.md                  # Strategist 人格 + 委派規則
├── workspace-config.yaml      # 公司路由（JIRA 票號 → 哪間公司）
├── .claude/
│   ├── rules/                 # 通用規則 (L1)
│   │   └── {company}/         # 公司專屬規則 (L2)
│   └── skills/                # 43 個工作流技能
├── _template/                 # 新公司範本 + 規則範例
├── scripts/                   # 同步工具
└── {company}/                 # 你的公司目錄
    ├── workspace-config.yaml  # 公司設定（JIRA、Slack、repos）
    └── {project}/             # 專案 repo，含 CLAUDE.md (L3)
```

### 工作流編排

技能之間會自動串接。例如 `「做 PROJ-123」` 會依序觸發：

```
work-on → jira-estimation → jira-branch-checkout → start-dev → tdd → dev-quality-check → git-pr-workflow
```

每個技能都有明確的進入條件和輸出，像 pipeline 一樣串起來。詳細流程圖 → [Developer Workflow Guide](workflow-guide.md)

### 排程 Agent

`/schedule` 可以設定定期執行的背景任務（例如每日技術文章掃描、定期健康檢查），不需要開著對話視窗。

## 多公司設定

Polaris 支援在同一個工作區管理多間公司。每間公司有獨立的設定、規則和技能：

```
你的工作區/
├── .claude/rules/
│   ├── *.md                   # 通用規則（所有公司）
│   ├── acme/                  # Acme 專屬規則
│   └── bigcorp/               # BigCorp 專屬規則
├── acme/                      # Acme 專案 + 設定
└── bigcorp/                   # BigCorp 專案 + 設定
```

**隔離機制：**
- `workspace-config.yaml` 把 JIRA 專案代碼對應到公司 — 說 `「做 ACME-123」` 時，Polaris 自動讀 Acme 的設定
- 公司規則都有 scope header，Strategist 只套用對應公司的規則
- 共用技能在 `.claude/skills/`（git 追蹤），公司專屬技能在 `.claude/skills/{company}/`（gitignore）

**加入第二間公司：** 再跑一次 `/init`，精靈會偵測已有的公司，在旁邊建立新的。

**診斷工具：**
- `/which-company PROJ-123` — 查看票號路由到哪間公司
- `/use-company` — 手動切換公司 context
- `/validate-isolation` — 掃描隔離問題（scope header 缺失、memory 標籤錯誤）

## 自訂

| 想做什麼 | 在哪裡 | 怎麼做 |
|---------|--------|--------|
| 加入新公司 | 執行 `/init` | 互動式精靈幫你建好一切 |
| 對應 JIRA 專案到 repo | `{company}/workspace-config.yaml` | 在 `projects:` 下新增 |
| 加公司專屬規則 | `.claude/rules/{company}/` | 建 `.md` 檔 — 每次對話自動載入 |
| 加專案專屬規則 | `{company}/{project}/CLAUDE.md` | sub-agent 進入專案時載入 |
| 建立新技能 | 執行 `/skill-creator` | 引導式建立 + 自動測試 |
| 調整技能路由 | `.claude/rules/{company}/skill-routing.md` | 觸發詞 → 技能對應表 |

### 可以改 vs 不要碰

**可以自由修改：**

| 路徑 | 自訂什麼 |
|------|---------|
| `.claude/rules/{company}/` | 你公司的慣例、PR 規範、JIRA 流程 |
| `{company}/workspace-config.yaml` | JIRA 專案、Slack 頻道、repo 對應 |
| `{company}/{project}/CLAUDE.md` | 專案層級規則 (L3) |

**框架內部 — 除非你在改 Polaris 本身，否則不要動：**

| 路徑 | 為什麼 |
|------|--------|
| `.claude/skills/*/SKILL.md` | 技能定義 — 用 `/skill-creator` 修改 |
| `.claude/skills/references/` | 技能共用資料（估點量表、範本） |
| `.claude/rules/*.md` (L1) | 通用規則 — 每次對話都載入 |
| `CLAUDE.md` | Strategist 人格 — 框架的大腦 |

## 升級

如果你是從 Polaris 範本 clone 的，想拉取框架更新：

```bash
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template [--dry-run]
```

這會同步技能、規則和共用資料，**不會覆蓋**你的公司設定、L2 規則和專案檔案。用 `--dry-run` 先預覽變更再套用。

> 升級只更新框架層。你自己加的公司規則、workspace-config、專案 CLAUDE.md 都不受影響。
