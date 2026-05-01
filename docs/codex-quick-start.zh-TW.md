# Polaris 給 Codex 用

Polaris 已把 Codex 納入一等 runtime：共用同一份 `.claude/**` 來源資產，並產生 Codex 端的 skills、rules 與 MCP 設定鏡像。

## 支援範圍

- 直接沿用既有資產：`CLAUDE.md`、`.claude/rules/`、`.claude/skills/`
- 觸發語句不變（例如：`「做 PROJ-123」`、`「standup」`、`「refinement EPIC-100」`）
- 由 Codex 直接讀 `SKILL.md` 並執行步驟
- 單一維護來源放在 `.claude/**`；`.agents/**` 與 `.codex/**` 視為產生物，不手動編輯

## 在 Codex 下的差異

| Claude Code | Codex 對應方式 |
|---|---|
| `/init` 這類 slash command | 直接用自然語言要求 Codex 初始化 |
| `Skill("engineering", ...)` | 由 Codex 讀 `.claude/skills/engineering/SKILL.md` 執行 |
| 在 Claude 設定 MCP | 改用你在 Codex runtime 可用的 MCP 連線 |

## 快速開始

### 1. Clone workspace

```bash
git clone https://github.com/YOUR-ORG/your-polaris-workspace ~/polaris-workspace
cd ~/polaris-workspace
```

### 2. 執行 Codex 健檢

```bash
bash scripts/polaris-codex-doctor.sh
```

會檢查：
- 必要工具（`git`、`gh`、`rg`）
- Polaris 核心檔案（`CLAUDE.md`、`.claude/rules/`、`.claude/skills/`）
- `workspace-config.yaml` 是否存在

### 2.5 同步 skills 到 Codex 路徑

Codex 會從 `.agents/skills` 讀取 repo skills。**建議模式是 symlink**，讓 Claude 與 Codex 共用同一份 source of truth：

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
```

這會建立 `.agents/skills -> ../.claude/skills`。

若你明確需要複製鏡像而不是 symlink，才用：

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents
```

複製模式只會輸出**公開共用 skills**（排除 `scope: maintainer-only` 與 company-specific skills），但它屬於 degraded mode，因為鏡像可能漂移。`scripts/check-skills-mirror-mode.sh` 與 cross-LLM parity 檢查預期使用 symlink 模式。

若你是 Windows 使用者或 clone 設定 `core.symlinks=false`，請見 `.claude/rules/cross-llm-skill-source-of-truth.md` 的 Platform Notes 取得修復步驟。

### 2.6 驗證機制一致性

用 parity 稽核確認 Claude/Codex skill 樹沒有漂移：

```bash
bash scripts/mechanism-parity.sh --strict
```

### 2.7 同步 Codex 的 MCP 基線

先預覽變更：

```bash
bash scripts/sync-codex-mcp.sh --dry-run
```

確認後套用並做 OAuth 登入：

```bash
bash scripts/sync-codex-mcp.sh --apply --login
```

這會在 Codex 建立 Polaris 基線 MCP servers：
- `claude_ai_Atlassian`
- `claude_ai_Slack`

### 2.8 轉譯 rules 到 Codex AGENTS

從 `.claude/rules` 產生 Codex 端規則鏡像：

```bash
bash scripts/transpile-rules-to-codex.sh
```

會產生：
- `.codex/AGENTS.md`
- `.codex/.generated/rules-manifest.txt`

### 2.9 驗證跨 LLM 一致性（可放 CI）

一個指令檢查 skills + rules 同步狀態：

```bash
bash scripts/verify-cross-llm-parity.sh
```

## 疑難排解

### 載入 skill 時出現 `invalid YAML`

這代表某個 `SKILL.md` 的 frontmatter 格式壞了。先跑：

```bash
bash scripts/polaris-codex-doctor.sh
```

如果 `.claude/skills` 和 `.agents/skills` 不一致，恢復共用 symlink：

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
```

### 出現 `MCP startup incomplete` 或 `server is not logged in`

這是 MCP connector 的登入問題，不是 Polaris skill 本身壞掉。

- `claude_ai_Atlassian` 和 `claude_ai_Slack` 是 Polaris 的基線 connector
- `figma` 是選配，只有在你要跑 Figma 相關流程時才需要

可用以下方式修正：

```bash
codex mcp login claude_ai_Slack
codex mcp login claude_ai_Atlassian
codex mcp login figma
```

如果某個選配 connector 不需要，可以直接移除：

```bash
codex mcp remove figma
```

### 3. 初始化設定（給 Codex 的提示詞）

若缺 `workspace-config.yaml`，可直接對 Codex 說：

```text
請用 workspace-config.yaml.example 建立 workspace-config.yaml，
並加上我的公司路由設定。
```

然後建立公司層設定 `{company}/workspace-config.yaml`。

### 4. 從高信號指令開始

直接用 Polaris 既有語意：

```text
做 PROJ-123
修 bug PROJ-456
review PR https://github.com/org/repo/pull/123
standup
排 sprint
```

## 建議在 Codex 的操作句型

觸發 Polaris 工作流時，建議補一句：

```text
請依 Polaris skill 流程執行。
先讀 .claude/skills/<skill>/SKILL.md 和必要 references，
完成後跑 quality gates 再回報結果。
```

這樣可以讓 Codex 行為更貼近 Polaris 的確定性 gate 設計。
