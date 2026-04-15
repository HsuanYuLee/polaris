# Polaris 給 Codex 用（相容層）

這個 workspace 原本以 Claude Code 為主，但可以在 Codex 套用同一套 Polaris 工作流。

## 相容範圍

- 直接沿用既有資產：`CLAUDE.md`、`.claude/rules/`、`.claude/skills/`
- 觸發語句不變（例如：`「做 PROJ-123」`、`「standup」`、`「refinement EPIC-100」`）
- 由 Codex 直接讀 `SKILL.md` 並執行步驟

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

Codex 會從 `.agents/skills` 讀取 repo skills。先把 Polaris skills 同步過去：

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents
```

若你想避免雙份檔案，可用 `--link`（建立 `.agents/skills -> .claude/skills` 符號連結）。

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
