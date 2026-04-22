---
name: codex-mcp-setup
description: "Use when the user wants to set up or sync Codex MCP servers for Polaris workflows. Trigger: 'codex mcp', '同步 mcp', '設定 codex mcp', '讓 codex 接 mcp', 'codex mcp setup'."
---

# Codex MCP Setup

Use this skill when the user wants Codex to use the same external integrations as Claude-side Polaris workflows.

## Workflow

### 1) Preview planned MCP changes

Run:

```bash
bash scripts/sync-codex-mcp.sh --dry-run
```

This checks whether baseline servers already exist:
- `claude_ai_Atlassian`
- `claude_ai_Slack`

### 2) Apply MCP configuration

Run:

```bash
bash scripts/sync-codex-mcp.sh --apply --login
```

Notes:
- `--login` may open interactive OAuth in browser.
- If OAuth fails, continue and tell the user to run `codex mcp login <name>` manually.

### 3) Optional Google Calendar

If user wants Calendar in Codex, use streamable server URL:

```bash
bash scripts/sync-codex-mcp.sh --apply --login \
  --with-google-calendar-url "<MCP_SSE_URL>" \
  --google-calendar-token-env "<TOKEN_ENV_VAR>"
```

### 4) Keep skills in sync for Codex

Run:

```bash
bash scripts/sync-skills-cross-runtime.sh --to-agents --link
bash scripts/mechanism-parity.sh --strict
bash scripts/polaris-codex-doctor.sh
```

### 5) Report

Summarize:
- Added / already existing MCP servers
- Login status per server
- Any manual follow-up needed
