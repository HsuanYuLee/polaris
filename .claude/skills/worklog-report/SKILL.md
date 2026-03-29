---
name: worklog-report
description: >
  Query Jira project for tickets in Done/Launched/Closed status, group by
  assignee, and send the report to Slack. Use when asked for: "worklog report",
  "done report", "sprint report", "完成報告", or when someone
  asks what tickets were finished in a date range or sprint.
  Supports two modes: date range (e.g. "2w", "1m") and sprint (e.g. "sprint:Q2 S1").
metadata:
  author: Polaris
  version: 1.0.0
---

# Done Report

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects[].key`（報告用的專案）、`slack.channels.default_report`（或 `slack.channels.web_automation_test`）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

Query Jira for Done/Launched/Closed tickets in the configured project(s), group by assignee, and post to Slack.

**Modes:**
- **Date range** (default): tickets that transitioned to done within a time window
- **Sprint**: all done tickets in a specific sprint

## 1. Parse arguments

`$ARGUMENTS` format: `[FILTER] [channel_id]`

| Arg | Format | Example |
|-----|--------|---------|
| Date range | `1w`, `2w`, `1m`, `3m` | `2w` (default if omitted) |
| Sprint | `sprint:{name}` | `sprint:Q2 S1` |
| Channel | Starts with `C`, no spaces | `{config: slack.channels.default_report}` |

Default channel: `{config: slack.channels.default_report}`（config: `slack.channels.default_report`，fallback: see `references/shared-defaults.md`）

## 2. Query Jira

Use `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql`. Retrieve fields: `key`, `summary`, `status`, `assignee`. Handle pagination via `startAt`/`maxResults`.

**Date range:**
```
project = {config: jira.projects[].key} AND status in ("Done","Launched","Closed") AND status changed to ("Done","Launched","Closed") AFTER "-{DATE_RANGE}"
```

**Sprint:**
```
project = {config: jira.projects[].key} AND sprint = "{SPRINT_NAME}" AND status in ("Done","Launched","Closed")
```

## 3. Group and sort

- Group by `assignee.displayName`; unassigned → "*Unassigned*"
- Sort assignees alphabetically; sort tickets within each group by key

## 4. Format message (Slack mrkdwn)

```
*Done Report*
Period: last {DATE_RANGE}   ← or "Sprint: {SPRINT_NAME}"
Total: {TOTAL_COUNT} tickets

*{Assignee}* ({count})
- <https://{config: jira.instance}/browse/{KEY}|{KEY}> - {Summary} [{Status}]（config: `jira.instance`，fallback: your-domain.atlassian.net）
```

Use `<URL|label>` for clickable Jira links. Include status label per ticket.

## 5. Send to Slack

- Channel arg looks like an ID (starts with `C`) → use directly
- Otherwise, use `mcp__claude_ai_Slack__slack_search_channels` with `channel_types: "public_channel,private_channel"` to resolve name → ID

Send with `mcp__claude_ai_Slack__slack_send_message`. Confirm:
```
Done Report sent to #{channel_name}! ({TOTAL_COUNT} tickets, {ASSIGNEE_COUNT} assignees)
```

## Do / Don't

- Do: paginate when results exceed one page
- Do: resolve channel name to ID before sending
- Don't: skip assignee grouping even for a single assignee

## Prerequisites

- Atlassian MCP integration (for Jira JQL queries)
- Slack MCP integration (for sending messages and resolving channel names)
