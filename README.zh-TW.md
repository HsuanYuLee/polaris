[English](./README.md) | 中文

# Polaris

一個 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 工作區模板，將你的 AI 助手變成策略師——它學習你團隊的工作流程、將任務路由到專門的技能、並從日常使用中演化自己的規則。

## 適合誰？

- **開發者** — 自動化 JIRA → branch → code → PR 的循環，透過 AI 執行團隊慣例
- **技術主管** — 統一團隊的估點、Code Review 和 Sprint Planning 標準
- **PM 和 Scrum Master** — 產出站會報告、追蹤工時、執行 Sprint Planning——不需要寫程式
- **多公司接案者** — 在單一工作區管理多個客戶，規則、技能和設定完全隔離

> 不確定適不適合？如果你的團隊使用 JIRA + GitHub，而且你希望 Claude Code 遵循你的工作流程而不是隨意發揮，Polaris 就是為你設計的。

## 三大支柱

Polaris 圍繞三大支柱組織你的 AI 輔助工作流程：

| 輔助開發 | 自我學習 | 日常紀錄 |
|:---:|:---:|:---:|
| JIRA → branch → code → PR | Feedback → pattern → rule | Standup, sprint, worklog |
| 自動化完整的票單生命週期 | 從日常使用中演化自己的規則 | 為整個團隊服務的 Sprint 生命週期 |

### 支柱一 — 輔助開發

你告訴 Claude Code 你想做什麼，Polaris 處理剩下的一切：

```
你：     「做 PROJ-123」
Polaris: 讀取 JIRA 票單 → 檢查前置條件 → 估算 Story Points
         → 拆分子任務 → 建立 JIRA 子票
         → 開 feature branch → 實作程式碼 → 跑測試
         → 開 PR 附上覆蓋率報告 → JIRA 狀態轉為 CODE REVIEW
```

**技能：** `work-on`, `fix-bug`, `epic-breakdown`, `epic-status`, `tdd`, `git-pr-workflow`, `review-pr`, `fix-pr-review`, `dev-quality-check`, `verify-completion`, `jira-branch-checkout`, `start-dev`, `scope-challenge`, `refinement`

深入了解 → [開發者工作流程指南](docs/workflow-guide.zh-TW.md)

### 支柱二 — 自我學習 ★

這是 Polaris 與靜態模板的根本差異。它累積團隊知識，並從日常使用中演化自己的規則：

1. **回饋擷取** — 當你糾正 Claude 的做法時，它會儲存這個教訓
2. **規則畢業** — 同一個回饋被引用 3 次以上，自動升級為永久規則
3. **外部學習** — 研讀文章、repo 或 PR，萃取可套用到你 codebase 的模式
4. **挑戰者審計** — 發版前，sub-agent 從新使用者的角度審視整個工作區

> **範例：** 你在不同的 PR 中糾正了 Claude 的 import 排序 3 次。第三次糾正時，這個教訓自動畢業成永久規則——之後所有 PR 都會自動遵循這個慣例。

**技能：** `learning`, `review-lessons-graduation` — 另外 `review-pr`, `fix-pr-review` 和 `check-pr-approvals` 內建教訓萃取功能

### 支柱三 — 日常紀錄

為 PM、Scrum Master 和開發者提供的 Sprint 生命週期自動化——不需要寫程式：

```
你：     「standup」
Polaris: 收集 JIRA 活動 + git commits + 行事曆會議
         → 依團隊分組 → 格式化為 昨天做/今天做/障礙 → 發到 Confluence

你：     「排 sprint」
Polaris: 拉取 JIRA backlog → 計算團隊容量 → 偵測 carry-over
         → 建議優先順序 → 草擬 Release 頁面
```

**技能：** `standup`, `sprint-planning`, `worklog-report`, `jira-worklog`, `refinement`（PM 視角）, `epic-breakdown`（PM 視角）

## 什麼是 Claude Code？

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 是 Anthropic 的程式碼代理——它在你的終端機、IDE（VS Code / JetBrains）或桌面應用程式中執行。你跟它對話，它就能讀取檔案、撰寫程式碼、執行指令、呼叫外部服務。Polaris 是建構在 Claude Code 之上的工作區模板，賦予它你團隊的技能和規則。

