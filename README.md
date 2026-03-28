# Polaris

> *You are the north star. Let me bring your vision to life.*
>
> *你是一切的指引，讓我來幫你實現。*

---

[English](#english) | [中文](#中文)

---

<a id="english"></a>

## English

Polaris is a workspace template for [Claude Code](https://claude.ai/claude-code) that turns natural language into structured execution — across any industry, any team, any scale.

You set the direction. AI navigates.

### What It Does

You sit at the center. Polaris routes your intent to specialized AI agents, enforces your rules, and delivers results.

| Capability | Skills |
|-----------|--------|
| **Task management** | `work-on` (smart router), `start-dev`, `fix-bug` |
| **Estimation & planning** | `jira-estimation`, `epic-breakdown`, `refinement`, `scope-challenge`, `sprint-planning` |
| **Code quality** | `dev-quality-check`, `verify-completion`, `tdd`, `unit-test`, `unit-test-review` |
| **PR lifecycle** | `git-pr-workflow`, `pr-convention`, `fix-pr-review` |
| **Code review** | `review-pr`, `review-inbox`, `check-pr-approvals`, `review-lessons-graduation` |
| **Debugging** | `systematic-debugging` |
| **Learning** | `learning` (external resources + review pattern mining) |
| **Reporting** | `standup`, `worklog-report`, `jira-worklog` |
| **Utilities** | `jira-branch-checkout`, `wt-parallel`, `auto-improve`, `dev-guide` |

### Architecture

```
polaris/
├── CLAUDE.md                          ← L1: Commander persona (your constitution)
├── workspace-config.yaml              ← Root config (company routing)
├── _template/
│   └── workspace-config.yaml          ← Template for new companies
│
├── .claude/
│   ├── settings.json                  ← Permission & hook config
│   ├── hooks/                         ← Quality gates
│   ├── rules/
│   │   ├── bash-command-splitting.md  ← L1: Universal rules
│   │   └── company/                   ← L2: Organization rules (customize these)
│   └── skills/                        ← Workflow skills (loaded on demand)
│       └── references/                ← Shared reference docs
│
└── company/                           ← Your organization folder
    ├── workspace-config.yaml          ← Company settings (gitignored)
    ├── project-a/                     ← L3: Project-specific rules
    ├── project-b/
    └── docs/
```

### Three-Layer Governance

| Layer | Location | Loaded | Analogy |
|-------|----------|--------|---------|
| **L1 — Workspace** | `CLAUDE.md` + `rules/` | Every conversation | Constitution |
| **L2 — Organization** | `rules/company/` | Every conversation | Federal law |
| **L3 — Project** | `company/project/CLAUDE.md` | When agent enters project | Local regulation |

Skills are loaded on demand — they don't occupy context until invoked.

**Multi-org support**: Create multiple organization folders. Each develops its own L2 rules and L3 projects independently, while sharing the L1 foundation.

```
polaris/
├── acme-corp/          ← Org A: SaaS company
│   ├── .claude/rules/  ← Org A's laws
│   ├── frontend/
│   └── backend/
├── side-project/       ← Org B: Personal venture
│   ├── .claude/rules/
│   └── mvp/
└── research-lab/       ← Org C: Academic project
    ├── .claude/rules/
    └── experiments/
```

### Quick Start

#### 1. Clone

```bash
git clone https://github.com/HsuanYuLee/polaris.git my-workspace
cd my-workspace
```

#### 2. Initialize Your Company

```bash
# Option A: Interactive wizard (recommended)
claude
> /init

# Option B: Manual setup
mkdir my-company
cp _template/workspace-config.yaml my-company/workspace-config.yaml
# Edit my-company/workspace-config.yaml with your values
# Then update root workspace-config.yaml:
# companies:
#   - name: my-company
#     base_dir: "~/work/my-company"
```

#### 3. Set Up Projects

Clone or symlink your project repos into your company folder. Each project can have its own `CLAUDE.md` and `.claude/rules/`.

#### 4. Start Commanding

```bash
claude
```

Use natural language:
- `work on PROJ-123` — smart router: estimates, creates branch, implements
- `fix bug PROJ-456` — end-to-end bug fix workflow
- `review PR https://github.com/...` — structured code review
- `create PR` — quality check + PR creation
- `standup` — generate daily standup report

See [ONBOARDING.md](ONBOARDING.md) for the full setup guide.

### Customization

**Adding Skills** — Create new skills in `.claude/skills/your-skill/SKILL.md`. Use `/skill-creator` for proper scaffolding.

**Modifying Rules** — Edit `rules/company/` to match your team's culture: skill routing, PR policies, JIRA workflows, scenario playbooks.

**Config-Driven** — Most skills read `workspace-config.yaml` at runtime. Change config to adapt behavior without touching skill code.

### Integrations

All optional — leave config sections empty to disable:

| Integration | What It Enables |
|------------|----------------|
| **JIRA** | Ticket management, estimation, status transitions, branch naming |
| **GitHub** | PR creation, review, approval tracking |
| **Confluence** | Technical documents, standup reports, release pages |
| **Slack** | Review notifications, AI status updates, reports |

### Beyond Software

The architecture — intent routing, rule governance, agent delegation — applies to any domain. Replace the skills, rewrite the rules, and Polaris becomes your command center for operations, research, legal review, or whatever you govern.

---

<a id="中文"></a>

## 中文

Polaris 是一個 [Claude Code](https://claude.ai/claude-code) 工作空間模板，用自然語言驅動結構化執行 — 不限產業、不限團隊、不限規模。

你決定方向，AI 負責實現。

### 它做什麼

你坐鎮中央。Polaris 將你的意圖路由給專業 AI agent，執行你定下的規則，交付成果。

| 能力 | Skills |
|-----|--------|
| **任務管理** | `work-on`（智慧路由）、`start-dev`、`fix-bug` |
| **估點與規劃** | `jira-estimation`、`epic-breakdown`、`refinement`、`scope-challenge`、`sprint-planning` |
| **程式碼品質** | `dev-quality-check`、`verify-completion`、`tdd`、`unit-test`、`unit-test-review` |
| **PR 生命週期** | `git-pr-workflow`、`pr-convention`、`fix-pr-review` |
| **Code Review** | `review-pr`、`review-inbox`、`check-pr-approvals`、`review-lessons-graduation` |
| **除錯** | `systematic-debugging` |
| **學習** | `learning`（外部資源 + PR review 模式萃取） |
| **報告** | `standup`、`worklog-report`、`jira-worklog` |
| **工具** | `jira-branch-checkout`、`wt-parallel`、`auto-improve`、`dev-guide` |

### 架構

```
polaris/
├── CLAUDE.md                          ← L1：指揮官人格（你的憲法）
├── workspace-config.yaml              ← Root config（公司路由）
├── _template/
│   └── workspace-config.yaml          ← 新公司範本
│
├── .claude/
│   ├── settings.json                  ← 權限與 hook 設定
│   ├── hooks/                         ← 品質閘門
│   ├── rules/
│   │   ├── bash-command-splitting.md  ← L1：通用規則
│   │   └── company/                   ← L2：組織規則（自訂）
│   └── skills/                        ← 工作流 skills（按需載入）
│       └── references/                ← 共用參考文件
│
└── company/                           ← 你的組織資料夾
    ├── workspace-config.yaml          ← 公司設定（gitignored）
    ├── project-a/                     ← L3：專案級規則
    ├── project-b/
    └── docs/
```

### 三層治理

| 層級 | 位置 | 載入時機 | 比喻 |
|------|------|---------|------|
| **L1 — 工作空間** | `CLAUDE.md` + `rules/` | 每次對話 | 憲法 |
| **L2 — 組織** | `rules/company/` | 每次對話 | 聯邦法律 |
| **L3 — 專案** | `company/project/CLAUDE.md` | Agent 進入專案時 | 地方法規 |

Skills 按需載入 — 不呼叫就不佔 context。

**多組織支援**：建立多個組織資料夾，各自發展自己的 L2 規則和 L3 專案，共享 L1 基礎。

### 快速開始

#### 1. Clone

```bash
git clone https://github.com/HsuanYuLee/polaris.git my-workspace
cd my-workspace
```

#### 2. 初始化公司

```bash
# 方法 A：互動式精靈（推薦）
claude
> /init

# 方法 B：手動設定
mkdir my-company
cp _template/workspace-config.yaml my-company/workspace-config.yaml
# 編輯 my-company/workspace-config.yaml 填入你的值
# 然後更新 root workspace-config.yaml：
# companies:
#   - name: my-company
#     base_dir: "~/work/my-company"
```

#### 3. 建立專案

將專案 repo clone 或 symlink 到公司資料夾。每個專案可以有自己的 `CLAUDE.md` 和 `.claude/rules/`。

#### 4. 開始指揮

```bash
claude
```

用自然語言：
- `做 PROJ-123` — 智慧路由：估點、建分支、實作
- `修 bug PROJ-456` — 端到端 bug 修正流程
- `review PR https://github.com/...` — 結構化 code review
- `發 PR` — 品質檢查 + PR 建立
- `standup` — 產生每日站立會議報告

完整設定指引請見 [ONBOARDING.md](ONBOARDING.md)。

### 自訂

**新增 Skill** — 在 `.claude/skills/your-skill/SKILL.md` 建立。用 `/skill-creator` 確保結構完整。

**修改規則** — 編輯 `rules/company/` 裡的檔案，匹配你團隊的文化：skill 路由、PR 規範、JIRA 流程、場景劇本。

**Config 驅動** — 大部分 skill 在執行時讀取 `workspace-config.yaml`。改設定就能改行為，不需動 skill 程式碼。

### 整合

全部選配 — 留空即停用：

| 整合 | 啟用功能 |
|------|---------|
| **JIRA** | 單據管理、估點、狀態轉換、分支命名 |
| **GitHub** | PR 建立、review、approve 追蹤 |
| **Confluence** | 技術文件、standup 報告、release page |
| **Slack** | Review 通知、AI 狀態更新、報告 |

### 超越軟體

這套架構 — 意圖路由、規則治理、agent 委派 — 適用於任何領域。替換 skills、重寫 rules，Polaris 就成為你的營運中心、研究指揮部、法務審查平台，或任何你需要治理的場域。

---

## License

MIT
