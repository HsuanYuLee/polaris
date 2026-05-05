<p align="center">
  <img src="docs-manager/src/assets/polaris-logo.png" alt="Polaris" width="320">
</p>

[English](./README.md) | 中文

# Polaris

Polaris 是支援 Claude Code / Codex 的工作區 harness，適合使用 JIRA、GitHub、Slack、Confluence 跑研發流程的團隊。它讓 coding agent 擁有穩定的 workflow skills、本機團隊 context、deterministic gates，以及能把日常修正沉澱下來的 learning loop，讓 agent 依照你的工作方式執行，而不是每個 session 重新猜。

Polaris 是 add-on layer。它擁有 framework instructions、skills、hooks，以及 `{company}/` 底下 ignored 的本機公司 context；產品 repo 仍保有 tracked `CLAUDE.md`、`AGENTS.md`、`.github/**` 與 repo-owned AI config 的所有權。

## 可以做什麼

| 工作流程 | Prompt | 結果 |
|---|---|---|
| 從票單開發 | `work on PROJ-123` / `做 PROJ-123` | 讀 JIRA、檢查前置、估點、開 branch、實作、測試、開 PR |
| 診斷 bug | `fix bug PROJ-456` / `修 bug PROJ-456` | 找根因、提出修正、驗證行為、交付 patch |
| Review PR | `review PR` / `review 這個 PR` | 讀 diff，依專案規則留下 inline review comments |
| Sprint planning | `sprint planning` / `排 sprint` | 拉 backlog、檢查容量、偵測 carry-over、草擬 release planning output |
| 產出 standup | `standup` | 收集 JIRA、git、calendar 活動，整理成團隊更新 |
| 外部學習 | `learn from <url>` / `學習這個 <url>` | 研讀外部資料或 merged PR，把有用模式沉澱成 workspace knowledge |

先選一個工作流程開始即可。完整技能清單請看 [開發者工作流程指南](docs/workflow-guide.zh-TW.md) 與 [中文觸發詞](docs/chinese-triggers.md)。

## 運作方式

Polaris 把 agent 行為分成三層：

| 層級 | 來源 | 用途 |
|---|---|---|
| Workspace | `CLAUDE.md`, `.claude/rules/`, `.claude/skills/` | 共用 strategist 行為、skills、hooks、deterministic rules |
| Company | ignored `.claude/rules/{company}/`, `{company}/workspace-config.yaml` | 公司專屬 JIRA、Slack、GitHub 與流程慣例 |
| Project | ignored `{company}/polaris-config/{project}/handbook/` | Repo handbook、generated scripts、test commands、runtime hints、本機 context |

Skills 只在被觸發時載入。Rules 和 hooks 則提供常駐護欄：語言政策、安全檢查、PR body 驗證、task artifact 驗證、context continuity 與 workflow gates。

## 前置需求

所有人都需要：

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)，或依照 [Polaris for Codex](docs/codex-quick-start.zh-TW.md) 設定的 Codex
- Atlassian MCP，連接 JIRA 與 Confluence
- Slack MCP，用於通知、standup、review workflows

請從 workspace root 使用 coding-agent runtime，不是一般 browser chat。下方 prompt 是輸入到 Claude Code 或 Codex 對話中。

開發者另外需要：

- Git
- 已通過組織認證的 GitHub CLI (`gh`)

選配整合：

- Google Calendar MCP，讓 standup 帶入會議脈絡
- Figma MCP，供引用設計稿的票單使用

大多數多步驟 workflow 會使用 sub-agent。Claude Code 需要 Max plan 或 API access 才能完整使用。

### MCP 設定

Claude Code 可透過 `/mcp` 連接 MCP servers：

- Slack: `https://mcp.slack.com/mcp`
- Atlassian: `https://mcp.atlassian.com/v1/mcp`

Codex 可以鏡像同一組 connectors：

```bash
codex mcp add claude_ai_Slack --url https://mcp.slack.com/mcp
codex mcp add claude_ai_Atlassian --url https://mcp.atlassian.com/v1/mcp
codex mcp login claude_ai_Slack
codex mcp login claude_ai_Atlassian
codex mcp list
```

本 framework 已不建議使用舊的 stdio `npx @anthropic-ai/claude-code-mcp-*` 設定。

## 快速上手

### 1. 建立 workspace