> 如果你用過 claude.ai 上的 Claude，Claude Code 就是同樣的 AI 但擁有存取你 codebase 和工具的能力。Polaris 教會它你團隊的特定工作流程。

## 前置需求

**所有人都需要：**
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — CLI、桌面應用或 IDE 擴充套件。需要 Claude Pro、Team 或 Enterprise 方案

> **重要：** 大多數 Polaris 技能使用 sub-agent，需要 **Max 方案**（$100/月）或 API 存取。在 Pro/Team 方案下，僅單步驟技能可運作。
- **Atlassian MCP** — 連接 Claude Code 到 JIRA 和 Confluence
- **Slack MCP** — 用於通知和報告（`standup`, `review-inbox`, `worklog-report`）

**開發者另外需要：**
- **Git** 和 **GitHub CLI**（`gh`）— 已通過組織認證

**選配：**
- **Google Calendar MCP** — 為 `standup` 增加會議脈絡
- **Figma MCP** — 當 JIRA 票單引用 Figma 設計時使用

> **MCP 設定**：MCP 伺服器將 Claude Code 連接到外部服務。在 Claude Code 設定中新增，或透過 CLI：
> ```
> claude mcp add atlassian -- npx -y @anthropic-ai/claude-code-mcp-atlassian
> claude mcp add slack -- npx -y @anthropic-ai/claude-code-mcp-slack
> ```
> 參閱 [MCP 伺服器文件](https://docs.anthropic.com/en/docs/claude-code/mcp-servers) 了解 Google Calendar 和 Figma 的設定方式。

## 快速上手

### 1. 建立你的工作區

到 GitHub 上的 [Polaris 模板 repo](https://github.com/HsuanYuLee/polaris)，點選 **「Use this template」→「Create a new repository」**，然後 clone 下來：

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

> **提示**：選一個專用的目錄名稱。避免用 `~/work`——很多開發者已經將這個路徑用於其他專案。

> **PM 和非開發者：** 請參閱 [PM 設定清單](docs/pm-setup-checklist.zh-TW.md)——它會告訴你該問開發者什麼、以及設定完成後該做什麼。然後直接跳到步驟 4。

### 2. 執行 `/init` 設定你的公司

> **注意：** `/init` 等 `/指令` 是在 Claude Code 對話中輸入的，不是在終端機 shell 中。

在工作區內開啟 Claude Code——在終端機中從工作區目錄執行 `claude`（或在 VS Code 中開啟該資料夾並使用 Claude Code 擴充套件）。然後輸入：

```
/init
```

互動式精靈會：
- 偵測你的 GitHub 組織和 repo
- 建立公司目錄和 `workspace-config.yaml`
- 設定專案對應（JIRA key → 本地 repo 路徑）

`/init` 完成後，你的工作區結構如下：

```
~/polaris-workspace/              ← your workspace root (this repo)
├── CLAUDE.md                     ← AI strategist instructions
├── workspace-config.yaml         ← routes JIRA keys to companies
├── .claude/
│   ├── rules/                    ← universal rules (L1)
│   │   └── your-company/         ← company-specific rules (L2)
│   └── skills/                   ← 34 workflow skills
└── your-company/                 ← created by /init
    ├── workspace-config.yaml     ← company config (JIRA, Slack, repos)
    └── your-project/             ← your existing repo (cloned or linked)
        └── .claude/CLAUDE.md     ← project-level rules (L3)
```

試著輸入 `「做 PROJ-123」`（替換為真實的票單 key）來驗證設定。如果 Polaris 成功讀取票單，就表示設定完成了。

### 3. 開始使用技能

初始化完成後，用自然語言跟 Claude Code 對話即可——中文或英文都可以：

```
「做 PROJ-123」       / "work on PROJ-123"     → 完整開發流程
「修 bug PROJ-456」   / "fix bug PROJ-456"     → 根因分析 → 修復 → 發 PR
「review 這個 PR」    / "review PR"             → Code Review 並留下行內評論
「估點 PROJ-789」     / "estimate PROJ-789"     → Story Point 估算
「standup」           / "standup"               → 產出每日站會報告
「排 sprint」         / "sprint planning"       → 拉票、算容量
「學習這個 <url>」    / "learn from <url>"      → 研讀外部資源，萃取模式
```

完整的中文觸發詞參考 → [docs/chinese-triggers.md](docs/chinese-triggers.md)

### 從這裡開始

不要一次嘗試全部 34 個技能。根據你的角色挑一個開始：

| 如果你是... | 先試這個 | 會發生什麼 |
|------------|---------|-----------|
| **開發者** | `「做 PROJ-123」` | 讀取 JIRA → 估點 → 建立 branch → 寫程式 → 開 PR |
| **PM / Scrum Master** | `「standup」` | 收集昨天的 JIRA + git 活動 → 格式化報告 |
| **技術主管** | `「排 sprint」` | 拉取 backlog → 計算容量 → 建議優先順序 |

其他技能都建立在這些基礎上。熟悉之後再逐步探索更多技能。

### PM 與 Scrum 工作流程

Polaris 涵蓋完整的 Sprint 生命週期——不需要寫程式或了解 git。所有 PM 技能因為使用 sub-agent，需要 **Max 方案**（$100/月）或 API 存取。

```
Sprint Planning    →  「排 sprint」
                      拉取 JIRA backlog → 計算團隊容量 → 偵測 carry-over
                      → 建議優先順序 → 草擬 Release 頁面

每日站會           →  「standup」
                      收集 JIRA 狀態變更 + git commits + 行事曆會議
                      → 依團隊分組 → 格式化為 昨天做/今天做/障礙

Refinement         →  「refinement EPIC-100」
                      讀取 Epic 內容 → 找出缺漏（Polaris 會為你閱讀 codebase）
                      → 草擬 AC、範圍、邊界案例 → 寫回 JIRA

拆單               →  「做 EPIC-100」
                      Epic → 帶有 Story Point 估算的子任務 → 批次建立到 JIRA

工時報告           →  「worklog report 2w」
                      查詢過去 2 週完成的票單 → 依 assignee 分組 → 發到 Slack
```

> **PM 和 Scrum Master：** 以下內容是給開發者和框架維護者的。你已經設定完成了！
> 如果某個技能無法運作，請檢查 Claude Code 設定中的 Atlassian MCP 和 Slack MCP 連線是否正常——這能解決 90% 的 PM 設定問題。
>
> 精簡版快速上手指南：[docs/quick-start-zh.md](docs/quick-start-zh.md)

## 運作原理

### 三層架構

| 層級 | 位置 | 載入時機 | 內容 |
|------|------|---------|------|
| **L1 — 工作區** | `CLAUDE.md` + `.claude/rules/` | 每次對話 | 策略師人設、委派規則 |
| **L2 — 公司** | `.claude/rules/{company}/` | 每次對話 | 技能路由、PR 慣例、JIRA 工作流程 |
| **L3 — 專案** | `{company}/{project}/CLAUDE.md` | 在專案中工作時 | Lint 設定、測試模式、元件慣例 |

規則始終載入。技能依需求載入——觸發前不會消耗 context。

### 工作流程編排

技能互相串聯以自動化完整的票單生命週期。詳見 **[開發者工作流程指南](docs/workflow-guide.zh-TW.md)**，包含：
- 票單生命週期（Feature / Bug / Hotfix 路徑）
- AC 關閉閘門（4 個自動化檢查點）
- 技能呼叫圖（技能如何互相調用）
- Code Review 和學習管線

> 你的公司可能有客製化版本在 `{company}/docs/rd-workflow.md`。

### 目錄結構

```
your-workspace/
├── CLAUDE.md                  # Strategist persona + delegation rules
├── workspace-config.yaml      # Company routing (gitignored; copy from .example)
├── .claude/
│   ├── rules/                 # Universal rules (L1)
│   │   └── {company}/         # Company rules (L2)
│   └── skills/                # 34 workflow skills
├── _template/                 # Template for new companies + rule examples
├── scripts/                   # Sync utilities
└── {company}/                 # Your company directory
    ├── workspace-config.yaml  # Company config (projects, JIRA, etc.)
    ├── {project-a}/           # Project with its own CLAUDE.md (L3)
    └── {project-b}/
```

## 多公司設定

Polaris 支援在單一工作區中管理多家公司。每家公司擁有獨立的設定、規則和技能：

```
your-workspace/
├── workspace-config.yaml          # Routes JIRA keys to companies
├── .claude/rules/
│   ├── *.md                       # Universal rules (all companies)
│   ├── acme/                      # Acme-specific rules
│   └── bigcorp/                   # BigCorp-specific rules
├── .claude/skills/
│   ├── *.md (or dirs)             # Shared skills (version-controlled)
│   ├── acme/                      # Acme-only skills (gitignored)
│   └── bigcorp/                   # BigCorp-only skills (gitignored)
├── acme/                          # Acme projects + config
└── bigcorp/                       # BigCorp projects + config
```

**隔離機制：**

- **設定路由** — `workspace-config.yaml` 將 JIRA 專案前綴對應到公司。當你說「做 ACME-123」，Polaris 會讀取 Acme 的設定
- **規則範圍** — 所有規則都會載入到每次對話（Claude Code 限制），但公司規則包含範圍標頭。策略師只會套用與當前活躍公司相符的規則
- **技能隔離** — 共用技能在 `.claude/skills/`（由 git 追蹤）。公司專屬技能放在 `.claude/skills/{company}/`（已 gitignore）
- **診斷工具** — 執行 `/which-company PROJ-123` 查看票單路由到哪家公司，`/use-company` 明確設定 context，或 `/validate-isolation` 掃描範圍標頭問題和 memory 標籤違規

**新增第二家公司：**

```
/init
```

精靈會偵測現有的公司，並在旁邊建立新的公司。設定完成後，執行 `/validate-isolation` 確認沒有規則缺少範圍標頭。

> **注意：** 如果兩家公司共用相同的 JIRA 專案前綴，請使用 `/use-company` 明確設定 context——自動路由無法區分它們。
>
> 完整的範圍策略請參閱 `.claude/rules/multi-company-isolation.md`。

## 自訂設定

| 做什麼 | 在哪裡 | 怎麼做 |
|--------|-------|--------|
| 新增公司 | 執行 `/init` | 互動式精靈建立一切 |
| 對應 JIRA 專案到 repo | `{company}/workspace-config.yaml` | 在 `projects:` 新增項目 |
| 新增公司專屬規則 | `.claude/rules/{company}/` | 建立 `.md` 檔案——每次對話自動載入 |
| 新增專案專屬規則 | `{company}/{project}/CLAUDE.md` | sub-agent 進入專案時載入 |
| 建立新技能 | 執行 `/skill-creator` | 引導式技能建立，含評估 |
| 修改技能路由 | `.claude/rules/{company}/skill-routing.md` | 對應觸發詞 → 技能 |

## 不要動的檔案

這些是框架內部檔案。除非你在修改 Polaris 框架本身，否則不要編輯：

| 路徑 | 原因 |
|------|------|
| `.claude/skills/*/SKILL.md` | 技能定義——使用 `/skill-creator` 修改 |
| `.claude/skills/references/` | 技能使用的共用資料（估點量表、模板） |
| `.claude/rules/*.md`（L1） | 通用規則——每次對話載入 |
| `_template/` | `/init` 精靈的模板 |
| `scripts/` | 模板與實例之間的同步工具 |
| `CLAUDE.md` | 策略師人設——框架的大腦 |

**可以安全編輯：**

| 路徑 | 可自訂的內容 |
|------|-------------|
| `.claude/rules/{company}/` | 你公司的慣例、路由、JIRA 工作流程 |
| `{company}/workspace-config.yaml` | JIRA 專案、Slack 頻道、repo 對應 |
| `{company}/{project}/CLAUDE.md` | 專案專屬規則（L3） |

## 升級

如果你從 Polaris 模板 clone 下來，想要拉取框架更新：

```bash
# From the Polaris template repo:
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template [--dry-run]
```

這會同步技能、規則和參考資料，同時保留你的公司設定、L2 規則和專案專屬檔案。使用 `--dry-run` 在套用前預覽變更。

> 完整選項請參閱 `scripts/sync-from-polaris.sh --help`。

## 關於名稱

> Polaris — 靈感來自張良，先傾聽、再謀劃、在幕後影響結局的策略師。

## 致謝

Polaris 從以下開源專案汲取靈感：

| 專案 | 作者 | 我們學到的 |
|------|------|-----------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic 技能框架、spec-first 開發、sub-agent 任務分工 |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI 驅動的開發環境管理、`/init` smartSelect 互動、audit trail |

## 授權

[MIT](LICENSE)
