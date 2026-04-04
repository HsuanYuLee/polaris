---
name: jira-worklog
description: >
  Logs work time to JIRA after completing a ticket implementation. Use when the user
  explicitly asks to log work time, or when another skill (like git-pr-workflow)
  delegates worklog recording after PR creation. Trigger keywords: "worklog", "log time",
  "time tracking", "記工時", "記錄工時", "log hours".
metadata:
  author: Polaris
  version: 1.1.0
---

# JIRA Worklog

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. Identify the JIRA ticket

Extract the ticket key from (in priority order):
1. Current branch name: `task/PROJ-419-*` → `PROJ-419`
2. Conversation context (ticket mentioned earlier)
3. Ask the user

### 2. Estimate time spent

| Scope                                  | Estimate   |
|----------------------------------------|------------|
| Simple code removal / config change    | 10–15m     |
| Small feature / bug fix (1–3 files)    | 15–30m     |
| Medium feature (3–10 files)            | 30m–1h     |
| Large feature (10+ files, multi-step)  | 1h–2h      |

Round to the nearest 5 minutes. Format: `Xh Ym` (e.g. `15m`, `1h`, `1h 30m`).

Present the estimate to the user for confirmation before logging.

### 3. Log the worklog

```
mcp__claude_ai_Atlassian__addWorklogToJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  timeSpent: <TIME>
```

### 4. Confirm

> Logged **\<TIME>** to \<TICKET>.


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