在 GitHub 使用 [Polaris template repo](https://github.com/HsuanYuLee/polaris)，再 clone 你的新 workspace：

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

建議使用專用目錄名稱。如果你已經把 `~/work` 用於產品 repo，請避免把 Polaris workspace 也放在同一路徑。

### 2. Onboard 公司

從 workspace root 開啟 Claude Code 或 Codex，然後在 agent 對話中輸入：

```text
請幫我 onboard Polaris workspace，設定我的公司
```

Onboard flow 會偵測 GitHub org 和 repos、建立 ignored company context、把 JIRA key 對應到本機 repo，最後輸出 readiness dashboard：`ready`、`partial` 或 `blocked`。

如果 dashboard 不是 `ready`，執行：

```text
onboard repair
```

### 3. 試一個真實 workflow

使用你 JIRA 專案裡的真實 ticket key：

```text
做 PROJ-123
```

PM 和 Scrum Master 可以從這個開始：

```text
standup
```

角色導向設定清單請看 [PM 設定清單](docs/pm-setup-checklist.zh-TW.md)。Codex runtime 設定請看 [Polaris for Codex](docs/codex-quick-start.zh-TW.md)。

## Repo 結構

```text
your-workspace/
├── CLAUDE.md                  # Strategist instructions
├── AGENTS.md                  # Generated runtime bootstrap for coding agents
├── workspace-config.yaml      # 本機 company routing，git ignored
├── .claude/
│   ├── rules/                 # Universal 與 company-scoped rules
│   └── skills/                # Workflow skills
├── docs/                      # Public guides
├── scripts/                   # Deterministic gates and workflow helpers
└── {company}/                 # Ignored local company context
    ├── workspace-config.yaml
    ├── polaris-config/
    │   └── {project}/handbook/
    └── {project}/             # Product repo；repo-owned files 仍由產品 repo 擁有
```

## 文件入口

| 需求 | 文件 |
|---|---|
| 完整開發生命週期 | [開發者工作流程指南](docs/workflow-guide.zh-TW.md) |
| 中文觸發詞 | [中文觸發詞](docs/chinese-triggers.md) |
| PM / 非開發者設定 | [PM 設定清單](docs/pm-setup-checklist.zh-TW.md) |
| Codex 設定 | [Polaris for Codex](docs/codex-quick-start.zh-TW.md) |
| 中文快速上手 | [中文快速上手](docs/quick-start-zh.md) |

## 自訂

可以安全自訂的位置：

| 做什麼 | 在哪裡 |
|---|---|
| 公司 routing 與 integrations | `{company}/workspace-config.yaml` |
| 公司工作流程慣例 | `.claude/rules/{company}/` |
| 專案 handbook 與 generated scripts | `{company}/polaris-config/{project}/` |
| 新 workflow skill | 使用 `skill-creator` |

`.claude/skills/*/SKILL.md`、`.claude/skills/references/`、`.claude/rules/*.md`、hooks、scripts 等 framework internals，只有在修改 Polaris 本身時才應該變更。

## 升級

從 Polaris template checkout 拉 framework updates：

```bash
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template --dry-run
./scripts/sync-from-polaris.sh --polaris ~/path-to-polaris-template
```

Sync 會保留 ignored company context、company rules 和 project-specific files。Apply mode 也會執行 Claude Code / Codex 的 cross-runtime parity checks。

## 安全性

Polaris 採 local-first 設計：

- 無 telemetry、analytics、usage reporting
- Framework 不會 phone home
- Memories、learnings、timelines、checkpoints 都儲存在本機
- Shell-level safety hooks 會攔截危險指令
- PR、JIRA、Slack、Confluence、commit、release 等 downstream prose 會先過 workspace language gates
- Skills、rules、scripts 都是可在 git 中審計的 plaintext files

網路活動來自你明確呼叫的工具，例如 git、`gh`、JIRA、Slack、Confluence 或 MCP connectors。

## 致謝

Polaris 從以下開源專案汲取靈感：

| 專案 | 作者 | 我們學到的 |
|---|---|---|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills framework、spec-first development、sub-agent task division |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven dev environment management、onboarding smartSelect interaction、audit trail |
| [get-shit-done](https://github.com/gsd-build/get-shit-done) | TÂCHES | Context engineering patterns、goal-backward verification、sub-agent completion envelope、complexity tier routing |
| [skill-sanitizer](https://github.com/cyberxuan-XBX/skill-sanitizer) | cyberxuan-XBX | Pre-LLM security scanning、code block context awareness、severity scoring with false-positive reduction |
| [Kubernetes](https://github.com/kubernetes/kubernetes)、[Vite](https://github.com/vitejs/vite)、[VS Code](https://github.com/microsoft/vscode)、[Home Assistant](https://github.com/home-assistant/core) | OSS communities | README 結構：清楚的 project identity、role-based entry points、短 setup path、詳細文件連結 |

## 授權

[MIT](LICENSE)
