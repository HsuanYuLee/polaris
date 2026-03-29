# Work — Multi-company AI Workspace

跨公司/跨專案的 AI 開發工作空間。在這裡啟動 Claude Code，用自然語言驅動整個開發流程。

## 結構

```
work/
├── CLAUDE.md                  ← L1: 通用 AI 指揮官 persona
├── workspace-config.yaml      ← Root config（公司路由）
├── _template/                 ← 新公司範本
│   └── workspace-config.yaml
├── .claude/
│   ├── rules/                 ← L1: 通用規則 (bash-splitting)
│   │   └── your-company/             ← L2: 公司級規則 (routing, PR, JIRA, etc.)
│   └── skills/                ← RD flow skills (work-on, fix-bug, review-pr, ...)
│
├── your-company/                     ← 公司資料夾
│   ├── workspace-config.yaml  ← 公司設定（gitignored）
│   ├── README.md              ← YourOrg 詳細使用說明
│   ├── setup.sh               ← 一鍵初始化
│   ├── docs/rd-workflow.md    ← RD 工作流程手冊
│   ├── your-app/         ← L3: 專案（各自有 CLAUDE.md + .claude/rules/）
│   ├── your-design-system/
│   └── ...
```

## 三層閱讀架構

| 層級 | 位置 | 載入時機 | 內容 |
|------|------|---------|------|
| **L1 — Workspace** | `CLAUDE.md` + `rules/` | 每次對話自動載入 | 通用 persona、委派原則、bash 規則 |
| **L2 — Company** | `rules/your-company/` | 每次對話自動載入 | Skill routing、PR/Review、JIRA、場景 playbook |
| **L3 — Project** | `your-company/your-app/CLAUDE.md` | Sub-agent 進入專案時載入 | 專案特定規範（lint、test、元件慣例） |

Skills 按需載入（透過 Skill tool），不佔每次對話的 context。

## Quick Start

見 [your-company/README.md](your-company/README.md)。

## Acknowledgements

Polaris 的設計從以下開源專案獲得啟發，感謝作者們的分享：

| Project | Author | What we learned |
|---------|--------|----------------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Agentic skills 框架、spec-first 開發流程、sub-agent 任務分工模式 |
| [ab-dotfiles](https://github.com/AlvinBian/ab-dotfiles) | Alvin Bian | AI-driven 開發環境管理、/init 精靈的 smartSelect 互動模式與 audit trail 概念 |
