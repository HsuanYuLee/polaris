---
name: codex-mcp-setup
description: "Use when the user wants to set up or sync Codex MCP servers for Polaris workflows. Trigger: 'codex mcp', '同步 mcp', '設定 codex mcp', '讓 codex 接 mcp', 'codex mcp setup'."
---

# Codex MCP Setup

使用者希望 Codex 使用與 Claude-side Polaris workflows 相同的 external integrations 時，使用此 skill。

## Workflow

### 1) Preview planned MCP changes

執行：

```bash
bash scripts/sync-codex-mcp.sh --dry-run
```

這會檢查 baseline servers 是否已存在：
- `claude_ai_Atlassian`
- `claude_ai_Slack`

### 2) Apply MCP configuration

執行：

```bash
bash scripts/sync-codex-mcp.sh --apply --login
```

注意：
- `--login` 可能會在瀏覽器開啟 interactive OAuth。
- 若 OAuth 失敗，流程繼續，並告知使用者手動執行 `codex mcp login <name>`。

### 3) Optional Google Calendar

若使用者希望 Codex 使用 Calendar，使用 streamable server URL：

```bash
bash scripts/sync-codex-mcp.sh --apply --login \
  --with-google-calendar-url "<MCP_SSE_URL>" \
  --google-calendar-token-env "<TOKEN_ENV_VAR>"
```

### 4) Keep skills in sync for Codex

執行：

```bash
mise run cross-runtime-sync
bash scripts/mechanism-parity.sh --strict
bash scripts/polaris-codex-doctor.sh
```

### 5) Report

摘要需包含：
- 新增或已存在的 MCP servers。
- 每個 server 的 login status。
- 需要人工處理的 follow-up。
